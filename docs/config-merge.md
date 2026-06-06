# Config Merge — Additive, Keyed-Set Composition

Status: implemented (both phases). Documents the two-phase change to
`_merge_configs`: Phase 1 (additive, keyed composition) and Phase 2 (delete
directives). Both pass the full CI gate.

---

## Motivation

connie composes a container's configuration from several layers. Today
`_merge_configs` folds them with yq's `*` operator:

```sh
yq eval-all '. as $item ireduce ({}; . * $item)' "$work" "$cfg"
```

`*` **replaces** arrays — it does not combine them. Combined with the fact
that `connie init` scaffolded a project `config.yml` containing an *active*
`packages: []` (the template is since inert — see the CHANGELOG), the
highest-precedence layer's empty list silently clobbered every lower layer:

```text
defaults(packages: []) → user(packages: [neovim]) → project(packages: [])
  ⇒  packages: []        # the user's neovim is read in, then wiped
```

So `connie edit-config --user` + adding `neovim` to `packages` does nothing
for any initialized project: the merged list is empty, the build arg is unchanged,
Docker hits its cache, and nothing installs. The user-level and system-level
layers are effectively dead for every list-valued key (`packages`,
`build_commands`, `ports`, `unsafe_extra_mounts`). Maps and scalars (`env`,
`resources`, `start_cmd`) already compose correctly.

The goal: every layer composes **additively** — each layer adds to, overrides
within, or (Phase 2) deletes from what lower-precedence layers established —
with a mental model simple enough to reason about, and without ever letting
config touch the container's security posture.

---

## Precedence and terminology

Layers, from **lowest precedence (most general) to highest (most specific)**:

```text
application defaults  →  system  →  user  →  project  →  env vars  →  CLI flags
   (compiled-in)        (/etc)    (~/.config)  (<slug>)   (CONNIE_*)   (--env …)
```

A **lower layer** in connie's vocabulary means *more specific* / *processed
later* / **wins**. "Lower overrides higher." This document uses that direction
throughout; it is the only source of ambiguity in the whole feature, so it is
fixed here once.

---

## Security boundary

The redesign changes only *settings*, never the container's *posture*. The
following are set at base/install time and are **not** reachable from any
config layer:

- dropped Linux capabilities, `no-new-privileges`, read-only root filesystem,
  non-root `claude-user`;
- SUID/SGID stripping — and crucially it is **re-applied after** user packages
  install (`extend.Dockerfile`), so a package shipping a setuid binary
  (`sudo`, `mount`, `su`, …) cannot be used to escalate.

Two facts that anchor the model (verified in the Dockerfiles):

- **`packages` install as root**, then SUID/SGID is re-stripped.
- **`build_commands` run as the unprivileged `claude-user`** at build time.

Consequences:

- `packages` is **not a privilege boundary** — adding tools widens the
  toolset/supply-chain surface but not the privilege model. So package
  *removal* is never a security requirement (add-only is safe).
- A `build_command` **cannot** `apk del` a package a higher layer added —
  `apk` needs root, and build commands are unprivileged. (The previously
  assumed "undo it with a build command" escape hatch does not exist.)
- The most powerful knob (arbitrary `build_commands`) is unprivileged, so it
  cannot add capabilities, un-strip setuid, or re-grant root. "Change the
  settings, not the posture" is enforced by construction.

`unsafe_extra_mounts` remains the single config key that can widen the trust
surface; it is deliberately named, guarded against catastrophic targets, and
documented as the one place trust is granted.

---

## The model: three behaviours, by data shape

Most of connie's "lists" are really **sets keyed by identity**. Recognizing
that collapses what looks like five per-key rules into three behaviours that
follow from a value's shape:

| Key | Shape | Identity | Behaviour | Delete (Phase 2) |
| --- | --- | --- | --- | --- |
| `env` | map | var name | add / override per key | `KEY: null` |
| `packages` | list of scalars | the package name | accumulate + dedupe | `-name` |
| `ports` | list `host:container` | **host port** | accumulate; lower layer overrides a host port | `"-hostport"` |
| `unsafe_extra_mounts` | list `host:container[:opts]` | **container target** | accumulate; lower layer redefines a target | `-target` |
| `build_commands` | ordered list | — (none) | **append**, in precedence order, dupes kept | none |
| `resources` | map of scalars | — | override (leaves last-win) | n/a |
| `start_cmd` | scalar | — | override | n/a |

