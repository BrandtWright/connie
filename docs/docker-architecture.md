# Docker Architecture

How connie assembles and runs a container. The short version: connie layers
in **two independent dimensions** — the **image** (built, at build time) and
the **Compose configuration** (applied, at run time) — and the two meet when
`docker compose run` starts the container. Keeping that distinction straight
explains the whole design, including why `extend.Dockerfile` handles only
`packages` and `build_commands` while ports, volumes, env, resources, and the
command live somewhere else entirely.

This document is a reference companion to `docs/DESIGN.md` (rationale for the
hardening) and `SECURITY.md` (the threat model and containment guarantees).

---

## The image (build time)

The image is built in two stacked layers, only the top of which is
per-project:

![connie image layers: alpine, then the shared base image, then the
per-project extend layer][img-layers]

- **`alpine:3.20`** — the foundation, pinned by digest for reproducibility.
- **Base image (`connie/base:latest`)** — Alpine plus core tools, Node, and
  Claude Code, running as the non-root `claude-user` with SUID/SGID bits
  stripped. Built **once** by `connie build-base` and shared by every project;
  not published to any registry.
- **Per-project image (`connie-<slug>-workspace`)** — built from
  `extend.Dockerfile` on top of the base, adding this project's `packages`
  (via `apk`) and running its `build_commands`. Built by `connie build` /
  `connie run`; unchanged build args hit Docker's layer cache, so a rebuild
  with nothing new completes instantly.

`extend.Dockerfile` carries exactly one security-relevant action: it
**re-strips SUID/SGID** after installing user packages, because a user-added
apk package could ship a setuid binary (`su`, `mount`, …). That is
defense-in-depth — under connie's own runtime (`no-new-privileges`, non-root,
`cap_drop: ALL`) a setuid binary cannot escalate anyway; the re-strip only
matters if the image is ever run *outside* connie's hardened Compose.

---

## Build time vs run time: where each config key goes

The dividing line is simple: **what changes the image's filesystem is
build-time and belongs in `extend.Dockerfile`; what governs how the container
runs is run-time and belongs in the Compose override.** Only two config keys
change the image filesystem, which is why `extend.Dockerfile` handles only
those two.

![Routing of config keys: packages and build_commands go to the image at
build time; everything else goes to the Compose override at run time][img-routing]

| Config key | Handled in | Why there |
| --- | --- | --- |
| `packages` | `extend.Dockerfile` (build arg) | `apk add` bakes files into image layers |
| `build_commands` | `extend.Dockerfile` (build arg) | arbitrary setup that mutates the image filesystem (`npm i -g`, `pip install`) |
| `ports` | Compose override (`ports:`) | publishing a port is a `docker run -p` decision; it cannot be baked into an image |
| `unsafe_extra_mounts` | Compose override (`volumes:`) | a bind mount attaches a *host* path at container start — images contain no host paths |
| `env` | Compose override (`environment:`) | injected at run; keeps values out of image history and avoids a rebuild on change |
| `resources` | Compose override (`mem_limit`/`cpus`/`pids_limit`) | cgroup limits apply to the container, not the image |
| `start_cmd` (+ context) | Compose override (`command:`) | the command the container runs — and the appended context — are run-time properties |

A few of these *cannot* be baked in even in principle: a bind mount has no
image representation; `EXPOSE` in a Dockerfile is documentation only and
publishes nothing; `VOLUME` cannot pin a host path; cgroup limits are not an
image concept. They are run-time by necessity.

---

## The Compose override (run time)

"Compose override" is connie's term for the **second Docker Compose file it
generates on the fly each run and layers on top of the static base Compose
file.** Docker Compose accepts multiple `-f` files and deep-merges them, with
later files adding to / overriding earlier ones — that second file is the
conventional "override," except connie generates it rather than committing it.

![Two Compose files merging: the committed base file (the security floor) plus
the generated override (per-project keys), combined at docker compose run into
the running container][img-compose]

Every connie operation runs as:

```sh
docker compose -p connie-<slug> \
  -f $LIB_DIR/docker/docker-compose.yml \   # static base — committed in the repo
  -f <generated-override.yml> \             # per-run, from your merged config
  run --rm workspace
```

The two files carry different things, on purpose:

- **The base file (`src/docker/docker-compose.yml`)** is fixed and
  version-controlled — the **security floor**, identical for every project:
  `read_only: true`, `cap_drop: [ALL]`, `security_opt: [no-new-privileges]`,
  `user: "1000:1000"`, the `/tmp` tmpfs, and `init: true`.
- **The generated override** is produced by `_generate_override` from the
  merged config — the per-project, varying bits: the `build.args`
  (`EXTRA_PACKAGES`, `BUILD_COMMANDS`), `environment`, `volumes`, `ports`,
  resource limits, and `command`.

So the base is the floor and the override adds to it. Two facts follow:

- **The override cannot weaken the floor.** It only ever sets the specific
  per-project keys connie generates, and the YAML-injection guards stop a
  config value from smuggling in a sibling key — so the hardening keys (which
  are not even present in the override) always hold. The dangerous-mount guard
  also runs at override-generation time, not frozen into a layer.
- **It is ephemeral.** The override is written to a temp file each invocation
  and deleted on exit; nothing lands on disk and nothing is committed.
  `connie config [dir]` is exactly "render the override to stdout without
  running anything" — the cheapest way to see what connie will hand Compose.

---

## Why this split has been implemented

- **No rebuild for run-time changes.** Editing ports, env, resources, mounts,
  or the command invalidates no image layer, so the next `connie run` skips
  straight to running. Only `packages` / `build_commands` trigger a
  (layer-cached) rebuild. This is the same reasoning that moved connie's
  *context* off a build-arg bake onto the run-time `--append-system-prompt`
  command (see `docs/context.md`).
- **The image stays minimal and reusable.** It is just "base + your tools";
  the same image re-runs under different ports/limits/env without rebuilding.
- **The security posture must be run-time anyway.** An image cannot enforce
  its own `cap_drop` or read-only rootfs — those are applied to the container
  by the runtime. The image build is the wrong place for them.
- **Values stay out of image history.** Env injected at run time is not
  persisted in image layers.

---

## See also

- `docs/DESIGN.md` — the security model and the rationale for each hardening
  measure.
- `SECURITY.md` — threat model, containment guarantees, and known limitations.
- `docs/config-merge.md` — how the layered config that feeds all of this is
  merged.
- `docs/context.md` — how connie's context is injected at run time (the
  motivating example of build-time vs run-time).

[img-layers]: assets/docker-image-layers.svg
[img-routing]: assets/docker-config-routing.svg
[img-compose]: assets/docker-compose-merge.svg
