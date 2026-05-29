# `connie` — Design Document

This document describes the architecture of `connie`, the reasoning behind its
design decisions, and the tradeoffs that were considered. It is intended for
contributors and for anyone who wants to understand why the tool works the way
it does.

---

## Problem Statement

Claude Code is a powerful AI coding assistant, but running it directly on a
developer's host machine raises questions about scope and containment: what
files can it read? What can it modify? What processes can it spawn? For
day-to-day use these questions may not matter, but for deliberate, auditable
use against production codebases they matter a great deal.

`connie` answers these questions by running Claude Code inside a container with
an explicit, minimal set of permissions. The developer defines what the
container can touch. Everything else is denied by default.

The secondary goal is reproducibility. A container built from the same
`.connie/config.yml` on any machine produces the same environment — the same
tools, the same configuration, the same constraints.

---

## Design Principles

### 1. Least Privilege by Default

The container is locked down at creation. Any capability not explicitly
required is absent. The developer opts *in* to capabilities, not out of them.

This is the opposite of Docker's defaults. For a tool that runs an AI agent
against your codebase, explicit constraint is more appropriate than implicit
permissiveness.

### 2. Per-Project Isolation

Claude Code state — auth tokens, project memory, conversation history — is
stored per-project in `$XDG_STATE_HOME/connie/<slug>/`. Each project gets a
completely fresh Claude Code context. No memory or history leaks between
projects.

This is implemented via volume mounts that point Claude Code's expected home
directory paths (`.claude/` and `.claude.json`) to per-project locations in
the XDG state directory, transparent to Claude Code itself.

### 3. Non-Invasive

`connie` must be attachable to any existing project without modifying it. The
project's source tree, build system, version control, and `.gitignore` are
entirely untouched. Nothing is written to the project directory.

This is stricter than the `git` analogy — `git` at least writes `.git/`.
`connie` leaves zero footprint in the project.

### 4. Config at the Right Layer

Different configuration belongs at different levels:

- **System config** — policies that apply to all users on a machine
- **User config** — personal preferences that apply to all projects
- **Project config** — requirements specific to a project (`~/.config/connie/projects/<slug>/config.yml`)
- **CLI flags** — one-off overrides for a single invocation

`connie` respects this layering and merges all sources with explicit, predictable
precedence. Higher layers override lower ones; the safe defaults are always
the fallback.

### 5. Build-time vs Runtime Separation

Some configuration affects the container *image* (packages to install). Some
affects how the container *runs* (environment variables, ports). These are
fundamentally different:

- Image config changes require a rebuild but are cached by Docker's layer
  mechanism — you pay the cost once per change
- Runtime config changes take effect immediately with no rebuild

`connie` keeps these concerns separate. The Dockerfile handles image construction;
the Compose override handles runtime configuration; build `args` are the handshake
between them.

---

## Architecture

```text
┌─────────────────────────────────────────────────────────────────┐
│  connie repository (installed once per developer machine)       │
│                                                                 │
│  src/connie                   CLI entry point                   │
│  src/docker/base.Dockerfile   Alpine + core tools + Claude Code │
│  src/docker/entrypoint.sh     Container startup script          │
│  src/docker/docker-compose.yml Hardened Compose base            │
│  src/docker/extend.Dockerfile Per-project build template        │
│  src/config/defaults.yml      Compiled-in defaults              │
│  src/config/project.yml       Project config template           │
│  Makefile                     Install / uninstall               │
└────────────────────┬────────────────────────────────────────────┘
                     │ installed to /usr/local/bin/connie
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│  Developer machine                                              │
│                                                                 │
│  /usr/local/bin/connie              The CLI                     │
│  /usr/local/lib/connie/docker/      Dockerfiles, entrypoint     │
│  /usr/local/lib/connie/config/      defaults.yml, project.yml   │
│  connie/base:latest                 Locally built base image    │
│  /etc/xdg/connie/config.yml         System-wide config (opt.)   │
│  ~/.config/connie/config.yml        User config (optional)      │
└────────────────────┬────────────────────────────────────────────┘
                     │ reads
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│  Project directory (completely untouched)                       │
│  (any existing project, unmodified)                             │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  XDG directories (on developer machine)                         │
│                                                                 │
│  ~/.config/connie/projects/<slug>/                              │
│  └── config.yml           Project config (editable)             │
│                                                                 │
│  ~/.local/state/connie/<slug>/                                  │
│  ├── .claude/             Claude Code state — per-project       │
│  └── .claude.json         Claude Code auth — per-project        │
│                                                                 │
│  ~/.local/share/connie/                                         │
│  └── projects.yml         Project registry (path → slug)        │
└─────────────────────────────────────────────────────────────────┘
```

