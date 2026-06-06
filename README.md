# connie

[![CI][ci-badge]][ci-link]
[![License: MIT][license-badge]][license-link]
[![Version][version-badge]][version-link]

A CLI tool that runs [Claude Code][claude-code]
in a constrained, reproducible container attached to a project directory.

Point `connie` at any project and it builds a hardened container with Claude
Code pre-installed, mounts the project as a workspace, and drops you straight
into Claude Code — ready to assist with development tasks.

---

## How It Works

```text
connie run ~/repos/my-project
        │
        ├── reads   ~/.config/connie/projects/<slug>/config.yml   project config
        ├── reads   context.md beside each config layer (if present) connie context
        ├── builds  connie-workspace image                         base + packages
        ├── mounts  ~/repos/my-project  →  /workspace               (read/write)
        ├── mounts  ~/.local/state/connie/<slug>/.claude/         →  ~/.claude/
        ├── mounts  ~/.local/state/connie/<slug>/.claude.json     →  ~/.claude.json
        └── starts  claude --append-system-prompt <connie context>  in the container
```

Nothing is written to the project directory. Claude Code state (auth tokens,
project memory, conversation history) lives in `~/.local/state/connie/<slug>/`
on the developer's machine. Each project has completely isolated state — no
memory or history leaks between projects.

---

## Requirements

- Docker Engine 24.0 or later
- Docker Compose v2.20 or later (`docker compose` plugin, not `docker-compose`)
- `yq` v4.x — YAML processor ([install guide][yq-install])
- A POSIX-compliant shell (`sh`, `bash`, `zsh`, `dash` all work)

---

## Installation

```sh
git clone https://github.com/BrandtWright/connie
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

# 2. Edit the config to add project-specific packages
# (connie config shows the exact path)
connie config ~/repos/my-project

# 3. Start Claude Code in the container
connie run ~/repos/my-project
```

If you run `connie` from inside a project directory, the path argument is
optional — connie walks up the directory tree looking for a registered project
root and uses it automatically:

```sh
cd ~/repos/my-project
connie run
```

On first run, if the base image (`connie/base:latest`) has not been built yet,
connie builds it automatically before starting the container. This takes a few
minutes once per machine.

On first run per project, Claude Code will prompt you to authenticate with your
Anthropic account. Credentials are saved to `~/.local/state/connie/<slug>/`
and reused on every subsequent `connie run` for that project.

---

## Commands

| Command | Description |
| --- | --- |
| `connie build-base` | Build (or rebuild) the connie base image |
| `connie init [dir]` | Initialize connie for a project directory |
| `connie run [dir]` | Build (if needed) and start Claude Code |
| `connie build [dir]` | Build the project container image without starting it |
| `connie clean [dir]` | Remove the locally built project container image |
| `connie remove [dir]` | Remove all connie-owned state for a project (inverse of init) |
| `connie list` | List the project workspaces connie knows about |
| `connie config [dir]` | Show project paths and effective Compose override |
| `connie edit-config [dir]` | Edit a project's config in `$EDITOR` (`--user` for the user-global config) |
| `connie edit-context [dir]` | Edit a project's connie context (`--user` for the user-global context) |
| `connie context [dir]` | Generate and show the Claude Code context file |
| `connie doctor [dir]` | Diagnose required tools, install, base image, and project state |
| `connie help` | Show usage |
| `connie version` | Show version |

### Flags

These flags apply to `run`, `build`, and `config`:

| Flag | Description |
| --- | --- |
| `--package <pkg>` | Install an additional apk package (repeatable) |
| `--env KEY=VALUE` | Set an additional environment variable (repeatable) |
| `--cmd <cmd>` | Override the start command (default: `claude`) |

Use `--cmd sh` to get a shell inside the container for debugging:

```sh
connie run --cmd sh
```

### Verbosity

These flags apply to any subcommand and can also be set via environment
variable (the CLI flag wins when both are set):

