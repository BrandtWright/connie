# Changelog

All notable changes to connie will be documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added

- **Zero project footprint** — `connie` no longer writes anything to the
  project directory. All state (config, Claude Code auth, session history)
  now lives in standard XDG directories on the developer's machine:
  - `~/.config/connie/projects/<slug>/config.yml` — developer-owned project config
  - `~/.local/state/connie/<slug>/` — Claude Code state and auth
  - `~/.local/share/connie/projects.yml` — project registry (path → slug)
  No `.gitignore` entry needed; the project does not need to know connie exists.
- **Claude Code context generation** at two of Claude Code's four
  documented context scopes. Connie owns the two that describe the
  container environment; the project and local scopes are untouched.
  - **Managed-policy scope** (`/etc/claude-code/CLAUDE.md`) — connie reads
    the merged config and generates a description of the container
    environment (installed packages, build commands, additional mounts,
    exposed ports, environment variables, resource limits, security
    constraints) and bakes it into the image at build time via a Docker
    build arg. Because it lives in the image, the user cannot exclude it.
  - **User-level scope** (`~/.claude/CLAUDE.md`) — connie assembles the
    host's `/etc/claude-code/CLAUDE.md` and `~/.claude/CLAUDE.md` (if
    present) into a single file in the per-project state directory, which
    is bind-mounted to `~/.claude/` inside the container. Each source
    contribution is preceded by a block-level HTML comment identifying
    its origin; Claude Code strips block-level HTML comments before
    context injection, so the markers cost no tokens but remain visible
    to humans previewing the file. Forwards the user's personal Claude
    Code preferences without per-project copies.
  Claude Code's default loading behaviour also picks up
  `/workspace/CLAUDE.md` and `/workspace/CLAUDE.local.md` from the project
  — connie never touches those, so projects that already use them work
  unchanged.
- `connie context [dir]` — new subcommand that prints both connie-managed
  contexts without starting the container. Pure read operation — no
  on-disk state is modified. Requires no Docker; useful for previewing
  what Claude Code will load before a run.
- `connie config [dir]` subcommand — prints the config file path, state
  directory path, and the effective Compose override for a project. Useful
  for diagnosing what `connie run` will do.
- Auto-migration from old `.connie/` project-directory layout to XDG directories.
  Triggered automatically on the first `connie run`/`connie build` for a project
  that still has a `.connie/` directory. Moves `config.yml`, `.claude/`, and
  `.claude.json`; removes `.connie/` if empty afterward.
- `build_commands:` config key — a list of arbitrary shell commands run at
  image build time as `claude-user`, after apk packages are installed. Enables
  npm, pip, gem, cargo, and other package managers not covered by the `packages:`
  apk mechanism. Commands are joined with `&&` and fail fast. Example:
  `build_commands: [npm install -g markdownlint-cli]`.
- `connie run` and `connie build` now automatically build the base image
  (`connie/base:latest`) if it does not exist, rather than dying with an
  error. A fresh install requires only `connie init` and `connie run` — no
  separate `connie build-base` step. `connie build-base` remains available
  to explicitly rebuild the base image (e.g. to pick up a new Claude Code
  version).

### Changed

- `config/defaults.yml` is now load-bearing: all config keys are guaranteed
  to be present in the merged config after it is loaded, so the `// fallback`
  values that were duplicated in the script's yq expressions have been removed.
  `_merge_configs` now checks for the file at startup and exits with a clear
  error if it is missing rather than silently producing null values.

### Security

- Per-project state directories (`~/.local/state/connie/<slug>/`) and their
  `.claude/` subdirectories are now created — or normalised if already present
  — with mode `0700` at `connie init`, `connie run`, and during auto-migration.
  This protects the OAuth bearer token that Claude Code persists at
  `<slug>/.claude/.credentials.json` from other local users on the same machine,
  even if Claude Code itself does not set restrictive permissions on the
  credential file. Defense-in-depth, applied at the directory layer.

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
- Port mappings configured in `config.yml` `ports:` were silently dropped
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
  `config.yml` `env:` or `--env` overrides them. `TERM` defaults to
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
- `connie init [dir]` — scaffold `.connie/` inside a project directory
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

- `.connie/.claude/` and `.connie/.claude.json` are per-project, stored in
  `.connie/` alongside other container config
- Claude Code auth and memory are fully isolated between projects
- `connie init` pre-creates both on the host so Docker has valid mount points

### Config hierarchy

- Compiled-in defaults → system → user → project → CLI flags
- `config.yml` format: `packages`, `env`, `volumes`, `ports`,
  `start_cmd`, `resources`
- `--package`, `--env`, and `--cmd` CLI flags for per-invocation overrides

### Other

- Auto-detection of project root by walking up the directory tree
- POSIX-compliant shell script — works with sh, bash, dash, zsh
- `CONNIE_LIB_DIR` environment variable for local development without reinstalling
