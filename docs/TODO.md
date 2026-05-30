# TODO

Ideas and planned features for future development. Items here are under
consideration — not committed to any release.

---

## Features

### SSH Agent Forwarding

Forward the host's `SSH_AUTH_SOCK` into the container so Claude Code can
perform authenticated git operations (clone, push, fetch) without embedding
credentials in the image.

Planned approach: a `ssh:` config key in `config.yml` that opts in to the
mount. The socket path is taken from `$SSH_AUTH_SOCK` on the host.

### `connie init --update`

Refresh `config.yml` from the current installed template, merging in any
new keys with their defaults while preserving the user's existing values.

Useful after a `connie` upgrade that adds new config options.

### Multiple Containers Per Project

Allow `config.yml` to define a `services:` key describing a multi-container
stack (e.g. app + database). The current config structure was designed to
accommodate this without breaking changes.

### Registry Publishing

Support pushing the base image to a private registry so teams can share a
single built base rather than each developer building it locally.

---

### `--verbose` Flag

Add a `--verbose` flag to `run` and `build` that narrates the config merge
process to stderr — which config files were found and loaded, which packages
are being installed, what command will be run. Distinct from `connie config`,
which shows the generated artifact; `--verbose` describes the process.

### Rules-Directory Previewing in `connie context`

`connie context` currently shows the four primary Claude Code scopes
(managed policy, user-level, project, local) but does not show
`~/.claude/rules/*.md` (user-level rules) or `<project>/.claude/rules/*.md`
(project rules). Per the Claude Code memory docs, rules without `paths:`
frontmatter load at session start; rules with `paths:` load when matching
files are opened.

Adding rules to the preview would require:

- Walking the two rules directories recursively for `*.md` files
- Parsing each file's YAML frontmatter to identify unconditional vs.
  path-scoped rules
- Displaying them under the appropriate scope, ideally with a note when
  a rule is path-scoped (so the user knows it won't always be in context)

Likely natural fit: nest the rules display *under* the relevant existing
scope (project rules under the Project scope header, user rules under
the User-level scope header) rather than introducing a fifth top-level
scope.

---

## Quality / Internals

### Expand Test Coverage

The roll-your-own POSIX shell test harness is in place under `tests/`,
with one unit-test file demonstrating it. Remaining work is filling out
coverage incrementally:

- **Unit (no I/O)**: `_merge_configs`, `_generate_override` and its
  sub-helpers (`_build_env_block`, `_build_vol_block`,
  `_build_ports_section`, `_build_fwd_env_obj`, `_build_cli_env_obj`),
  argument parser, `_compose_project_name`.
- **Integration (filesystem, no Docker)**: `cmd_init`, `cmd_config`,
  `cmd_context`, the four context emit functions, registry walk
  (`_register_project` together with `_find_project_root`),
  `_migrate_project` (from-old-`.connie/` migration), `_write_user_context`.
- **CLI (no Docker)**: `connie help`, `connie version`, error paths
  (unknown flag, unknown command, duplicate positional, missing
  required argument), the typo-subcommand guard.
- **Docker (gated)**: `connie build-base`, `connie build`, `connie run`
  with `--cmd sh`, `connie clean`. Needs to run on a host with Docker
  available; the harness should skip these when `docker` is absent.

### `connie update` Command

A command that rebuilds the base image and pulls the latest `connie` release in
one step, analogous to `brew upgrade`.

---

## Documentation

### Screencast / Quickstart GIF

A short terminal recording showing `connie init` + `connie run` from scratch
would lower the barrier for new users evaluating the tool.
