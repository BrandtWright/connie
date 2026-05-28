# connie — Design Document

This document describes the architecture of connie, the reasoning behind its
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

connie answers these questions by running Claude Code inside a container with
an explicit, minimal set of permissions. The developer defines what the
container can touch. Everything else is denied by default.

The secondary goal is reproducibility. A container built from the same
`.containerrc` on any machine produces the same environment — the same tools,
the same configuration, the same constraints. This makes Claude Code sessions
predictable and auditable.

---

## Design Principles

### 1. Least Privilege by Default

The container is locked down at creation. Any capability not explicitly
required is absent. The developer opts *in* to capabilities, not out of them.

This is the opposite of Docker's defaults, which grant a broad capability set
and leave hardening as an exercise. For a tool that runs an AI agent against
your codebase, explicit constraint is more appropriate than implicit permissiveness.

### 2. Explicit Host Access

The container has read/write access to exactly two locations on the host:

- The project directory (`/workspace`) — what Claude Code is here to work on
- `~/.claude` — Claude Code's auth credentials and state, persisted across sessions

Nothing else on the host filesystem is visible to the container. No home
directory, no SSH keys, no git config, no other projects.

### 3. Non-Invasive

connie must be attachable to any existing project without modifying it. The
project's source tree, build system, and version control are untouched. The
only artifact connie places in a project is `.devbox/`, which is gitignored.

This principle is modeled on how `git` works: `.git/` is git's entire
footprint inside a project. The project does not need to know git exists to be
managed by it.

### 4. Config at the Right Layer

Different configuration belongs at different levels:

- **System config** — policies that apply to all users on a machine
- **User config** — personal preferences that apply to all projects
- **Project config** — requirements specific to a project (`.devbox/.containerrc`)
- **CLI flags** — one-off overrides for a single invocation

connie respects this layering and merges all sources with explicit, predictable
precedence. Higher layers override lower ones; the safe defaults are always
the fallback.

### 5. Build-time vs Runtime Separation

Some configuration affects the container *image* (packages to install). Some
affects how the container *runs* (environment variables, ports). These are
fundamentally different:

- Image config changes require a rebuild but are cached by Docker's layer
  mechanism — you pay the cost once per change
- Runtime config changes take effect immediately with no rebuild

connie keeps these concerns separate. The Dockerfile handles image construction;
the Compose override handles runtime configuration; build args are the handshake
between them.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  connie repository (installed once per developer machine)       │
│                                                                 │
│  bin/connie                   CLI entry point                   │
│  lib/connie/base.Dockerfile   Alpine + core tools + Claude Code │
│  lib/connie/templates/        Per-project Dockerfile + Compose  │
│  lib/connie/config/           Compiled-in defaults              │
│  Makefile                     Install / uninstall               │
└────────────────────┬────────────────────────────────────────────┘
                     │ installed to /usr/local/bin/connie
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│  Developer machine                                              │
│                                                                 │
│  /usr/local/bin/connie        The CLI                           │
│  /usr/local/lib/connie/       Templates, base.Dockerfile,       │
│                               compiled-in defaults              │
│  connie/base:latest           Locally built base image          │
│  /etc/connie/config.yml       System-wide config (optional)     │
│  ~/.config/connie/config.yml  User config (optional)            │
│  ~/.claude/                   Claude Code auth + state          │
└────────────────────┬────────────────────────────────────────────┘
                     │ reads
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│  Project directory (untouched except for .devbox/)              │
│                                                                 │
│  .devbox/                                                       │
│  ├── .containerrc             Project config (editable)         │
│  ├── docker-compose.yml       Hardened base (managed by connie) │
│  ├── extend.Dockerfile        Build template (managed by connie)│
│  └── override.yml             Generated at runtime (ephemeral)  │
└─────────────────────────────────────────────────────────────────┘
```

### Image Hierarchy

```
alpine:3.20  (pulled from Docker Hub)
      │
      │  built by 'connie build-base'
      ▼
connie/base:latest  (local image)
  Alpine 3.20 + bash + curl + git + coreutils + Node.js + Claude Code
      │
      │  built by 'connie run' / 'connie build'
      ▼
connie/workspace:<project>  (local image, per project)
  base image + project-specific packages from .containerrc
```

The base image is built once and reused across all projects. Project images
are built per-project and cached — rebuilds only occur when the project's
package list changes.

### Config Merge Flow

```
defaults.yml              (lowest precedence)
      +
