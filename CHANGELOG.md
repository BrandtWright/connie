# Changelog

All notable changes to connie will be documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added

- `connie run` and `connie build` now automatically build the base image
  (`connie/base:latest`) if it does not exist, rather than dying with an
  error. A fresh install requires only `connie init` and `connie run` — no
  separate `connie build-base` step. `connie build-base` remains available
  to explicitly rebuild the base image (e.g. to pick up a new Claude Code
  version).

### Fixed

- `connie clean` now surfaces docker errors instead of silently swallowing
  them. Previously `2>/dev/null || true` caused a failed clean (e.g. Docker
  daemon not running) to print "Done." and exit 0 with nothing removed.
- `command:` value in the generated `override.yml` is now quoted, preventing
  malformed YAML when `start_cmd` contains spaces or special characters.
- `_info` and `_detail` helpers now write to stderr instead of stdout.
  Previously, calling either function inside `_prepare` (which is invoked
  via command substitution to capture a temp-file path) would corrupt the
  captured path. stderr is the correct channel for progress messages;
  `_die` already used it.
- Port mappings configured in `.containerrc` `ports:` were silently dropped
  and never forwarded to the container. The `ports` block was computed in
  `_generate_override` but missing from the YAML output.

---

## [0.2.0]

### Added

- Forward the host's `TERM`, `COLORTERM`, and a derived `FORCE_COLOR` into the
  container so Claude Code renders with the same color depth in-container as on
  the host. Previously Docker's `-t` hardcoded `TERM=xterm` with no `COLORTERM`,
  downgrading Claude Code to basic 16-color output. `FORCE_COLOR` is derived from
  the host's declared capabilities (`COLORTERM=truecolor` → `3`, `*256color*`
  term → `2`, otherwise `1`) and bypasses Node.js/chalk's Docker PTY probe, which
  otherwise underestimates color support regardless of `TERM`/`COLORTERM`.
  All forwarded values are the lowest-precedence env entries — anything in
  `.containerrc` `env:` or `--env` overrides them. `TERM` defaults to
  `xterm-256color` when unset on the host.
- Base image now installs `ncurses-terminfo-base` so forwarded `TERM` values
  (e.g. `screen-256color`) resolve against the terminfo database for
  in-container TUI tools such as `less`.

### Fixed

- `--env KEY=VALUE` now emits valid YAML. It previously appended bare
  `KEY=VALUE` lines into the `environment:` map, producing an unparseable
  override whenever any other env var was set. CLI `--env` values now merge as
  the highest-precedence env source.

---

## [0.1.0] — Initial release

### Added

- `connie build-base` — build the local base image
- `connie init [dir]` — scaffold `.devbox/` inside a project directory
- `connie run [dir]` — build (if needed) and start Claude Code
- `connie build [dir]` — build the project container image without starting it
- `connie clean [dir]` — remove the locally built project container image

### Base image

- Alpine 3.20 with bash, coreutils, curl, wget, git, ripgrep, fd, jq, tree,
  file, tar, gzip, unzip, lsof, build-base, libgcc, libstdc++, linux-headers
- Non-root user `claude-user` (uid/gid 1000) — Claude Code runs as this user
- Claude Code installed via the official `install.sh` script as `claude-user`,
  placing the binary in `/home/claude-user/.local/bin/`
- `DISABLE_AUTOUPDATER=1` baked in — required for read-only filesystem
- `GIT_TERMINAL_PROMPT=0` baked in — prevents git from hanging on credentials
- `entrypoint.sh` redirects all XDG user directories to `/tmp` at startup,
  making the read-only filesystem transparent to tools that write to `~`

### Container security

- Read-only root filesystem
- All Linux capabilities dropped (`cap_drop: ALL`)
- `no-new-privileges: true`
- All suid/sgid bits removed from the base image at build time
- `/tmp` as `tmpfs` (RAM-backed, ephemeral)
- `init: true` for correct signal handling and zombie reaping
- Resource limits: 4GB RAM, 2 CPUs, 512 PIDs, 4096/8192 file descriptors

### Per-project Claude Code state

- `.devbox/.claude/` and `.devbox/.claude.json` are per-project, stored in
  `.devbox/` alongside other container config
- Claude Code auth and memory are fully isolated between projects
- `connie init` pre-creates both on the host so Docker has valid mount points

### Config hierarchy

- Compiled-in defaults → system → user → project → CLI flags
- `.containerrc` format: `packages`, `env`, `volumes`, `ports`,
  `start_cmd`, `resources`
- `--package`, `--env`, and `--cmd` CLI flags for per-invocation overrides

### Other

- Auto-detection of project root by walking up the directory tree
- Optional `.gitignore` update on `connie init`
- POSIX-compliant shell script — works with sh, bash, dash, zsh
- `CONNIE_LIB_DIR` environment variable for local development without reinstalling
