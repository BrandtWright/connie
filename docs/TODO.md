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

### Automated Test Suite

Currently verification is manual (`make check` + exercise against a scratch
project). A lightweight integration-test harness — likely a shell script that
runs `init`/`build`/`run --cmd`/`clean` against a fixture project and checks
exit codes and output — would catch regressions.

### `connie update` Command

A command that rebuilds the base image and pulls the latest `connie` release in
one step, analogous to `brew upgrade`.

---

## Documentation

### Screencast / Quickstart GIF

A short terminal recording showing `connie init` + `connie run` from scratch
would lower the barrier for new users evaluating the tool.
