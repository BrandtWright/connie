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

### Quality-Audit Remediation (in progress)

A deep code/test/security/docs review (2026-06-01) produced a prioritized
list of fixes. Items below are ordered by priority; each is intended to
land as its own focused commit (independent unless noted). Work happens on
the `quality-fixes` branch. **Prerequisite: the connie container running
this repo must have `yq` (and ideally `shellcheck`) in its `packages:` —
without `yq` the test suite fails wholesale and `src/connie` can't run.**

1. **Harness: fail tests when `given`/`when` steps exit non-zero.**
   `tests/harness.sh:112-122` — `given()`/`when()` call `"$@"` then emit a
   breadcrumb without checking the exit status; only `expect` counts
   failures. Combined with the `|| _status=$?` subshell wrapper (which
   disables `set -e`), a failing fixture/stimulus does not abort the test,
   so assertions can run against stale/empty state and falsely pass. Fix:
   check the step's status in `given`/`when` and mark the test failed (and
   emit a breadcrumb) on non-zero, mirroring `expect`. Re-run the full
   suite afterward — this may surface previously-masked failures that then
   need their own fixes.

2. **Fix broken Docker-test fixture path.** `tests/helpers/docker.sh:85`
   references `src/config/project-template.yml`, which does not exist (the
   file is `src/config/project.yml`; cf. `Makefile:64`, `src/connie:51`).
   The `cp` fails — silently, because of bug #1. One-line path fix.

3. **Deny `docker.sock` (and validate paths) in `volumes:`.**
   `_build_vol_block` (`src/connie:430-442`) passes arbitrary
   `host:container` entries through verbatim; nothing rejects mounting the
   Docker socket (full host-takeover) or host root. Add a reject for
   entries whose host path resolves to `*docker.sock*` (via `_die` with a
   hint); consider warning on other absolute-root mounts. Add unit tests
   under `tests/unit/build_vol_block_test_cases.sh`. Touches the same
   function as #7 — sequence #3 then #7, or fold the escaping in together.

4. **Docker-free coverage for `_prepare` and `_run_compose`.** These (the
   riskiest orchestration code) are only exercised through Docker-gated
   tests that `make test` skips. Add integration tests for `_prepare`
   (state pre-creation, `.claude/` + `.claude.json` creation, 0700 perms,
   `.claude.json` empty/dir repair, missing-config `_die`, auto-migrate
   trigger) and unit/integration tests for `_run_compose` arg assembly by
   stubbing a fake `docker` on `PATH` that records its argv. Also add the
   two cheap gaps: `_confirm` accept/reject paths (pipe `y\n` / empty to
   stdin) and `_require_yq` v4 sniff (stub a fake `yq`), plus an explicit
   env-vs-CLI verbosity precedence test (`-v` overrides `CONNIE_QUIET=1`).

5. **README: document `connie doctor` and `-q/-v`; single source of truth
   for test count.** `connie doctor` (shipped v0.4.0) is missing from the
   README Commands table (`README.md:100-112`); the `-q/--quiet` and
   `-v/--verbose` global flags are undocumented there too. Add both. Then
   fix the stale test-count figures: `CONTRIBUTING.md:100` ("183 tests"),
   `CONTRIBUTING.md:117` ("should still be 152/152"), and
   `.github/PULL_REQUEST_TEMPLATE.md:9` ("152+ tests") — actual is 226
   (will change once #4 adds tests; recount and update at the end).

6. **Wire `make format-check` into CI.** The target exists
   (`Makefile:170-176`, CI-safe: skips if shfmt absent) but isn't invoked.
   Add a `format-check` step to the `lint-and-test` job in
   `.github/workflows/ci.yml` (after `make lint`). Optional stretch:
   consider a macOS/arm64 matrix (deferred — note only).

7. **yq-encode `EXTRA_PACKAGES`/`command`/`volumes`/`ports`.** In
   `_generate_override` (`src/connie:494-521`) `EXTRA_PACKAGES` and
   `command:` are interpolated raw into double-quoted YAML while
   `BUILD_COMMANDS`/`CONNIE_CONTEXT` three lines up are properly
   yq-encoded; `volumes`/`ports` are built with raw `sed`. Make escaping
   consistent (yq-encode all user-controlled values) to prevent YAML
   breakout. Verify with `generate_override` unit tests (add cases with
   quotes/special chars). Coordinate with #3 (same function).

8. **Docs accuracy: credential wording + already-correct digest pin.**
   `docs/DESIGN.md` (~line 386-388) implies the read-only FS protects the
   credential file, but it lives on a *writable* bind mount — reword to
   reflect that the 0700 parent dirs are the protection, not the read-only
   root. Separately, `SECURITY.md:117-119` undersells the Alpine pin as a
   "release tag" with no immutability guarantee, but `base.Dockerfile:25`
   actually pins by digest (and `DESIGN.md:312-313` already says so) —
   update SECURITY.md to match. Both are doc-only.

**Cross-cutting:** add a `[Unreleased]` CHANGELOG entry; also fix the
duplicated `markdownlint-cli2` paragraph at `docs/CHANGELOG.md:118-129`
(copy-paste artifact). Run `make check`, `make lint`, and `make test`
before each commit; `make test-docker` if a build/run-chain change is
touched (#2, #3, #4, #7).

### Docker-gated Tests

The test suite is complete — 195 non-Docker tests cover the pure
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
