# TODO

Ideas and planned features for future development. Items here are under
consideration — not committed to any release.

---

## Release-Integration Punch List

Items deferred until the project is ready for its first published
release on a real Git remote. None of these can land until the remote
URL is known and a GitHub repository exists; tracked here so they
don't get forgotten at release time.

- **GPG-signed release tags.** Switch from `git tag -a` to
  `git tag -s`. Requires a maintainer GPG key with a verified
  email matching the GitHub account; the key's public half goes into
  GitHub settings so signatures show as "verified" on the tag page.
  CI workflow may want a separate verification job.
- **SBOM generation in CI.** Add a workflow step that runs `syft`
  against the freshly built base image and uploads the SPDX or
  CycloneDX output as a release artifact. Closes the supply-chain
  story past the SHA-pinned installer: anyone downloading a release
  can verify exactly what packages shipped.
- **`.github/FUNDING.yml`.** Lists funding platforms (GitHub
  Sponsors, Ko-fi, etc.) used by the maintainer. GitHub renders a
  "Sponsor" button on the repo page when present.
- **GitHub repo metadata** — description, topics, the "About"
  sidebar's website/homepage field. Not files but worth checking off
  at release time so the project's GitHub page isn't blank.

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

### Richer `connie list` Output

`connie list` currently prints one absolute project path per line — minimal
and pipe-friendly by design. A future `--long`/`-l` (or `--format`) mode could
add columns drawn from data connie already has: the slug, a `(stale)` marker
when the registered path no longer exists on disk, a `(current)` marker for the
workspace containing `$PWD`, and — at the cost of a `docker image inspect` per
entry — whether the per-project image is built. Kept out of the default to
preserve clean, scriptable output.

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

### `connie update` Command

A command that rebuilds the base image and pulls the latest `connie` release in
one step, analogous to `brew upgrade`.

---

## Documentation

### Screencast / Quickstart GIF

A short terminal recording showing `connie init` + `connie run` from scratch
would lower the barrier for new users evaluating the tool.