1. **Keyed sets** (`env`, `packages`, `ports`, `unsafe_extra_mounts`): a lower
   layer adds a new key, overrides an existing key, or (Phase 2) deletes it.
   `env` already behaves exactly this way; the others are generalizations of
   it onto list-shaped data.
2. **Ordered list** (`build_commands`): append, dupes allowed, runs in
   precedence order. It is the one value with no natural key and where order
   matters — hence the exception.
3. **Scalars / scalar-maps** (`start_cmd`, `resources`): most-specific wins.

The user reasons "is this a keyed thing, an ordered thing, or a single value?"
— not five rules with three different delete tokens.

### Identity-key rationale

- **ports → host port.** Host ports are unique on the host; container ports
  legitimately repeat (`8080:80` and `9090:80` are both valid). Keying on the
  host port means a lower layer can remap or drop a host binding
  deterministically, and two entries for the same host port collapse to the
  most specific one (no invalid double-binding can be emitted).
- **mounts → container target.** Docker forbids two mounts at the same target
  but allows one source mounted to several targets. The target is the real
  uniqueness constraint, so it is the identity; a lower layer redefining a
  target changes its source/options.

---

## Merge algorithm

Verified working against a full multi-layer fixture (see "Verification"
below). Replace the single `*`-reduce with an accumulate pass plus a keyed
post-pass:

```sh
# 1. Accumulate every present layer:
#    maps deep-merge, scalars last-win, ARRAYS APPEND (note the '+').
yq eval-all '. as $item ireduce ({}; . *+ $item)' "$@" \
|
# 2. Collapse the keyed-set arrays to the most-specific entry per identity.
#    reverse | unique_by(KEY) | reverse keeps the LAST occurrence per key
#    while preserving order. build_commands/env/resources/start_cmd need no
#    post-pass — *+ already does the right thing for them.
yq '
    .packages            = (.packages // []            | unique)
  | .ports               = (.ports // []               | reverse | unique_by(split(":") | .[0]) | reverse)
  | .unsafe_extra_mounts = (.unsafe_extra_mounts // [] | reverse | unique_by(split(":") | .[1]) | reverse)
'
```

Notes:

- `_merge_configs` already skips absent layers (`[ -f ] || continue`). A
  present-but-**null** layer (the default `user.yml` is fully commented →
  null) is tolerated by `*+` — verified: it contributes nothing and the other
  layers merge normally. A regression test for it is part of Phase 1.
- Within-layer host-port collisions (`["8080:80", "8080:90"]` in one file)
  collapse to last-wins by the same keyed post-pass — no separate
  collision-detection code is needed, because keying *is* the dedup.
- Duplicate dedup for `packages` falls out of `unique`; `build_commands` is
  deliberately **not** deduped (order and repetition are meaningful).

---

## Phase 1 — additive accumulate + override (ship first)

Scope: add, override-by-key, and dedupe. **No delete sentinel yet.**

### Behaviour changes

Only the four list keys change (from replace → accumulate); `env`,
`resources`, `start_cmd` already behaved this way and are unchanged:

- `packages` — accumulate across layers, deduped. (Fixes the original
  neovim-vanishes bug.)
- `build_commands` — append in precedence order (was: replace).
- `ports` — accumulate, keyed by host port; a lower layer remaps a host port.
- `unsafe_extra_mounts` — accumulate, keyed by container target; a lower layer
  redefines a target's source/options.

### Implementation

- Rewrite `_merge_configs` to the two-step pipeline above.
- Keep the temp-file / error-handling structure already in the function.

### Tests (`tests/unit/merge_configs_*`)

- packages accumulate across three layers and dedupe a repeat.
- build_commands append in precedence order; a repeated command is kept.
- ports: distinct host ports from two layers both survive; same host port in a
  lower layer wins.
- mounts: distinct targets from two layers both survive; same target in a
  lower layer redefines source/options.
- env still merges and overrides per key (regression).
- resources / start_cmd still override (regression).
- a present-but-null layer is tolerated (the default `user.yml`).
- existing `_merge_configs` tests still pass.

### Documentation

- README + DESIGN: state the per-key merge behaviours and the keyed-set model.
- `defaults.yml`, `project.yml`, `user.yml` comments: describe accumulate /
  override per key so the templates match reality.
