# Context — Injected via Claude's `--append-system-prompt`

Status: Phase 2 (implementation) complete on branch
`context-append-system-prompt` — lint clean and the unit/integration/cli
suite green; the docker layer was updated for the new model but needs a
daemon to run. Phase 3 (docs sweep — DESIGN, README, AGENTS) remains.
Claude-specific by design — the earlier generalization (defaulting `start_cmd`
to `bash`, config-driven state mounts) is **shelved**; it made the common
Claude path fussier for little near-term gain. Replaces the bespoke CLAUDE.md
context subsystem (`_emit_*_context`, `_write_user_context`, the `cmd_context`
preview formatters, and the `CONNIE_CONTEXT` image bake) with a
`_resolve_context` helper and an inline `--append-system-prompt`;
`_generate_connie_context` is retained as the generated application scope.

---

## Motivation

connie's context handling grew exploratorily and is due for a cleanup. The aims:

- **More maintainable** — fewer moving parts than the current four-scope file
  assembly + build-arg bake + bind-mount dance.
- **Easier to configure** — context lives in plain markdown files at
  conventional paths, not baked into images or assembled from `/etc`.
- **Out of the way** — connie's context must not disturb a project's own
  configuration. Many repos check a `CLAUDE.md` into source control; it may hold
  critical instructions and must load untouched.

