# connie

A CLI tool that runs [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
in a constrained, reproducible container attached to a project directory.

Point `connie` at any project and it builds a hardened container with Claude
Code and your project's dependencies pre-installed, mounts the project as a
workspace, and drops you straight into Claude Code — ready to assist with
development tasks.

---

## How It Works

```
connie run ~/repos/my-project
        │
        ├── reads .devbox/.containerrc   (project dependencies + config)
        ├── builds a container image     (base image + project packages)
        ├── mounts ~/repos/my-project    → /workspace  (read/write)
        ├── mounts ~/.claude             → /root/.claude  (auth persistence)
        └── starts Claude Code           inside the hardened container
```

The container has read/write access to exactly two locations on your host
machine: the project directory and `~/.claude` (so Claude Code stays
authenticated between sessions). Everything else is locked down.

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

Then build the base Docker image (required once after install):

```sh
connie build-base
```

`build-base` pulls Alpine 3.20, installs core tools and Claude Code, and tags
the result as `connie/base:latest` on your local machine. It only needs to be
re-run when you want to pick up a new version of Claude Code or the base tools.

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

On first run, Claude Code will open a browser window and prompt you to
authenticate with your Anthropic account. Credentials are saved to `~/.claude`
on your host machine and reused on every subsequent `connie run`.

---

## Commands

| Command | Description |
|---|---|
| `connie build-base` | Build the connie base image (once after install) |
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
projects. Useful for a preferred shell, default resource limits, or any other
setting you want across every project you work on.

```yaml
# ~/.config/connie/config.yml
start_cmd: claude --verbose     # pass flags to Claude Code globally

resources:
  memory: 8g      # you have a lot of RAM
  cpus: "4.0"
```

---

## `.containerrc` Reference

```yaml
# Additional packages to install at build time (via apk).
# The base image already includes: bash, curl, git, coreutils, and Claude Code.
packages:
  - python3
  - py3-pip
  - jq

# Environment variables injected at container runtime.
# Safe to commit — do not put secret values here.
env:
  APP_ENV: development
  LOG_LEVEL: debug

# Secret environment variables.
# List variable *names* here; values come from your shell environment at
# runtime and are never stored in this file.
secrets:
  - MY_API_KEY

# Additional volume mounts beyond the standard mounts.
# Standard mounts (always present, not configured here):
#   [project dir]  →  /workspace     (read/write)
#   ~/.claude      →  /root/.claude  (read/write)
volumes:
  - /some/other/path:/data:ro

# Port mappings (host:container).
ports:
  - "8080:8080"

# Command to run on container start.
# Default is 'claude'. Use 'sh' or 'bash' to get a shell for debugging.
start_cmd: claude

# Resource limit overrides.
# resources:
#   memory: 4g
#   cpus: "2.0"
#   max_pids: 512
```

---

## Security Model

Containers are hardened by default. See [DESIGN.md](DESIGN.md) for full
rationale. The enforced constraints are:

- **Read-only root filesystem** — no process can modify image layers
- **All Linux capabilities dropped** — even root has no special powers
- **`no-new-privileges`** — no privilege escalation via setuid or similar
- **tmpfs for writable system paths** — `/tmp` and `~/.local/state` are
  RAM-backed, ephemeral, and non-executable
- **Exactly two host mounts** — project directory and `~/.claude` only
- **Resource limits** — 4GB RAM, 2 CPUs, 512 PIDs (all overridable)

---

## Adding connie to a Project

The project being developed never needs to know about connie. The only
recommended change to a project is adding `.devbox/` to its `.gitignore`,
which `connie init` offers to do automatically.

---

## License

MIT