- CHANGELOG `[Unreleased]`.

### Done criteria

`make check` / `lint` / `test` / `format-check` all green; CI gate passed.

---

## Phase 2 — delete directives (implemented)

A lower layer can remove an entry a higher layer established. Built on Phase 1's
keyed-set foundation — the same `reverse | unique_by(identity) | reverse`
collapse, with the identity function taught to ignore a leading `-`, plus a
final pass that drops surviving directives.

### Delete syntax

One uniform rule for the list keys: **a list entry of `-<identity>` deletes the
entry with that identity**, where the identity is the same field the key is
collapsed on. For `env` (a map) the natural form is `KEY: null`.

| Key | Delete a value | Identity matched |
| --- | --- | --- |
| `packages` | `-vim` | package name |
| `ports` | `"-8080"` | host port (quote it — bare `-8080` is a YAML int) |
| `unsafe_extra_mounts` | `-/data` | container target |
| `env` | `MY_VAR: null` | var name |

A leading `-` is reserved: it cannot collide with a real value (a package name
or host path starting with `-` is invalid, and a negative host port is
meaningless), so a directive is unambiguous.

### Behaviour

- A directive is keyed by identity exactly like an add, so the most-specific
  add OR delete per identity wins — which means a more-specific layer can
  **re-add** something a less-specific layer deleted (`env` re-add works the
  same way, via last-wins over the `null`).
- Deleting an identity no layer established is a **no-op**, and the directive
  never leaks into the merged result.
- `build_commands`: **no delete** (no key; ordered). A build command also
  cannot `apk del` (it runs unprivileged), so removal is not achievable as a
  side effect either — by design.

### Implementation

In the `_merge_configs` post-pass: `env` strips null-valued keys
(`with_entries(select(.value != null))`); each list key collapses with the
identity function reading through a leading `-` (`sub("^-"; "")`), then drops
surviving `-` entries (`map(select(test("^-") | not))`). `ports` are coerced to
strings first so a `"-8080"` directive is not parsed as the integer `-8080`.

### Tests

Added to `tests/unit/merge_configs_*`: delete a package / port / mount / env
key; re-add a deleted package at a more-specific layer; delete of an absent
identity is a no-op.

---

## Out of scope

- **Admin prohibitions.** Additive composition lets the system layer *mandate*
  an entry (require-by-inclusion) but not *forbid* a user from adding one;
  arbitrary prohibitions would need a separate mechanism. The dangerous-mount
  guard remains the only hard prohibition.
- **The security posture.** cap-drop, no-new-privileges, read-only rootfs,
  SUID stripping, and the non-root user are never config-controllable.

---

## Verification log

The Phase 1 pipeline was run against application/user/project fixtures
covering every key:

- input: `packages` `[git]` / `[git, neovim]` / `[ripgrep]`; `ports`
  `[8080:80]` / `[9090:90]` / `[8080:3000]`; `unsafe_extra_mounts`
  `[/a:/data:ro]` / — / `[/a:/data:rw]`; `build_commands` one per layer;
  `env` `{A:1}` / `{B:2}` / `{A:10}`; `start_cmd` claude→sh;
  `resources.memory` 4g→8g.
- output: `packages: [git, neovim, ripgrep]`; `build_commands` appended in
  order; `env: {A: 10, B: 2}`; `ports: ["9090:90", "8080:3000"]`;
  `unsafe_extra_mounts: ["/a:/data:rw"]`; `start_cmd: sh`;
  `resources.memory: 8g`.
- within-layer collision `["8080:80", "8080:90"]` → `["8080:90"]`.

The Phase 2 delete pipeline was run against the same three layers with delete
directives:

- input: `packages` `[git, curl]` / `["-curl", vim]` / `[curl]`; `ports`
  `["8080:80"]` / `["-8080", "-9999"]` / `["8080:9000"]`; `unsafe_extra_mounts`
  `["/a:/data:ro"]` / `["-/data"]` / —; `env` `{A:1, B:2}` / `{B: null}` /
  `{B: 3}`.
- output: `packages: [git, vim, curl]` (curl deleted then re-added);
  `ports: ["8080:9000"]` (8080 deleted then re-mapped; `-9999` a no-op);
  `unsafe_extra_mounts: []` (deleted, not re-added); `env: {A: 1, B: 3}`
  (B deleted then re-added).
