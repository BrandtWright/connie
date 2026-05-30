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
- **README badges** — CI status, license, latest release/version.
  Need the real `github.com/<org>/<repo>` URL because the badge
  endpoints embed it. shields.io is the standard provider.
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

### Docker-gated Tests

The test suite is complete — 152 non-Docker tests cover the pure
functions, the filesystem-touching helpers, and the CLI surface that
doesn't need a Docker daemon (all pass under both `ash` and `bash
--posix`); 31 Docker-gated tests under `tests/docker/` exercise the
subcommands that actually build images and start containers. See
`tests/README.md` for the conventions and `tests/docker/*.sh` for the
test files. Run with `make test` and `make test-docker` respectively;
the Docker layer exits 0 with a skip message when `docker` is absent
on the host.

What the Docker layer covers:

- **`connie build-base`** — image creation at the expected tag,
  `claude-user` user/uid, `DISABLE_AUTOUPDATER` baked in, entrypoint
  path, Claude Code binary installed, idempotence.
- **`connie build`** — per-project image creation, the
  `_generate_override` → `extend.Dockerfile` → `docker build` chain,
  `CONNIE_CONTEXT` reaching `/etc/claude-code/CLAUDE.md`, idempotence,
  the auto-build-base branch.
- **`connie clean`** — workspace image removal with base image
  retention (`down --rmi local` semantics), idempotence.
- **`connie run`** — full container lifecycle: starts as `claude-user`
  at uid 1000, `/workspace` bind mount surfaces project files,
  `/tmp` writable, root filesystem read-only, `/etc/claude-code/CLAUDE.md`
  present, no `CONNIE_NO_DISPATCH` leak into the container env.
- **Resource limits** — `mem_limit`, `pids_limit`, and `cpus` from the
  merged config actually constrain the running container (verified by
  reading the cgroup v2 hierarchy from inside).
- **Context parity** — the managed-policy context Claude Code sees
  inside the container reflects the same project config values that
  `connie context` previews on the host.
- **Auto-migration trigger** — a project with a legacy `.connie/`
  layout (no XDG config) is migrated to XDG paths transparently before
  the build proceeds, with the in-tree `.connie/` rmdir'd afterwards.

Isolation: Docker tests stage to `connie-test/base:harness-<test>-<pid>`
via the `CONNIE_BASE_IMAGE` env-var override (parameterized through
`extend.Dockerfile`'s leading `ARG BASE_IMAGE`), so they never touch
the user's production `connie/base:latest`. A per-subshell trap
removes the test images at exit.

### `connie update` Command

A command that rebuilds the base image and pulls the latest `connie` release in
one step, analogous to `brew upgrade`.

---

## Documentation

### Screencast / Quickstart GIF

A short terminal recording showing `connie init` + `connie run` from scratch
would lower the barrier for new users evaluating the tool.
