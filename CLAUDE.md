# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## What connie is

A CLI (`src/connie`) that runs Claude Code inside a hardened, reproducible Docker
container scoped to a single project directory. It is a single POSIX `sh` script
plus a set of Dockerfiles and config files — there is no compiled artifact and no
runtime dependency beyond `docker`, `docker compose` v2, and `yq` v4.

## Development commands

```sh
make check                                # syntax-check src/connie (sh -n) — run after every edit
make install PREFIX=~/.local              # install to ~/.local without sudo
make uninstall PREFIX=~/.local

# Test changes without reinstalling — CONNIE_LIB_DIR overrides the lib path
CONNIE_LIB_DIR=./src ./src/connie build-base
CONNIE_LIB_DIR=./src ./src/connie init ~/repos/scratch
CONNIE_LIB_DIR=./src ./src/connie run  ~/repos/scratch
CONNIE_LIB_DIR=./src ./src/connie run  --cmd sh   # shell into the container to debug
```

There is no automated test suite. Verification is manual: `make check`, then
exercise `init` / `build` / `run` / `clean` against a scratch project.

## Hard constraints

- **`src/connie` must stay POSIX `sh` — no bashisms.** The script also runs in
  Alpine and CI where bash may be absent. Use `[ ]` not `[[ ]]`, `$(...)` not
  backticks, `.` not `source`, `_`-prefixed names instead of `local`, and
  space/newline-separated strings instead of arrays. `make check` enforces parse
  validity but not bashism-freedom — review manually.
- **`base.Dockerfile` and `entrypoint.sh` live in `src/docker/`.** That is what
  `Makefile` installs and what `connie build-base` uses as its build context.

## Architecture

### Three layers of artifact

1. **Installed tooling** — `Makefile` copies `src/connie` to `$PREFIX/bin` and
   `src/docker/**` + `src/config/**` to `$PREFIX/lib/connie/docker/` and
   `$PREFIX/lib/connie/config/`. `LIB_DIR` in the script defaults to
   `/usr/local/lib/connie`, overridable via `CONNIE_LIB_DIR`.
2. **Base image** (`connie/base:latest`) — built from `src/docker/base.Dockerfile`
   by `connie build-base`, or automatically on first `connie run`/`connie build`
   if not already present: Alpine 3.20 + core tools + non-root `claude-user`
   (uid 1000) + Claude Code installed via the official `install.sh` as that user.
   Not published to any registry.
3. **Per-project image** (`connie-workspace`) — built by `connie run`/`connie build`
   from `$LIB_DIR/docker/extend.Dockerfile`, which is `FROM connie/base:latest`
   plus `EXTRA_PACKAGES` (apk) injected as a build arg.

### What `connie init` writes — and where

`connie init` writes nothing to the target project directory. All state lives
in XDG directories on the user's machine:

- `$XDG_CONFIG_HOME/connie/projects/<slug>/config.yml` — **developer-owned**,
  the project's container config; the only file meant to be hand-edited; never
  overwritten by re-running `init`.
- `$XDG_STATE_HOME/connie/<slug>/.claude/` and `.claude.json` —
  **Claude-Code-owned** per-project state and auth. Pre-created on the host
  because the read-only container filesystem cannot create the bind-mount
  targets itself (and Docker would otherwise auto-create `.claude.json` as a
  *directory*, breaking config parsing).
- `$XDG_DATA_HOME/connie/projects.yml` — **connie-managed** registry mapping
  project paths to their slugs.
- No generated files — the Compose override is written to a temp file and
  deleted when connie exits.

The `<slug>` is `<basename>-<cksum>`, e.g. `my-project-1234567890`. Run
`connie config [dir]` to see the exact paths for any project.

### Config merge → override.yml → compose (the core flow)

`src/connie` is organised as a pipeline. When you change runtime behaviour, trace
it through these stages rather than editing one in isolation:

1. `_merge_configs` deep-merges YAML (via `yq` reduce) in ascending precedence:
   `src/config/defaults.yml` → `/etc/xdg/connie/config.yml` →
   `~/.config/connie/config.yml` → `~/.config/connie/projects/<slug>/config.yml`. Produces one
   temp file.
2. CLI flags (`--package`, `--env`, `--cmd`) and shell env override on top of the
   merged file — these are applied in `_generate_override`, not the merge.
3. `_generate_override` reads the merged config and writes a temp file:
   build args (`EXTRA_PACKAGES`, `BUILD_COMMANDS`), `environment` (from `env`),
   `volumes` (the three standard mounts first, then extras), `ports`, resource
   limits, and `command`.
4. `_run_compose` runs `docker compose -f $LIB_DIR/docker/docker-compose.yml -f <tmpfile> ...`.
   The static `docker-compose.yml` carries the immutable security posture
   (`read_only`, `cap_drop: ALL`, `no-new-privileges`, `/tmp` tmpfs, `init: true`);
   the override carries everything derived from config. `connie run` calls
   `_run_compose` twice — `build workspace` then `run --rm workspace`.

### Runtime environment (entrypoint.sh)

Because the container root filesystem is read-only, `entrypoint.sh` redirects all
XDG dirs and `GIT_CONFIG_GLOBAL` to the `/tmp` tmpfs at startup, marks `/workspace`
a git safe directory, and `exec`s the command as PID 1. The base image bakes in
`DISABLE_AUTOUPDATER=1` — without it Claude Code's updater hangs trying to
write to the read-only filesystem.

### Claude Code context generation

Claude Code loads `CLAUDE.md` from four scopes. connie populates two of them:

1. **Managed policy** (`/etc/claude-code/CLAUDE.md` in the container) —
   `_generate_connie_context` reads the merged config and emits markdown
   describing the container. `_generate_override` encodes it as a JSON-string
   YAML value and passes it as the `CONNIE_CONTEXT` build arg.
   `extend.Dockerfile` writes it to the image as root. Baked into the layer
   cache; immutable from inside the container.
2. **User-level** (`~/.claude/CLAUDE.md` in the container) —
   `_generate_user_context` concatenates the host's `/etc/claude-code/CLAUDE.md`
   and `~/.claude/CLAUDE.md` (if present) into the per-project state directory,
   which is bind-mounted to `~/.claude/`. Called from `cmd_run` at run time.

The project and local scopes (`/workspace/CLAUDE.md`,
`/workspace/CLAUDE.local.md`) come from the project directory unchanged —
connie never touches `/workspace/`. `connie context` exercises the same
generation code paths without launching the container, which is the
preferred way to verify context output.

## Conventions

- Version lives in one place: `VERSION` at the top of `src/connie`. Bump it
  and add a `docs/CHANGELOG.md` entry (Keep a Changelog format) per release.
- Changing a value in `src/config/defaults.yml` affects every project relying on the
  default — treat it like a public API change.
- Security-relevant edits to `src/docker/docker-compose.yml` or `src/docker/base.Dockerfile`
  should be mirrored in `docs/DESIGN.md`, which documents the rationale for each hardening measure.
- Changes to context generation (`_generate_connie_context`,
  `_generate_user_context`, or the `CONNIE_CONTEXT` build-arg wiring in
  `extend.Dockerfile`) should be mirrored in the **Claude Code Context Model**
  section of `docs/DESIGN.md` and the **Claude Code Context** section of
  `README.md`.
- `docs/TODO.md` tracks features and ideas under consideration.
  Consult it when evaluating new work; update it when items are completed or
  when new ideas arise during a session.