| Flag | Env | Description |
| --- | --- | --- |
| `-q`, `--quiet` | `CONNIE_QUIET=1` | Suppress info/detail output; only errors reach stderr |
| `-v`, `--verbose` | `CONNIE_VERBOSE=1` | Also emit `[debug]` lines (traces the `docker compose` calls) |

---

## Configuration

connie reads configuration from multiple sources and merges them in this order,
from lowest to highest precedence:

```text
1. connie compiled-in defaults       (/usr/local/lib/connie/config/defaults.yml)
2. System-wide config                (/etc/xdg/connie/config.yml)
3. User config                       (~/.config/connie/config.yml)
4. Project config                    (~/.config/connie/projects/<slug>/config.yml)
5. Environment variables             (CONNIE_CMD, CONNIE_MEMORY, CONNIE_CPUS, CONNIE_MAX_PIDS)
6. CLI flags (--package, --env, --cmd)
```

Composition is additive and keyed: a higher-precedence layer overrides scalar
and map values (`resources`, `env`, `start_cmd`) and accumulates the list keys —
`build_commands` append in order, while `packages`, `ports`, and
`unsafe_extra_mounts` accumulate and collapse to one entry per identity (package
name, host port, container target), so a layer can also remap a port or redefine
a mount set by a more general one — or remove an inherited entry with a
`-<identity>` directive (`-vim`, `"-8080"`, `-/data`; for env, set the variable
to `null`). Configuration only ever changes application settings; it cannot
weaken the container's security posture.

`TERM` and `COLORTERM` from the host shell are automatically forwarded into
the container as the lowest-precedence env entries — below even project config.
They can be overridden via `config.yml` `env:` or `--env`.

### The Project Config

Each project has a `config.yml` at
`~/.config/connie/projects/<slug>/config.yml` where `<slug>` is derived from
the project's directory name and path. Created by `connie init` and never
overwritten by subsequent connie operations.

Run `connie config [dir]` to see the exact path for any project.

See [`config.yml` reference][configyml-ref] below.

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

## `config.yml` Reference

```yaml
# Additional packages to install at build time (via apk).
# The base image already includes: bash, coreutils, grep, sed, gawk,
# findutils, git, curl, wget, ripgrep, fd, jq, tree, file, tar, gzip,
# unzip, lsof, build-base, and Claude Code. Add project-specific tools here.
packages:
  - python3
  - py3-pip
  - github-cli

# Arbitrary shell commands run at image build time, as claude-user.
# Runs after apk packages, so apk-installed tools are available.
# Use for package managers not covered by apk: npm, pip, gem, cargo, etc.
# Commands run in sequence; the build fails if any command fails.
# Note: the base image does not expose a standalone npm — add nodejs and
# npm to packages: first if you need it here.
build_commands:
  - npm install -g markdownlint-cli2  # also needs packages: [nodejs, npm]
  - pip install black ruff            # also needs packages: [python3, py3-pip]

# Environment variables injected at container runtime.
# connie automatically forwards TERM, COLORTERM, and FORCE_COLOR from the
# host shell so Claude Code renders with the same color fidelity inside the
# container as outside it. Override any of them here if needed.
env:
  APP_ENV: development
  LOG_LEVEL: debug
  # FORCE_COLOR: "2"   # override if your terminal only supports 256 colours

# ADVANCED / opt-in: extra host bind mounts beyond the standard mounts
# (project dir → /workspace, plus this project's ~/.claude state). Extra
# mounts are the one config key that can hand the container a host resource,
# so the key is deliberately named. connie still refuses the catastrophic
# cases (Docker socket, /proc, /sys, /dev, daemon data, standard-mount
# shadowing, unsafe propagation), but the guard is best-effort — see
# "Security Model" and SECURITY.md. Only add what you must; prefer :ro.
# unsafe_extra_mounts:
#   - /some/other/path:/data:ro

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

## Claude Code Context

connie appends its own context to Claude's system prompt when it launches
Claude (`claude --append-system-prompt`). It writes no `CLAUDE.md` anywhere,
so a project's own `CLAUDE.md` (and `CLAUDE.local.md`) loads natively, exactly
as Claude Code finds it — connie never reads, writes, or shadows it. Projects
that already use `CLAUDE.md` work without modification.

The appended payload has up to four scopes, assembled from conventional files
on the host:

| Scope | Source on host | Included |
| --- | --- | --- |
| Application | generated from the merged config | always |
| Machine | `/etc/xdg/connie/context.md` | if the file exists |
| User | `~/.config/connie/context.md` | if the file exists |
| Project | `~/.config/connie/projects/<slug>/context.md` | if the file exists |

### Application — connie describing the container

connie generates a description of the container environment from the merged
config: filesystem constraints, available tools, installed packages,
build-time setup commands, additional mounts, exposed ports, environment
variables, and resource limits. This scope is always present.

### Machine / User / Project — your own context

Drop a `context.md` beside any config layer and its contents are appended
under a `## … Context` heading. Use the user file (`~/.config/connie/context.md`)
for personal preferences that apply everywhere, the project file for
per-project notes you don't want checked into the repo, and the machine file
(`/etc/xdg/connie/context.md`) for host-specific facts. These are plain
markdown — no YAML, no escaping — and changes take effect on the next
`connie run`. `connie edit-context [dir]` (or `--user`) opens the project or
user file for you; leave it empty to contribute nothing.

