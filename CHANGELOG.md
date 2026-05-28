# Changelog

All notable changes to connie will be documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

---

## [0.1.0] — Initial release

### Added

- `connie build-base` — build the local base image (Alpine 3.20 + core tools
  + Claude Code) tagged as `connie/base:latest`
- `connie init [dir]` — scaffold `.devbox/` inside a project directory
- `connie run [dir]` — build (if needed) and start Claude Code in a container
- `connie build [dir]` — build the project container image without starting it
- `connie clean [dir]` — remove the locally built project container image
- Hardened container defaults: read-only root filesystem, all Linux
  capabilities dropped, `no-new-privileges`, tmpfs for `/tmp` and
  `~/.local/state`, resource limits (4GB RAM, 2 CPUs, 512 PIDs)
- Exactly two host mounts: project directory (`/workspace`) and `~/.claude`
  (Claude Code auth persistence) — nothing else from the host is accessible
- Config hierarchy: compiled-in defaults → system → user → project →
  shell environment → CLI flags
- `.containerrc` project config format: `packages`, `env`, `secrets`,
  `volumes`, `ports`, `start_cmd`, `resources`
- `--package`, `--env`, and `--cmd` CLI flags for per-invocation overrides
- Auto-detection of project root by walking up the directory tree
- Optional `.gitignore` update on `connie init`
- POSIX-compliant shell script — works with sh, bash, dash, zsh
- `CONNIE_LIB_DIR` environment variable for local development without
  reinstalling