The enabling realization: Claude Code's `--append-system-prompt` /
`--append-system-prompt-file` flags **append** to the system prompt and leave
CLAUDE.md loading fully intact. So connie can inject its environment context as
an appended system prompt and never write, read, or shadow a project's
`CLAUDE.md`. (Verified against the CLI reference: both flags work in
**interactive** mode, append rather than replace, and the appended text is
covered by prompt caching after the first turn. See
<https://code.claude.com/docs/en/cli-reference.md>.)

---

## Invariant: the project directory is untouched

connie maps nothing into `/workspace` and writes nothing inside it. Verified in
the current code and preserved by this design:

- the only default mounts are `${project}:/workspace:rw` plus two **state**
  mounts targeting `/home/claude-user/…` — never a path under `/workspace`
  (`src/connie:674-676`);
- the dangerous-mount guard refuses any `unsafe_extra_mounts` whose target would
  shadow `/workspace` (`src/connie:654-657`);
- this redesign removes the one path that even *read* from the project dir
  (`_emit_project_context`). connie will neither read nor write the project's
  `CLAUDE.md`; Claude loads it natively.

`/workspace` is mounted read/write so **you and Claude** can edit project
files — that is the point of connie. What connie itself never does is inject,
scaffold, or overlay anything inside the repo. Context adds **no mount at all**
— the payload is passed inline (see below), not as a file. The only way
anything lands under `/workspace` is a user's explicit `unsafe_extra_mounts`
opt-in, which connie never requires.

---

## Design

Three steps, all driven by connie host-side; the container just runs `claude`.

### 1. Source the scopes

Context lives in a dedicated `context.md` beside each config layer's
`config.yml`, read host-side at `connie run`. A scope contributes only if its
file exists (the application scope is generated, so it is always present):

| Scope | Source (host) | Section heading in the prompt |
| --- | --- | --- |
| Application | *generated from merged config* | `## Container Runtime Environment` |
| Machine | `${XDG_CONFIG_DIRS%%:*}/connie/context.md` | `## Machine Context` |
| User | `$XDG_CONFIG_HOME/connie/context.md` | `## User Context` |
| Project | `$CONFIG_DIR/projects/<slug>/context.md` | `## Project Context` |

Two notes:

- The **application** scope is the one generated value — connie's live facts
  (actual resources, installed packages, exposed ports, mounts). This
  *retargets* today's `_generate_connie_context` output from a baked file into
  the appended prompt; the generator survives.
- The **project** scope here is connie's *out-of-repo* per-project context
  (it lives under connie's config dir, never in the repo) — personal notes you
  do not want checked in. It complements the repo's own `CLAUDE.md`, which
  Claude loads independently; the two never collide.

### 2. Assemble one payload

A shared `_resolve_context` reads/generates the scopes and concatenates the
present ones into a single markdown payload, each under its heading:

```text
## Container Runtime Environment     ← always (generated)
…
## Machine Context                   ← only if the machine context.md exists
…
## User Context                      ← only if the user context.md exists
…
## Project Context                   ← only if the project context.md exists
…
```

Conditional sections are trivial: `_resolve_context` already stats each file, so
an absent source simply contributes no heading. The same function backs both
`cmd_run` (which injects) and `cmd_context` (which prints), so the previewed
context is provably the injected context — the discipline `_merge_configs`
already follows.

### 3. Inject via the flag

The default `start_cmd` launches `claude` with the payload appended, so a fresh
project **just works** — `connie init` + `connie run` starts Claude with
connie's context appended and the repo's `CLAUDE.md` loading normally, with zero
per-project fiddling.

The payload is passed **inline**, baked into the command as an argv array —
`["claude", "--append-system-prompt", "<payload>"]`. Because it is an argv
element rather than a token in a `sh -c` string, there is no shell quoting at
all: the payload is one verbatim element, newlines included. This adds **no
context file and no context mount** — `connie context` provides the same
host-side inspectability an artifact would. (The only ceiling is `ARG_MAX`,
~2 MB for argv+env, which a context payload will not approach.)

This requires `_generate_override` to emit `command:` as a YAML/JSON **list**
when injecting the flag, not the scalar string it emits today — a scalar
command would be word-split and shred the multi-line payload. Composing the
flag onto a user-overridden `start_cmd` (e.g. `claude --resume`) is a Phase 2
detail: append `--append-system-prompt <payload>` as discrete trailing argv
elements; a non-`claude` `start_cmd` is the user's responsibility.

---

## Why append, not a CLAUDE.md file

- **Non-invasive by construction.** connie writes no `CLAUDE.md` anywhere, so it
  cannot collide with, shadow, or override the project's. (Even the old
  `~/.claude/CLAUDE.md` write was the *user* scope and would not have overridden
  a *project* `CLAUDE.md` — but "inject as system prompt, write no project files"
  is a far cleaner guarantee than reasoning about scope precedence.)
- **Semantically right.** "You are in a hardened container, N CPUs, read-only
  rootfs" is *runtime environment*, not project *memory*. The system prompt is
  where environment framing belongs; `CLAUDE.md` is where the project's own
  instructions belong. Appending keeps the two cleanly separated.
- **Cheap.** The appended text is part of the cached system-prompt prefix after
  the first turn, so it is not re-billed every request.

We can lean on a Claude CLI flag precisely because we have chosen to stay
Claude-specific. The base image pins the Claude installer by SHA
(`base.Dockerfile`), so the flag will not shift under us unexpectedly.

---

## What changes in the code

**Removed** (the bespoke subsystem):

- `_emit_user_context`, `_emit_project_context`, `_emit_local_context`
- `_write_user_context` and its `cmd_run` call site
- the `_ctx_preview_header` / `_ctx_scope_header` / `_ctx_preview_footer`
  formatters
- host-file concatenation and the `CONNIE_ETC_CLAUDE_MD` override
- the `CONNIE_CONTEXT` build arg path in `_generate_override` and the
  `extend.Dockerfile` write to `/etc/claude-code/CLAUDE.md`

**Kept / retargeted:**

- `_generate_connie_context` — survives; its output becomes the application
  section of the payload instead of a baked file.
- `cmd_context` — repurposed to print the assembled appended prompt via
  `_resolve_context`. Smaller; still the cheapest way to see "what will Claude
  get".

**Added:**

- `_resolve_context` (read/generate scopes → assemble payload) and a small
  reader helper
- the per-layer `context.md` path constants
- the default `start_cmd` wiring, and `_generate_override` emitting `command:`
  as an argv list so the inline payload is one element (no shell splitting)

**Tests:** delete the `_emit_*` / `_write_user_context` integration cases and
the context-parity docker case; keep `_generate_connie_context` + its snapshot
(generator retained); add cases for `_resolve_context` assembly (present/absent
scopes, ordering) and for `cmd_context`'s new output.

---

## Phasing

connie is pre-1.0 and unreleased (0.5.0). With generalization shelved, the work
is small enough to land tightly:

- **Phase 1 — this plan.** Settle the one open decision, then save.
- **Phase 2 — implement and replace.** Add `_resolve_context` + assembly, wire
  the default `start_cmd`, repurpose `cmd_context`, then delete the old
  subsystem once the replacement passes the gate. Update tests in the same
  phase.
- **Phase 3 — docs sweep.** Reconcile DESIGN §"Context Model", README,
  `AGENTS.md`, the generated application context, and CHANGELOG.

---

## Resolved decision — inline, no mount

How the payload reaches Claude: **inline**, baked into the command as an argv
array (not `--append-system-prompt-file` with a mount). Rationale: it keeps the
mount surface to only what is load-bearing (the project and Claude-state
mounts), the size/quoting consideration lives in exactly one place (the startup
command) and never repeats per project, and argv passing means no shell quoting
at all. `connie context` gives the same inspectability a mounted artifact
would. The file variant was considered and rejected on the "no mount we do not
absolutely need" principle.

---

## Security boundary (unchanged)

Context is *settings*, never *posture*. Nothing here touches cap-drop,
`no-new-privileges`, the read-only rootfs, SUID stripping, or the non-root user.

The only new surface is **context content** — author-controlled markdown that
connie appends to Claude's system prompt. connie does not execute it; it is
text, passed inline as an argv element — no context file and no new mount, so
it adds no write vector into the project and no mount surface.

---

## Out of scope

- **Generalization.** Defaulting to `bash` and config-driven per-tool state
  mounts are shelved, not designed here. If connie later needs to host other
  tools, revisit then.
- **Project-directory mounts.** connie maps nothing into `/workspace` (see the
  invariant above); that is a fixed property, not a configurable one.
- **Rules / imports.** `.claude/rules/*.md` and `@`-imports are Claude's own
  memory model, loaded natively; connie does not touch them.
- **The security posture.** Never config-controllable.