### Wiring it into other tools

The payload reaches Claude via `--append-system-prompt`. If you point connie
at a different tool with `start_cmd`, connie does not inject the flag (it
can't assume another tool understands it); read `connie context` and wire the
output into your tool however it expects.

### Previewing

Run `connie context [dir]` to print the exact payload connie will append —
without starting the container. It needs no Docker and is the quickest way to
verify what Claude will receive before a run. (A one-line diagnostic goes to
stderr, so `connie context > preview.md` captures just the payload.)

---

## Security Model

Containers are hardened by default. See [DESIGN.md][design-md] for full
rationale. The enforced constraints are:

- **Non-root user** — Claude Code runs as `claude-user` (uid 1000), not root
- **Read-only root filesystem** — no process can modify image layers at runtime
- **All Linux capabilities dropped** — no privileged operations possible
- **`no-new-privileges`** — no privilege escalation via setuid or similar
- **`/tmp` as tmpfs** — RAM-backed, ephemeral, vanishes on exit
- **Auto-updater disabled** — `DISABLE_AUTOUPDATER=1` prevents silent writes
  to the read-only filesystem at startup
- **Three host mounts by default** — project directory, per-project `.claude/`,
  and `.claude.json`; by default *nothing else is mounted*. A project may opt
  into extra mounts via the advanced `unsafe_extra_mounts:` key, but connie
  refuses the dangerous-mount class as a backstop (the
  Docker socket/data, kernel/device trees like `/proc`/`/sys`/`/dev`, host
  root, mounts that shadow the standard mounts, and unsafe propagation)
- **Resource limits** — 4GB RAM, 2 CPUs, 512 PIDs (all overridable)
- **Network egress is *not* filtered** — the container can reach any network
  the Docker daemon can; no inbound ports are exposed unless you list them.
  Enforce egress externally if your threat model needs it (see SECURITY.md)

---

## Where connie Stores Things

connie writes nothing to the project directory. All state lives in standard
XDG locations on your machine:

```text
~/.config/connie/
├── config.yml                        your personal preferences (all projects)
├── context.md                        your personal context, appended to Claude (optional)
└── projects/
    └── <slug>/
        ├── config.yml                project-specific config (edit this)
        └── context.md                project-specific context (optional)

~/.local/state/connie/
└── <slug>/
    ├── .claude/                      Claude Code credentials, history, state
    └── .claude.json                  Claude Code account metadata and config

~/.local/share/connie/
└── projects.yml                      registry: project paths → slugs
```

The `<slug>` is derived from the project directory name and path
(e.g. `my-project-1234567890`). Run `connie config [dir]` to see the exact
paths for any project.

The project directory itself is never modified — no `.gitignore` update, no
config files, nothing. The project does not need to know connie exists.

### Syncing `~/.config/` to a dotfiles repository

If you keep `~/.config/` in a dotfiles repository, exclude
`~/.config/connie/projects/` from the sync. The per-project configs there
are keyed to specific project paths on the current machine (via the
`<slug>`) and aren't meaningful on a different machine where the same
project doesn't exist at the same path. The rest of `~/.config/connie/`
— including any user-level `~/.config/connie/config.yml` you may add — is
safe to sync normally.

---

## Installed Files

`make install` copies connie's support files to `$LIBDIR` (default:
`/usr/local/lib/connie`). Here is what each file does and when it is used.

