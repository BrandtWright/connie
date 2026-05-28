# connie

A CLI tool that runs [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
in a constrained, reproducible container attached to a project directory.

Point `connie` at any project and it builds a hardened container with Claude
Code pre-installed, mounts the project as a workspace, and drops you straight
into Claude Code — ready to assist with development tasks.

---

## How It Works

```
connie run ~/repos/my-project
        │
        ├── reads  .devbox/.containerrc        project dependencies + config
        ├── builds connie-workspace image      base image + project packages
        ├── mounts ~/repos/my-project       →  /workspace          (read/write)
        ├── mounts .devbox/.claude/         →  ~/.claude/           (read/write)
        ├── mounts .devbox/.claude.json     →  ~/.claude.json       (read/write)
        └── starts Claude Code              inside the hardened container
```

Claude Code state (auth tokens, project memory, conversation history) is stored
in `.devbox/` alongside the rest of the project's container config. Each project
has completely isolated Claude Code state — no memory or history leaks between
projects.

---

## Requirements

- Docker Engine 24.0 or later
- Docker Compose v2.20 or later (`docker compose` plugin, not `docker-compose`)
- `yq` v4.x — YAML processor ([install guide](https://github.com/mikefarah/yq))
- A POSIX-compliant shell (`sh`, `bash`, `zsh`, `dash` all work)

---

## Installation

```sh
git clone https://github.com/yourorg/connie
cd connie
make install                        # installs to /usr/local (may need sudo)
make install PREFIX=~/.local        # install without sudo
```

To uninstall:

```sh
make uninstall
make uninstall PREFIX=~/.local
```

---

## Quick Start

```sh
# 1. Scaffold connie config inside a project
connie init ~/repos/my-project

# 2. Optionally edit the config to add project-specific packages
$EDITOR ~/repos/my-project/.devbox/.containerrc

# 3. Start Claude Code in the container
connie run ~/repos/my-project
```

If you run `connie` from inside a project directory, the path argument is
optional — connie walks up the directory tree looking for `.devbox/`:

```sh
cd ~/repos/my-project
connie run
```

On first run, if the base image (`connie/base:latest`) has not been built yet,
connie builds it automatically before starting the container. This takes a few
minutes once per machine.

On first run per project, Claude Code will prompt you to authenticate with your
Anthropic account. Credentials are saved to `.devbox/.claude/.credentials.json` and reused
on every subsequent `connie run` for that project.

---

## Commands

| Command | Description |
|---|---|
| `connie build-base` | Build (or rebuild) the connie base image |
| `connie init [dir]` | Scaffold `.devbox/` inside a project |
| `connie run [dir]` | Build (if needed) and start Claude Code |
| `connie build [dir]` | Build the project container image without starting it |
| `connie clean [dir]` | Remove the locally built project container image |
| `connie help` | Show usage |
| `connie version` | Show version |

### Flags

These flags apply to `run` and `build`:

| Flag | Description |
|---|---|
| `--package <pkg>` | Install an additional apk package (repeatable) |
| `--env KEY=VALUE` | Set an additional environment variable (repeatable) |
| `--cmd <cmd>` | Override the start command (default: `claude`) |

Use `--cmd sh` to get a shell inside the container for debugging:

```sh
connie run --cmd sh
```

---

## Configuration

connie reads configuration from multiple sources and merges them in this order,
from lowest to highest precedence:

```
1. connie compiled-in defaults       (/usr/local/lib/connie/config/defaults.yml)
2. System-wide config                (/etc/connie/config.yml)
3. User config                       (~/.config/connie/config.yml)
4. Project config                    ([project]/.devbox/.containerrc)
5. Shell environment variables
6. CLI flags (--package, --env, --cmd)
```

### The Project Config: `.devbox/.containerrc`

This is the file you edit to describe a project's container needs. Created by
`connie init` and never overwritten by subsequent connie operations.

See [`.containerrc` reference](#containerrc-reference) below.

### User Config

Create `~/.config/connie/config.yml` to set preferences that apply to all
projects:

```yaml
# ~/.config/connie/config.yml
resources:
  memory: 8g
  cpus: "4.0"
```

---

## `.containerrc` Reference

```yaml
# Additional packages to install at build time (via apk).
# The base image already includes: bash, coreutils, grep, sed, gawk,
# findutils, git, curl, wget, ripgrep, fd, jq, tree, file, tar, gzip,
# unzip, lsof, build-base, and Claude Code. Add project-specific tools here.
packages:
  - python3
  - py3-pip
  - github-cli

# Environment variables injected at container runtime.
# connie automatically forwards TERM, COLORTERM, and FORCE_COLOR from the
# host shell so Claude Code renders with the same color fidelity inside the
# container as outside it. Override any of them here if needed.
env:
  APP_ENV: development
  LOG_LEVEL: debug
  # FORCE_COLOR: "2"   # override if your terminal only supports 256 colours

# Additional volume mounts beyond the standard mounts.
# Standard mounts (always present, not configured here):
#   [project dir]        →  /workspace                 (read/write)
#   .devbox/.claude/     →  ~/.claude/                 (read/write)
#   .devbox/.claude.json →  ~/.claude.json             (read/write)
volumes:
  - /some/other/path:/data:ro

# Port mappings (host:container).
ports:
  - "8080:8080"

# Command to run on container start.
# Default is 'claude'. Use 'sh' to get a shell for debugging.
start_cmd: claude

# Resource limit overrides (defaults shown).
# resources:
#   memory: 4g
#   cpus: "2.0"
#   max_pids: 512
```

---

## Security Model

Containers are hardened by default. See [DESIGN.md](DESIGN.md) for full
rationale. The enforced constraints are:

- **Non-root user** — Claude Code runs as `claude-user` (uid 1000), not root
- **Read-only root filesystem** — no process can modify image layers at runtime
- **All Linux capabilities dropped** — no privileged operations possible
- **`no-new-privileges`** — no privilege escalation via setuid or similar
- **`/tmp` as tmpfs** — RAM-backed, ephemeral, vanishes on exit
- **Auto-updater disabled** — `DISABLE_AUTOUPDATER=1` prevents silent writes
  to the read-only filesystem at startup
- **Exactly three host mounts** — project directory, `.devbox/.claude/`, and
  `.devbox/.claude.json` — nothing else from the host is visible
- **Resource limits** — 4GB RAM, 2 CPUs, 512 PIDs (all overridable)

---

## What Lives in `.devbox/`

```
.devbox/
├── .claude/             Claude Code credentials, history, and state — per-project
├── .claude.json         Claude Code account metadata and app config — per-project
├── .containerrc         Your project config (edit this)
├── docker-compose.yml   Hardened container base (managed by connie)
├── extend.Dockerfile    Per-project build template (managed by connie)
└── override.yml         Generated at runtime (ephemeral, never commit)
```

The entire `.devbox/` directory is gitignored — none of this is committed to
your project repository. The project under development never needs to know
connie exists.

---

## License

MIT
