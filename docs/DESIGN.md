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
pipeline above. See [Terminal Environment Forwarding][terminal-env].

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
against the latest installer. See [Rebuild Triggers][rebuild-triggers].

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

Claude Code is installed by downloading the official install script
(`https://claude.ai/install.sh`) *as the `claude-user` user*, **verifying
its SHA256** against a pinned value declared as a Dockerfile ARG, and only
then executing it. The SHA pin closes what would otherwise be a textbook
`curl … | bash` supply-chain hole: a brief compromise of `claude.ai`
would otherwise ship arbitrary code into every fresh base image build.
If Anthropic ships a new installer the build fails loudly at
`sha256sum -c` until a maintainer reviews and refreshes the pin. The pin
appears in the build log on every rebuild (no hidden state), and a
maintainer can test a candidate update via
`docker build --build-arg CLAUDE_INSTALLER_SHA256=<new> …` without
editing the Dockerfile. Update procedure documented in a comment block
above the ARG declaration.

The Alpine base is also pinned by content digest, not just tag, so an
unexpected re-push to `alpine:3.20` cannot silently change what every
connie base image starts from.

Installing as `claude-user` rather than as root via `npm install -g` lands
the binary in `/home/claude-user/.local/bin/` with correct ownership —
which is where Claude Code expects to manage itself — and avoids
permission mismatches at runtime.

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
prompts the user to log in via browser. The OAuth bearer token Claude Code
persists at `~/.claude/.credentials.json` (inside the container) lands on
the host at `~/.local/state/connie/<slug>/.claude/.credentials.json` via the
bind mount; account metadata is written to
`~/.local/state/connie/<slug>/.claude.json` alongside it.

On subsequent runs for the same project, the saved credentials are reused
automatically — no re-authentication needed.

Each project authenticates independently. Running `connie` against a new project
requires a one-time authentication for that project. This is intentional: it
ensures each project's Claude Code session is fully isolated, including the
auth context.

No API keys are required. Authentication uses the user's Anthropic subscription.

### Credential storage

Persisting OAuth tokens on disk is the standard pattern for OAuth-based
tools — `~/.ssh/id_*`, `~/.aws/credentials`, `~/.config/gh/hosts.yml`, and
similar all persist credentials to per-user directories under `$HOME`.
Connie's contribution to this model is per-project isolation and
defense-in-depth on the directory permissions.

Connie does not write `.credentials.json` itself; Claude Code does, from
inside the container. What connie does is harden the directory hierarchy
around it. Both the per-project state directory
(`~/.local/state/connie/<slug>/`) and its `.claude/` subdirectory are
created — or normalised, when they already exist — with mode `0700` (user
read/write/exec, group and others denied) at `connie init`, `connie run`,
and during auto-migration. Even if Claude Code does not set restrictive
permissions on `.credentials.json` itself, the parent directories prevent
other local users on the same machine from traversing to it.

File ownership stays with the user running connie. No privilege escalation
is required at any layer, and the read-only container filesystem prevents a
compromised in-container process from rewriting the credential file through
any path other than the bind mount.

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

### XDG placement and machine-locality

Per-project config lives in `XDG_CONFIG_HOME` (`~/.config/connie/projects/<slug>/`)
because it is user-edited configuration — the textbook XDG_CONFIG_HOME case.
The `<slug>` is derived from the project path, so these entries are inherently
machine-local: a different machine without that exact path won't have a
matching project, and the config files there have no meaning.

