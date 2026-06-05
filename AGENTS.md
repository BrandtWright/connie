# connie — guidance for AI coding assistants

This file provides guidance to AI coding assistants working in this repository.
It follows the [AGENTS.md spec][agents-md] — a tool-agnostic
convention so any assistant that adopts it (Claude Code, Cursor, Aider,
Copilot, and others) picks up the same project context without per-tool
duplication. Most of the content below is tool-agnostic engineering
documentation; the few session-guidance items toward the end are framed in
terms of common AI-assistant workflows rather than any one tool's UI.

## What connie is

A CLI (`src/connie`) that runs Claude Code inside a hardened, reproducible Docker
container scoped to a single project directory. It is a single POSIX `sh` script
plus a set of Dockerfiles and config files — there is no compiled artifact and no
runtime dependency beyond `docker`, `docker compose` v2, and `yq` v4.

## Development commands

```sh
make check                                # syntax-check src/connie (sh -n) — run after every edit
make test                                 # run the POSIX shell test suite
make install PREFIX=~/.local              # install to ~/.local without sudo
make uninstall PREFIX=~/.local

# Test changes without reinstalling — CONNIE_LIB_DIR overrides the lib path
CONNIE_LIB_DIR=./src ./src/connie build-base
CONNIE_LIB_DIR=./src ./src/connie init ~/repos/scratch
CONNIE_LIB_DIR=./src ./src/connie run  ~/repos/scratch
CONNIE_LIB_DIR=./src ./src/connie run  --cmd sh   # shell into the container to debug
```

`make check` is a sub-second `sh -n` parse check. `make test` runs the
POSIX shell test suite under `tests/` — a roll-your-own harness with a
`given`/`when`/`expect` DSL where each step is a named function the
framework executes and records, inspired by slipbox's test architecture.
`tests/README.md` is the authoritative reference; the short version:

- File naming: `<feature>_test_cases.sh`
- Function naming: preconditions `a_*`/`an_*`, stimuli `the_*`,
  assertions `it_*` (named) or `expect_*` (primitive), tests `*_test_case`
- One logical claim per test (multiple `expect` calls are fine when they
  describe inseparable aspects of the same claim)
- Each test runs in an isolated subshell with `HOME`/`XDG_*` redirected
  to a `mktemp -d` so connie's path-derived globals point at a sandbox
- `src/connie`'s argument parser and dispatch live in `_main`, called by
  an entry-point line at the bottom; tests source the script with
  `CONNIE_NO_DISPATCH=1` to get the functions without firing the CLI
- Output: TAP by default; `sh tests/run.sh --pretty` for human-readable
- Filter: `sh tests/run.sh -f <substring>` to run a subset
- Docker-requiring tests live in a separate `tests/docker/` tree and run
  from a Docker-capable host only — `make test` skips them

### Verification tooling

When working on connie inside connie, the project's own `config.yml`
(at `~/.config/connie/projects/<slug>/config.yml`) should include:

```yaml
packages:
  - yq          # exercise yq pipelines in src/connie directly
  - shellcheck  # POSIX/bashism enforcement (make check only checks parse validity)
  - yamllint    # YAML lint (duplicate-key + hygiene; yq parse is the fallback)

build_commands:
  # hadolint is a Haskell binary and is not available in Alpine's apk
  # repositories. Install the static release into ~/.local/bin, which is
  # already on PATH for claude-user (set in base.Dockerfile).
  - mkdir -p ~/.local/bin
  - wget -qO ~/.local/bin/hadolint https://github.com/hadolint/hadolint/releases/latest/download/hadolint-Linux-x86_64
  - chmod +x ~/.local/bin/hadolint
```

Each tool closes a specific verification gap:

- `yq` — lets you run `connie context`, `connie config`, and reproduce
  `_merge_configs` / `_generate_override` output during a session
- `shellcheck` — mechanically enforces the "no bashisms" hard constraint
  below; run as `shellcheck -s sh src/connie`
- `hadolint` — catches common Dockerfile mistakes in `src/docker/base.Dockerfile`
  and `src/docker/extend.Dockerfile`
