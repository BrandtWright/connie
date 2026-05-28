# Changelog

All notable changes to connie will be documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

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

- Compiled-in defaults → system → user → project → shell env → CLI flags
- `.containerrc` format: `packages`, `env`, `volumes`, `ports`,
  `start_cmd`, `resources`
- `--package`, `--env`, and `--cmd` CLI flags for per-invocation overrides

### Other

- Auto-detection of project root by walking up the directory tree
- Optional `.gitignore` update on `connie init`
- POSIX-compliant shell script — works with sh, bash, dash, zsh
- `CONNIE_LIB_DIR` environment variable for local development without reinstalling