`XDG_STATE_HOME` has stronger spec language about non-portability ("not
important or portable enough to the user that it should be stored in
`XDG_DATA_HOME`") and would also be defensible for machine-local data. It
was not chosen here because state-home is conventionally for application-
managed state (logs, history, undo, layout) rather than user-edited input,
and putting hand-curated config files there breaks the "config = stuff I
edit" mental model that other CLI tools (`gh`, `git`, VS Code, etc.)
reinforce by placing similar machine-specific user config under
`XDG_CONFIG_HOME`.

The practical consequence for developers who sync `~/.config/` to a
dotfiles repository: exclude `~/.config/connie/projects/` from the sync.
The rest of `~/.config/connie/` — including any user-level
`~/.config/connie/config.yml` — is portable and safe to sync.

---

## Claude Code Context Model

Claude Code loads `CLAUDE.md` files from four scopes, documented in the
[Claude Code memory documentation][claude-code-memory]:

| Scope | Location in container | Populated by | Loaded |
| --- | --- | --- | --- |
| Managed policy | `/etc/claude-code/CLAUDE.md` | connie (build time) | Every session, immutable |
| User-level | `~/.claude/CLAUDE.md` | connie (run time) | Every session |
| Project | `/workspace/[.claude/]CLAUDE.md` | the project | When working in `/workspace` |
| Local | `/workspace/CLAUDE.local.md` | the developer | When working in `/workspace` |

connie populates the managed-policy and user-level scopes because they
describe context that the project itself cannot articulate without
knowing about connie. The project and local scopes come from `/workspace`
exactly as Claude Code finds them — connie never touches
`/workspace/CLAUDE.md` or `/workspace/CLAUDE.local.md`, preserving the
non-invasive contract.

### Managed-policy: the connie self-description

The managed-policy scope is the only Claude Code scope that the user
cannot exclude. This is the right home for context describing connie
itself and how the container has been customized for the project:

- A short description of what connie is
- Filesystem layout (`/workspace` read/write, `/tmp` tmpfs, rest read-only)
- Available tooling (base-image utilities + packages from `config.yml`)
- Build-time setup commands
- Additional mounts and exposed ports
- Environment variables
- Resource limits
- Security constraints

All of this is derivable from the merged config (see [Config Merge Flow]
(#config-merge-flow)). At build time, `_generate_connie_context` reads
the merged config, emits the markdown, and `_generate_override` encodes
it as a JSON-string YAML value in the Compose override under
`build.args.CONNIE_CONTEXT`. `extend.Dockerfile` writes it to
`/etc/claude-code/CLAUDE.md` inside the image as root. Docker's layer
cache makes the rebuild instant when the content has not changed.

JSON encoding is used because multi-line YAML block scalars require
indentation matching the parent key. A JSON-encoded string is single-line
with `\n` escapes, which YAML's double-quoted string syntax decodes back
to a real multi-line value on parse. This avoids any indentation-tracking
logic in the heredoc that produces the override.

### User-level: host preferences into the container

The user-level scope is the right home for host-side preferences that
apply to every project — coding style, commit message format, personal
workflow notes. These live on the host at `~/.claude/CLAUDE.md`, plus
potentially `/etc/claude-code/CLAUDE.md` for system-wide host context.
Connie respects both by reading them at run time and concatenating them
into the per-project state directory's `.claude/CLAUDE.md`. The state
directory is bind-mounted to `~/.claude/` inside the container, so the
assembled file lands at the path Claude Code expects.

Each source contribution is preceded by a block-level HTML comment
identifying its origin (`<!-- source: /etc/claude-code/CLAUDE.md on host
(system-wide) -->` and `<!-- source: ~/.claude/CLAUDE.md on host
(user-specific) -->`). Claude Code strips block-level HTML comments from
CLAUDE.md content before injecting it into context, so these markers cost
no tokens. They remain visible to humans previewing the assembled file
via `connie context` or by inspecting the state directory directly, which
makes it straightforward to trace any user-level instruction back to its
host source.

Assembly is split between two functions:

- `_emit_user_context` — emits the assembled content (including source
  markers) to stdout. Pure; no side effects.
- `_write_user_context` — calls `_emit_user_context` and redirects its
  output to the state directory. Removes the destination instead of
  leaving a zero-byte file when both host sources are absent.

`cmd_run` calls `_write_user_context` after `_generate_override` writes
the Compose file but before the container starts. `cmd_context` calls
only `_emit_user_context` — preview never updates on-disk state.

Host-side edits to `~/.claude/CLAUDE.md` or `/etc/claude-code/CLAUDE.md`
are snapshotted at `connie run` time, consistent with how connie handles
all other config. A change on the host takes effect on the next run, not
the current one.

### Project and local: the project's own context

connie never reads or writes these. They are part of `/workspace`, which
is mounted from the host project directory. If a project already uses
`CLAUDE.md`, it works as-is — Claude Code finds it via its normal
directory-walk loading. The project author has no need to know connie
exists.

### Previewing

`connie context [dir]` prints all four Claude Code scopes — the two
connie populates and the two it reads from the project directory —
without launching the container or modifying any on-disk state. It is
the cheapest way to verify what Claude Code will actually load.

| Scope shown | Source on host | Generator |
| --- | --- | --- |
| Managed policy | derived from merged config | `_generate_connie_context` |
| User-level | `/etc/claude-code/CLAUDE.md` + `~/.claude/CLAUDE.md` | `_emit_user_context` |
| Project | `<project>/CLAUDE.md` + `<project>/.claude/CLAUDE.md` | `_emit_project_context` |
| Local | `<project>/CLAUDE.local.md` | `_emit_local_context` |

All four emit functions are pure: they print to stdout, take no side
effects, and emit nothing if their sources are absent. `cmd_context`
prints them in load order (broadest to most specific). The four scopes
are wrapped between a document-level preview header and footer, with
each scope preceded by a per-scope header identifying the scope number
(1/4 through 4/4), its container path, and how its content gets there.

All preview structure — document header, per-scope headers, footer, and
empty-scope markers — is written to stdout as block-level HTML comments.
Claude Code strips block-level HTML comments before context injection
per its memory documentation, so the markers cost no tokens if the
preview is ever redirected to a file and loaded back as actual context.
The advantage of putting the structure on stdout (rather than stderr)
is that `connie context > preview.md` produces a coherent, self-
contained document with every scope clearly delineated rather than
losing the scope labels on redirect.

Source-attribution markers within a scope (when multiple host files
contribute — user-level from two host paths, project from `./CLAUDE.md`
and `./.claude/CLAUDE.md`) follow the same HTML-comment convention.
Together with the section headers, they let humans trace any
instruction back to its source.

What's not yet previewed: `.claude/rules/*.md` (project and user
rules), which Claude Code also loads. Their inclusion would require
walking the rules directories and parsing per-file frontmatter for
path-scoped rules — a worthwhile follow-up but out of scope for the
initial preview.

---

## Test Architecture

connie ships with 226 tests organised across four layers under `tests/`.
The harness is a roll-your-own POSIX shell harness — no external
framework — written in the same `sh` discipline as `src/connie` so the
test layer doesn't introduce a runtime dependency.

### Layers

| Layer | Path | Tests | Purpose |
| --- | --- | --- | --- |
| Unit | `tests/unit/` | 68 | Pure functions: `_project_slug`, `_merge_configs`, `_generate_override` and its sub-helpers, `_generate_connie_context`, `_compose_project_name`, etc. |
| Integration | `tests/integration/` | 51 | Filesystem-touching helpers: `_migrate_project`, `_register_project`, `_find_project_root`, `cmd_init`, the context-emit functions. |
| CLI | `tests/cli/` | 76 | Top-level subcommand behaviour observable via stdout/stderr/exit code: `connie help`, `connie config`, `connie context`, `connie list`, `connie remove`, including the diagnostic case where a project isn't initialised. |
| Docker | `tests/docker/` | 31 | End-to-end against real images and containers: `build-base`, `build`, `clean`, `run` lifecycle, cgroup-v2 resource-limit enforcement, host↔container context parity, `.connie/` → XDG auto-migration trigger. Gated on `docker` being on `$PATH`. |

### DSL

Tests are written as behaviour specifications using a `given` / `when` /
`expect` DSL where each step is a named function the framework executes
and records. The function names themselves are the documentation; no
description strings.

```sh
build_succeeds_against_an_initialized_project_test_case() {
    given a_unique_test_base_image_tag_and_an_initialized_project
    when the_user_runs_connie_build_against_the_project
    expect it_succeeds
    expect the_workspace_image_exists
}
```

Convention: **one logical claim per test**. Multiple `expect` calls are
allowed when they describe inseparable aspects of the same claim
(e.g. "the build succeeded AND the image was tagged AND the cmd ran").
Tests are discovered by an `awk` scan for `*_test_case()` function
definitions, so a test file is just a collection of functions with no
boilerplate.

### Isolation

Each test runs in a fresh subshell with:

- A `mktemp -d` workspace assigned to `$WORKSPACE`
- `HOME` and every `XDG_*` env var redirected into the workspace, so
  connie's path-derived globals (`CONFIG_DIR`, `STATE_DIR`, …) point at
  a sandbox rather than the developer's real state
- `$TEST_STDOUT` and `$TEST_STDERR` files where `exercise_connie`
  captures the subject's output for capture-based assertions

Tests source `src/connie` with `CONNIE_NO_DISPATCH=1` so the function
definitions load without firing `_main`. The flag is set, exported,
and unset explicitly around the `.` to avoid a POSIX special-builtin
quirk under `bash --posix` (a leaked `CONNIE_NO_DISPATCH=1` would
propagate to subsequent `exercise_connie` subprocess invocations and
silently skip dispatch).

### Docker layer isolation

Docker tests stage to a per-subshell `connie-test/base:harness-<test>-<pid>`
image tag via the `CONNIE_BASE_IMAGE` env var override (parameterized
through `extend.Dockerfile`'s `ARG BASE_IMAGE` before `FROM`). The
trap-on-exit removes both the base image, the workspace image, and the
per-project network so neither the user's production `connie/base:latest`
nor Docker's IPAM pool accumulates state across runs. The IPAM cleanup
exists because `docker compose run --rm` removes the container but not
the network — without explicit cleanup, the default pool exhausts after
~30 tests with "all predefined address pools have been fully subnetted."

### Hooks for testability

A few overrides in `src/connie` exist purely so tests can stage
fixtures without touching system paths or production tags:

- `CONNIE_BASE_IMAGE` — overrides the default `connie/base:latest`
  tag. Docker tests use this to isolate from the user's production
  image. Also useful outside testing — e.g. building
  `connie-arm/base:latest` on an arm host alongside the x86_64 tag.
- `CONNIE_ETC_CLAUDE_MD` — overrides the host's system-wide Claude
  Code policy path (`/etc/claude-code/CLAUDE.md` by default). The
  test harness redirects this to a fixture file so tests pass on
  hosts where `/etc/claude-code/` doesn't exist.
- `CONNIE_LIB_DIR` — overrides the installed lib path so contributors
  can test changes against the working tree without reinstalling.
- `CONNIE_NO_DISPATCH` — suppresses `_main` dispatch when set, so the
  test harness can source `src/connie` purely for function definitions.

### Runtime auto-detection

`cmd_run` runs `docker compose run --rm workspace` after the build
phase. The compose file sets `tty: true` so interactive Claude Code
gets a real PTY, but the same setting makes `docker compose run` refuse
to start when stdout isn't a terminal. `cmd_run` auto-detects this
with `[ -t 1 ]` and passes `-T` when stdout isn't a TTY, so the same
subcommand works in interactive sessions, in CI, in the test harness,
and any other output-redirected context without needing an explicit
flag.

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

[terminal-env]: #terminal-environment-forwarding
[rebuild-triggers]: #rebuild-triggers
[claude-code-memory]: https://code.claude.com/docs/en/memory