### Image Hierarchy

```text
alpine:3.20  (pulled from Docker Hub)
      │
      │  built by 'connie build-base' (or automatically on first 'connie run')
      ▼
connie/base:latest  (local image)
  Alpine 3.20 + core tools + claude-user (uid 1000) + Claude Code
      │
      │  built by 'connie run' / 'connie build'
      ▼
connie-workspace  (local image, per project)
  base image + project-specific packages from config.yml
```

### Config Merge Flow

```text
defaults.yml                                  (lowest precedence)
      +
/etc/xdg/connie/config.yml
      +
~/.config/connie/config.yml
      +
~/.config/connie/projects/<slug>/config.yml
      +
CONNIE_CMD / CONNIE_MEMORY / CONNIE_CPUS / CONNIE_MAX_PIDS
      +
CLI flags                                     (highest precedence)
      │
      ▼
  merged config
      │
      ├──► build args  ──► extend.Dockerfile ──► docker compose build
      │
      └──► runtime config ──► override.yml ──► docker compose run
```

Note: `TERM` and `COLORTERM` from the host shell are forwarded into the
container as the lowest-precedence env entries — below even `defaults.yml`.
This is handled separately in `_generate_override`, not through the merge
pipeline above. See [Terminal Environment Forwarding](#terminal-environment-forwarding).

---

## The Container Security Model

### Non-Root User

Claude Code runs as `claude-user` (`uid 1000`, `gid 1000`), not root. This is
the most important single hardening measure: a compromised process has no
ability to affect the host system even if it escapes the container, because it
has no root privileges to begin with.

The user is created in the base image and Claude Code is installed as that user
via the official install script, which places the binary in
`/home/claude-user/.local/bin/`.

### Read-Only Root Filesystem

The container image is immutable at runtime. No process can modify binaries,
install software, or alter configuration in the image layers. Any path that
legitimately needs to be writable is explicitly provided via volume mount or
`tmpfs`.

### All Capabilities Dropped

Linux divides root's privileges into discrete capabilities. Dropping all of
them means that even a process running as root could not perform privileged
operations. Combined with the non-root user, this provides defense in depth.

### `no-new-privileges`

Prevents any process from gaining capabilities via `setuid` binaries or similar
escalation paths, even if such binaries exist in the image. The base image also
removes all `suid`/`sgid` bits at build time as an additional measure.

### `tmpfs` for Writable System Paths

With a read-only root, the only writable system path is `/tmp`, mounted as
`tmpfs`. The entrypoint script redirects all `XDG` user directories there at
startup:

| Variable | Path | Purpose |
| --- | --- | --- |
| `XDG_CACHE_HOME` | `/tmp/.cache` | Tool caches |
| `XDG_CONFIG_HOME` | `/tmp/.config` | Runtime config |
| `XDG_DATA_HOME` | `/tmp/.local/share` | Application data |
| `XDG_STATE_HOME` | `/tmp/.local/state` | Runtime state |
| `XDG_RUNTIME_DIR` | `/tmp/runtime` | Sockets and PIDs |
| `GIT_CONFIG_GLOBAL` | `/tmp/.gitconfig` | Git global config |

All of these are RAM-backed and vanish on container exit.

### Auto-Updater Disabled

`DISABLE_AUTOUPDATER=1` is baked into the base image. Without this, Claude
Code's auto-updater silently hangs at startup on a read-only filesystem —
it cannot write the update files and waits indefinitely. Disabling it is
required for the read-only container model to work.

To update Claude Code, run `connie build-base` to rebuild the base image
against the latest installer. See [Rebuild Triggers](#rebuild-triggers).

### Terminal Environment Forwarding

`TERM`, `COLORTERM`, and a derived `FORCE_COLOR` are forwarded from the host
shell into the container on every `connie run`, at the lowest config
precedence. They can be overridden via `config.yml` `env:` or `--env`.

**Why `FORCE_COLOR`**: `Node.js` applications (including Claude Code) use
`process.stdout.getColorDepth()` to determine color support. Inside a Docker
`PTY` this probe consistently underestimates the host terminal's capabilities —
it reports basic 16-color support even when `TERM=xterm-256color` and
`COLORTERM=truecolor` are correctly set. `FORCE_COLOR` bypasses the probe
entirely and directly asserts the color support level, giving Claude Code the
same rendering fidelity it has when run directly on the host.

**Why `ncurses-terminfo-base`**: Non-`Node.js` TUI tools (`less`, `vim`, `git
log`, etc.) look up terminal capabilities in the `terminfo` database. Alpine
Linux ships with no `terminfo` entries; without `ncurses-terminfo-base` a
forwarded `TERM=xterm-256color` produces "terminal not found" warnings and
falls back to no-color mode for all shell tools.

### Host Mounts

Exactly three locations on the host filesystem are visible inside the container:

| Host path | Container path | Access | Purpose |
| --- | --- | --- | --- |
| `[project dir]` | `/workspace` | Read/Write | The project being worked on |
| `~/.local/state/connie/<slug>/.claude/` | `~/.claude/` | Read/Write | Claude Code state, memory, and credentials — per-project |
| `~/.local/state/connie/<slug>/.claude.json` | `~/.claude.json` | Read/Write | Claude Code app config — per-project |

The project directory is mounted read/write but nothing is ever written to it
by connie. The state mounts must be pre-created on the host before Docker
mounts them — with a read-only container filesystem Docker cannot create the
mount point at the target path if it doesn't exist in the image.

### Resource Limits

| Resource | Default |
| --- | --- |
| Memory | 4GB |
| CPU | 2 cores |
| PIDs | 512 |
| File descriptors (soft) | 4096 |
| File descriptors (hard) | 8192 |

All limits are overridable per-project in `config.yml` under `resources`.

---

## The Base Image

The base image (`connie/base:latest`) is built locally by `connie build-base`
from `src/docker/base.Dockerfile`. It is not published to any registry.

### Build Process

Claude Code is installed by running the official install script
(`https://claude.ai/install.sh`) *as the `claude-user` user*. This mirrors
the recommended installation method and ensures the binary and supporting files
land in `/home/claude-user/.local/bin/` with correct ownership — which is where
Claude Code expects to manage itself.

Installing as the correct user, rather than as root via `npm install -g`, avoids
permission mismatches and ensures Claude Code can locate its own files at runtime.

### Contents

| Component | Purpose |
| --- | --- |
| `alpine:3.20` | Minimal base |
| `bash`, `coreutils`, `grep`, `sed`, `gawk`, `findutils` | Shell and core utils |
| `git` | Source control |
| `curl`, `wget` | HTTP clients |
| `ripgrep`, `fd`, `jq`, `tree`, `file` | Search and file tools |
| `tar`, `gzip`, `unzip` | Archive tools |
| `build-base`, `libgcc`, `libstdc++`, `linux-headers` | Native module support |
| `lsof` | Process diagnostics |
| `ncurses-terminfo-base` | Terminal capability database for TUI tools |
| `claude-user` (uid/gid 1000) | Non-root runtime user |
| Claude Code | The AI coding assistant |
| `entrypoint.sh` | Runtime environment setup |

### Rebuild Triggers

On first use, `connie run` and `connie build` automatically build the base
image if it does not exist. Run `connie build-base` explicitly when:

- A new version of Claude Code is available
- You want to update the Alpine base or tooling versions

---

## Authentication

Claude Code authenticates via `OAuth`. On first `connie run` for a project, it
prompts the user to log in via browser. Credentials are written to
`~/.local/state/connie/<slug>/.claude.json` and `.claude/`.

On subsequent runs for the same project, the saved credentials are reused
automatically — no re-authentication needed.

Each project authenticates independently. Running `connie` against a new project
requires a one-time authentication for that project. This is intentional: it
ensures each project's Claude Code session is fully isolated, including the
auth context.

No API keys are required. Authentication uses the user's Anthropic subscription.

---

## File Ownership Model

**Managed by `connie` (do not edit):**

- `$LIB_DIR/docker-compose.yml` — hardened Compose base, shared across all projects
- `$LIB_DIR/extend.Dockerfile` — generic build template, shared across all projects
- Compose override — written to a temp file at runtime, deleted when connie exits

**Owned by the developer (edit freely):**

- `~/.config/connie/projects/<slug>/config.yml` — the project contract

**Owned by Claude Code (do not edit manually):**

- `~/.local/state/connie/<slug>/.claude/` — session state, memory, history
- `~/.local/state/connie/<slug>/.claude.json` — auth tokens and config

**Managed by connie (registry):**

- `~/.local/share/connie/projects.yml` — maps project paths to their slugs

**Never touches the project directory:**

- Nothing is written to the project's source tree. No `.gitignore` update needed.

---

## Future Directions

Explicitly out of scope for the initial implementation but accounted for in
the architecture:

- **SSH agent forwarding** — a future `ssh` config key in `config.yml`
- **Multiple containers per project** — `config.yml` structure supports
  a `services` key for multi-container stacks
- **Registry publishing** — for teams that want to share the base image
- **`connie init --update`** — refresh tool-managed files from updated templates
  without overwriting `config.yml`
- **Capability grants** — a `capabilities` key for projects that need specific
  Linux capabilities re-granted
- **Shell completions** — `connie completion bash|zsh|fish`
