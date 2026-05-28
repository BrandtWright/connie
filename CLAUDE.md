# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## What connie is

A CLI (`bin/connie`) that runs Claude Code inside a hardened, reproducible Docker
container scoped to a single project directory. It is a single POSIX `sh` script
plus a set of templates and Dockerfiles — there is no compiled artifact and no
runtime dependency beyond `docker`, `docker compose` v2, and `yq` v4.

## Development commands

```sh
make check                                   # syntax-check bin/connie (sh -n) — run after every edit
make install PREFIX=~/.local                 # install to ~/.local without sudo
make uninstall PREFIX=~/.local

# Test changes without reinstalling — CONNIE_LIB_DIR overrides the lib path
CONNIE_LIB_DIR=./lib/connie ./bin/connie build-base
CONNIE_LIB_DIR=./lib/connie ./bin/connie init ~/repos/scratch
CONNIE_LIB_DIR=./lib/connie ./bin/connie run  ~/repos/scratch
CONNIE_LIB_DIR=./lib/connie ./bin/connie run  --cmd sh   # shell into the container to debug
```

There is no automated test suite. Verification is manual: `make check`, then
exercise `init` / `build` / `run` / `clean` against a scratch project.

## Hard constraints

- **`bin/connie` must stay POSIX `sh` — no bashisms.** The script also runs in
  Alpine and CI where bash may be absent. Use `[ ]` not `[[ ]]`, `$(...)` not
  backticks, `.` not `source`, `_`-prefixed names instead of `local`, and
  space/newline-separated strings instead of arrays. `make check` enforces parse
  validity but not bashism-freedom — review manually.
- **`base.Dockerfile` and `entrypoint.sh` live in `lib/connie/`.** That is what
  `Makefile` installs and what `connie build-base` uses as its build context.

## Architecture

### Three layers of artifact

1. **Installed tooling** — `Makefile` copies `bin/connie` to `$PREFIX/bin` and
   `lib/connie/**` to `$PREFIX/lib/connie` (templates, `base.Dockerfile`,
   `entrypoint.sh`, `config/defaults.yml`). `LIB_DIR` in the script defaults to
   `/usr/local/lib/connie`, overridable via `CONNIE_LIB_DIR`.
2. **Base image** (`connie/base:latest`) — built from `lib/connie/base.Dockerfile`
   by `connie build-base`, or automatically on first `connie run`/`connie build`
   if not already present: Alpine 3.20 + core tools + non-root `claude-user`
   (uid 1000) + Claude Code installed via the official `install.sh` as that user.
   Not published to any registry.
3. **Per-project image** (`connie-workspace`) — built by `connie run`/`connie build`
   from the project's `.connie/extend.Dockerfile`, which is `FROM connie/base:latest`
   plus `EXTRA_PACKAGES` (apk) injected as a build arg.

### What `connie init` writes into a project

Everything connie touches in a target project lives under `.connie/` (and the
directory is gitignored — connie never modifies the project's own source tree):

- `.containerrc` — **developer-owned**, the only file meant to be hand-edited;
  never overwritten by re-running `init`.
- `docker-compose.yml`, `extend.Dockerfile` — **connie-managed** templates, copied
  from `lib/connie/templates/`. Editing the templates only affects *future*
  `init` runs, not already-initialised projects.
- `.claude/` (dir) and `.claude.json` (file) — **Claude-Code-owned** per-project
  state and auth. Pre-created on the host because the read-only container
  filesystem cannot create the bind-mount targets itself (and Docker would
  otherwise auto-create `.claude.json` as a *directory*, breaking config parsing).
- `override.yml` — generated fresh on every run, ephemeral, never committed.

### Config merge → override.yml → compose (the core flow)

`bin/connie` is organised as a pipeline. When you change runtime behaviour, trace
it through these stages rather than editing one in isolation:

1. `_merge_configs` deep-merges YAML (via `yq` reduce) in ascending precedence:
   `lib/connie/config/defaults.yml` → `/etc/connie/config.yml` →
   `~/.config/connie/config.yml` → project `.connie/.containerrc`. Produces one
   temp file.
2. CLI flags (`--package`, `--env`, `--cmd`) and shell env override on top of the
   merged file — these are applied in `_generate_override`, not the merge.
3. `_generate_override` reads the merged config and emits `.connie/override.yml`:
   build args (`EXTRA_PACKAGES`, `BUILD_COMMANDS`), `environment` (from `env`),
   `volumes` (the three standard mounts first, then extras), `ports`, resource
   limits, and `command`.
4. `_run_compose` runs `docker compose -f docker-compose.yml -f override.yml ...`.
   The static `docker-compose.yml` carries the immutable security posture
   (`read_only`, `cap_drop: ALL`, `no-new-privileges`, `/tmp` tmpfs, `init: true`);
   `override.yml` carries everything derived from config. `connie run` calls
   `_run_compose` twice — `build workspace` then `run --rm workspace`.

### Runtime environment (entrypoint.sh)

Because the container root filesystem is read-only, `entrypoint.sh` redirects all
XDG dirs and `GIT_CONFIG_GLOBAL` to the `/tmp` tmpfs at startup, marks `/workspace`
a git safe directory, and `exec`s the command as PID 1. The base image bakes in
`DISABLE_AUTOUPDATER=1` — without it Claude Code's updater hangs trying to
write to the read-only filesystem.

## Conventions

- Version lives in one place: `VERSION` at the top of `bin/connie`. Bump it
  and add a `CHANGELOG.md` entry (Keep a Changelog format) per release.
- Changing a value in `config/defaults.yml` affects every project relying on the
  default — treat it like a public API change.
- Security-relevant edits to `docker-compose.yml` or `base.Dockerfile` should be
  mirrored in `DESIGN.md`, which documents the rationale for each hardening measure.
- `TODO.md` at the repo root tracks features and ideas under consideration.
  Consult it when evaluating new work; update it when items are completed or
  when new ideas arise during a session.