- `yamllint` — flags duplicate keys (which yq silently accepts) plus
  trailing-space / final-newline hygiene in the config templates and
  `docker-compose.yml`; `make lint-yaml` falls back to a yq parse-check when
  it is absent

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
   `~/.config/connie/config.yml` →
   `~/.config/connie/projects/<slug>/config.yml`. Produces one temp file.
2. CLI flags (`--package`, `--env`, `--cmd`) and shell env override on top of the
   merged file — these are applied in `_generate_override`, not the merge.
3. `_generate_override` reads the merged config and writes a temp file:
   build args (`EXTRA_PACKAGES`, `BUILD_COMMANDS`), `environment` (from `env`),
   `volumes` (the three standard mounts first, then extras), `ports`, resource
   limits, and `command`.
4. `_run_compose` runs
   `docker compose -f $LIB_DIR/docker/docker-compose.yml -f <tmpfile> ...`.
   The static `docker-compose.yml` carries the immutable security posture
   (`read_only`, `cap_drop: ALL`, `no-new-privileges`, `/tmp` tmpfs, `init: true`);
   the override carries everything derived from config. `connie run` calls
   `_run_compose` twice — `build workspace` then `run --rm workspace`. The
   second invocation auto-passes `-T` when stdout is not a TTY (`[ -t 1 ]`),
   so the same `cmd_run` works in both interactive sessions (where the
   compose file's `tty: true` lights up Claude Code's UI) and non-TTY
   contexts like CI or the test harness (where `tty: true` would otherwise
   fail with "the input device is not a TTY").

### Runtime environment (entrypoint.sh)

Because the container root filesystem is read-only, `entrypoint.sh` redirects all
XDG dirs and `GIT_CONFIG_GLOBAL` to the `/tmp` tmpfs at startup, marks `/workspace`
a git safe directory, and `exec`s the command as PID 1. The base image bakes in
`DISABLE_AUTOUPDATER=1` — without it Claude Code's updater hangs trying to
write to the read-only filesystem.

### Claude Code context generation

connie bakes and writes no `CLAUDE.md`. It appends its context to Claude's
system prompt at launch via `claude --append-system-prompt`, so a project's own
`CLAUDE.md` loads natively and is never read, written, or shadowed.

`_resolve_context` (shared by `cmd_run` and `cmd_context`, so the preview is
exactly what Claude receives) assembles one markdown payload host-side, in
order:

1. **Application** — `_generate_connie_context` reads the merged config and
   emits markdown describing the container (resources, packages, ports, mounts,
   security posture). Always present.
2. **Machine / User / Project** — the contents of a `context.md` beside each
   config layer (`$SYSTEM_CONTEXT`, `$USER_CONTEXT`, and
   `<config>/projects/<slug>/context.md`), each under a `## … Context` heading,
   included only when the file exists and is non-empty.

`_generate_override` injects the payload by emitting `command:` as an argv
array — `["claude", "--append-system-prompt", "<payload>"]` — when the launch
command is `claude` (an array keeps the multi-line payload as one verbatim
element, so there is no shell quoting). Any other `start_cmd` passes through as
a scalar and gets no injection (connie cannot deliver context through a flag
the tool lacks). `cmd_context` prints the same payload for a read-only preview.
Nothing is written to disk or into the project directory.

## Conventions

- Version lives in one place: `VERSION` at the top of `src/connie`. Bump it
  and add a `docs/CHANGELOG.md` entry (Keep a Changelog format) per release.
- Changing a value in `src/config/defaults.yml` affects every project relying
  on the default — treat it like a public API change.
- Security-relevant edits to `src/docker/docker-compose.yml` or
  `src/docker/base.Dockerfile` should be mirrored in `docs/DESIGN.md`, which
  documents the rationale for each hardening measure.
- Changes to context generation (`_resolve_context`,
  `_generate_connie_context`, or the `--append-system-prompt` command wiring in
  `_generate_override`) should be mirrored in `docs/context.md`, the **Claude
  Code Context Model** section of `docs/DESIGN.md`, and the **Claude Code
  Context** section of `README.md`.
- `docs/TODO.md` tracks features and ideas under consideration.
  Consult it when evaluating new work; update it when items are completed or
  when new ideas arise during a session.

[agents-md]: https://agents.md/