/etc/connie/config.yml
      +
~/.config/connie/config.yml
      +
.devbox/.containerrc
      +
shell environment
      +
CLI flags                 (highest precedence)
      │
      ▼
  merged config
      │
      ├──► build args  ──► extend.Dockerfile ──► docker compose build
      │
      └──► runtime config ──► override.yml ──► docker compose run
```

---

## The Container Security Model

### Constraints and Their Rationale

**Read-only root filesystem (`read_only: true`)**

The container image is immutable at runtime. No process can modify binaries,
install software, or alter configuration in the image layers. Any path that
legitimately needs to be writable is explicitly listed.

**All capabilities dropped (`cap_drop: [ALL]`)**

Linux divides root's privileges into discrete capabilities. Dropping all of
them means that even a process running as root inside the container cannot
perform privileged operations — no raw network access, no filesystem
ownership changes, no kernel module loading.

**`no-new-privileges`**

Prevents any process from gaining capabilities via `setuid` binaries or
similar escalation paths, even if such binaries exist in the image.

**tmpfs for writable system paths**

With a read-only root, writable system paths are mounted as tmpfs:

| Path | Size | Purpose |
|---|---|---|
| `/tmp` | 256MB | General temporary files |
| `/root/.local/state` | 64MB | Runtime state for CLI tools |

Both are mounted `noexec` — binaries cannot be executed from them. Both are
RAM-backed and vanish on container exit.

**Exactly two host mounts**

| Mount | Access | Purpose |
|---|---|---|
| `[project dir]` → `/workspace` | Read/Write | The project being worked on |
| `~/.claude` → `/root/.claude` | Read/Write | Claude Code auth + state persistence |

Nothing else from the host is mounted. Claude Code can read and modify project
files, and its authentication state persists across sessions, but it cannot
reach anything else on the host filesystem.

**Resource limits**

| Resource | Default Limit |
|---|---|
| Memory | 4GB |
| CPU | 2 cores |
| PIDs | 512 |
| File descriptors (soft) | 1024 |
| File descriptors (hard) | 65536 |

All limits are overridable per-project in `.containerrc` under `resources`.

---

## The Base Image

The base image (`connie/base:latest`) is built locally by `connie build-base`
from `lib/connie/base.Dockerfile`. It is not published to any registry —
it lives on the developer's machine only.

Contents:

| Component | Purpose |
|---|---|
| `alpine:3.20` | Minimal base (~5MB) |
| `bash` | Shell (Claude Code and many tools expect bash) |
| `curl` | HTTP client |
| `git` | Source control |
| `coreutils` | GNU core utilities (consistent cross-platform behaviour) |
| `ca-certificates` | TLS root certificates for HTTPS |
| `nodejs` + `npm` | Claude Code runtime |
| `@anthropic-ai/claude-code` | The AI coding assistant |

The base image is rebuilt by running `connie build-base` again. This is
necessary when:

- A new version of Claude Code is released and you want to upgrade
- You want to update the Alpine base or Node.js version
- You are moving connie to a new machine

---

## Authentication

Claude Code authenticates via OAuth. On first run it opens a browser window,
the user logs in with their Anthropic account, and credentials are cached
locally. connie mounts `~/.claude` from the host into `/root/.claude` in the
container so these credentials persist across container sessions.

No API keys are required. Authentication uses the user's Anthropic subscription.

---

## File Ownership Model

**Managed by connie (do not edit):**
- `.devbox/docker-compose.yml` — hardened Compose base
- `.devbox/extend.Dockerfile` — generic build template
- `.devbox/override.yml` — generated at runtime, ephemeral

**Owned by the developer (edit freely):**
- `.devbox/.containerrc` — the project contract

**Never committed:**
- `.devbox/` as a whole — added to the project's `.gitignore`
- `.devbox/override.yml` — generated fresh on every `connie run`

---

## Future Directions

Explicitly out of scope for the initial implementation but accounted for in
the architecture:

- **SSH agent forwarding** — a future `ssh` config key in `.containerrc`
- **Multiple containers per project** — `.containerrc` uses a `services`
  structure ready to support multi-container stacks
- **Registry publishing** — for teams that want to share the base image
  rather than building it locally
- **`connie init --update`** — refresh tool-managed files from updated
  templates without overwriting `.containerrc`
- **Capability grants** — a `capabilities` key in `.containerrc` for
  projects that need specific Linux capabilities re-granted
- **Shell completions** — `connie completion bash|zsh|fish`