### Base image: `base.Dockerfile` + `entrypoint.sh`

Used together by `connie build-base` (and automatically on the first
`connie run` or `connie build` if the base image is absent).

`base.Dockerfile` drives `docker build` to produce the `connie/base:latest`
local image — Alpine Linux with core tools and Claude Code pre-installed.
`entrypoint.sh` is part of the same build context and gets baked into that
image as the container entrypoint: it sets up writable XDG directories in
`/tmp`, marks `/workspace` as a git safe directory, and `exec`s the requested
command as PID 1.

Neither file is ever copied to a project. The base image is built once per
machine and reused across all projects.

### Per-project image + compose: `docker-compose.yml` + `extend.Dockerfile`

Read directly from `$LIBDIR/docker/` on every `connie run`, `connie build`,
`connie clean`, and `connie config`. Neither file is copied to a project.

`docker-compose.yml` defines the hardened security posture that applies to
every project: read-only root filesystem, all Linux capabilities dropped,
`no-new-privileges`, `/tmp` as a tmpfs, and `init: true`. It references
`extend.Dockerfile` via `context: .`, so Docker uses `$LIBDIR/docker/` as the
build context.

`extend.Dockerfile` builds the per-project image on top of `connie/base:latest`,
accepting `EXTRA_PACKAGES` and `BUILD_COMMANDS` as build args. These are
injected at build time from the merged config — the image is rebuilt only when
they change; otherwise Docker's layer cache makes the build instant.

### Config: `config/defaults.yml`, `config/project.yml`, `config/user.yml`

`defaults.yml` is the lowest-precedence layer in connie's config merge. It is
read on every `connie run`, `connie build`, and `connie config` and is never
copied anywhere.

`project.yml` is copied once by `connie init` to
`~/.config/connie/projects/<slug>/config.yml` and never overwritten. It is the
developer-owned file that describes the project's container needs. It ships
inert — every key commented out — so a freshly-initialized project changes
nothing in the merge until you uncomment something (it won't, for example,
override a `start_cmd` you set at the user level).

`user.yml` is the analogous template for machine-wide personal preferences.
`connie edit-config --user` copies it once to `~/.config/connie/config.yml`
(creating it on first use) and never overwrites it; its settings apply to every
project, sitting just below per-project config in the merge.

---

## Further Reading

- [DESIGN.md][design-md] — architecture, security model, and design rationale
- [CHANGELOG.md][changelog-md] — version history

[ci-badge]: https://github.com/BrandtWright/connie/actions/workflows/ci.yml/badge.svg?branch=main
[ci-link]: https://github.com/BrandtWright/connie/actions/workflows/ci.yml
[license-badge]: https://img.shields.io/badge/License-MIT-yellow.svg
[license-link]: https://opensource.org/licenses/MIT
[version-badge]: https://img.shields.io/github/v/tag/BrandtWright/connie?label=version&sort=semver
[version-link]: https://github.com/BrandtWright/connie/releases
[claude-code]: https://docs.anthropic.com/en/docs/claude-code
[yq-install]: https://github.com/mikefarah/yq
[configyml-ref]: #configyml-reference
[design-md]: docs/DESIGN.md
[changelog-md]: docs/CHANGELOG.md

---

## License

MIT
