# Contributing to connie

---

## Development Setup

connie is a self-hosting tool — once it is working you can use it to develop
itself.

```sh
git clone https://github.com/BrandtWright/connie
cd connie
make install PREFIX=~/.local       # install without sudo
make install-dev                   # install + set up the pre-commit hook
```

The base image is built automatically on first `connie run`. To build it
explicitly (e.g. to pre-warm the cache before testing):

```sh
connie build-base
```

To test changes without reinstalling, invoke the script directly and override
the library path:

```sh
CONNIE_LIB_DIR=./src ./src/connie build-base
CONNIE_LIB_DIR=./src ./src/connie init ~/repos/some-project
CONNIE_LIB_DIR=./src ./src/connie run  ~/repos/some-project
```

`CONNIE_LIB_DIR` overrides the default library path (`/usr/local/lib/connie`),
so Dockerfile, compose, and config-template changes are picked up without
reinstalling.

---

## Code Style

The CLI script (`src/connie`) must remain POSIX-compliant `sh`. No bashisms.
This ensures connie works on any system with a POSIX shell, including Alpine
Linux (which is what the container itself runs) and CI environments where bash
may not be the default.

Specific rules:

- Use `[ ]` not `[[ ]]`
- Use `$(cmd)` not `` `cmd` ``
- No `local` keyword — prefix private variables with `_` instead
- No bash arrays — use space-separated strings or newline-separated values
- Use `.` not `source`
- Syntax-check with: `sh -n src/connie`
- `make check` runs the syntax check
- `make lint` runs shellcheck (POSIX/bashism enforcement), markdownlint,
  hadolint, and yq parse-checks across every changed file type. Run it
  before staging any commit, or install the pre-commit hook with
  `make install-hooks` so it runs automatically.
- `make format` applies shfmt; `make format-check` (a blocking CI step)
  fails on any drift. The canonical formatter version is **shfmt v3.13.1**
  — the version CI installs (see `.github/workflows/ci.yml`). Different
  shfmt versions can format differently, so match it locally to avoid a
  CI-only failure. shfmt has no language manifest for Dependabot to track,
  so bump the pin in `ci.yml` (and this note) by hand.

### Markdown links

All links in markdown files use [reference style][md-reference-style] —
`[text][slug]` in the body, with `[slug]: url` definitions grouped at
the bottom of the file. Inline `[text](url)` links are disallowed and
mechanically caught by markdownlint's [MD054][md054] rule.

Why: inline links make line wrapping awkward (a long URL inside a
sentence either pushes the line past 80 chars or forces an ugly
break), and they scatter URL maintenance throughout the document —
updating a URL means searching the body instead of editing one entry
in a single bottom-of-file table. Autolinks (`<https://example.com>`)
for bare URLs are still fine.

---

## Project Structure

```text
connie/
├── Makefile                         Install / uninstall / lint / test / hooks
├── LICENSE                          MIT
├── README.md                        User-facing documentation
├── CONTRIBUTING.md                  This file
├── SECURITY.md                      Vulnerability reporting and security model
├── AGENTS.md                        Guidance for AI coding assistants working in this repo
├── docs/
│   ├── DESIGN.md                    Architecture and design decisions
│   ├── CHANGELOG.md                 Version history
│   └── TODO.md                      Planned work
├── src/
│   ├── connie                       The CLI script (POSIX sh)
│   ├── docker/
│   │   ├── base.Dockerfile          Alpine + core tools + Claude Code
│   │   ├── entrypoint.sh            Container startup script
│   │   ├── docker-compose.yml       Hardened Compose base
│   │   └── extend.Dockerfile        Per-project build template
│   └── config/
│       ├── defaults.yml             Compiled-in defaults
│       └── project.yml              Default project config template
├── tests/                           Shell-script test suite
│   ├── run.sh                       Entry point: non-Docker tests
│   ├── run-docker.sh                Entry point: Docker-gated tests
│   ├── harness.sh                   given/when/expect DSL
│   ├── helpers/                     Preconditions, stimuli, assertions
│   └── {unit,integration,cli,docker}/  Test files by layer
└── .github/workflows/ci.yml         GitHub Actions: check + lint + test
```

---

## Making Changes

### Changes to `src/connie`

1. Run `make check` (`sh -n src/connie`) to catch syntax errors
2. Run `make lint` to catch bashisms and other issues
3. Run `make test` — the non-Docker suite should stay all-green
4. If you change anything in the build/run chain, run `make test-docker`
   on a host with docker
5. Verify all config layers work (defaults, user config, project config, flags)

### Changes to `src/docker/base.Dockerfile`

The base Dockerfile defines what every connie container includes. Changes here
affect all projects on the next `connie build-base`. When making changes:

- Keep the image as small as possible — Alpine's value is its minimal footprint
- Add packages to the `apk add` block; do not add separate `RUN` layers
  unless there is a strong reason (each layer adds image size)
- Update `docs/DESIGN.md` if the contents of the base image change
- Test with `connie build-base && connie run <some-project>`

### Changes to `docker-compose.yml` or `extend.Dockerfile`

These files live in `src/docker/` and are installed to `$LIB_DIR/docker/` at
runtime — they are not copied into projects. Changes take effect for all
projects immediately after reinstalling (no `connie init` re-run needed).

When making security-relevant changes to `docker-compose.yml`, update
`docs/DESIGN.md` to reflect the new security posture.

### Changes to the project config template

`src/config/project.yml` is copied to
`~/.config/connie/projects/<slug>/config.yml` by `connie init`. Changing the
template does not affect already-initialised projects — only new `connie init`
runs pick up the change.

### Changes to `src/config/defaults.yml`

Changing a default value is a potentially breaking change — it affects all
projects that rely on that default. Treat default changes with the same care
as a public API change and document them in `docs/CHANGELOG.md`.

---

## Versioning

connie uses [Semantic Versioning][semver]:

- **Patch** — bug fixes, no behaviour changes
- **Minor** — new features, backward compatible
- **Major** — breaking changes to `config.yml` format or CLI interface

The version is defined in one place: the `VERSION` variable at the top of
`src/connie`. Update it and add an entry to `docs/CHANGELOG.md` with each
release.

---

## Changelog

Maintain `docs/CHANGELOG.md` in [Keep a Changelog][keep-a-changelog]
format. Each entry should explain what changed and why, not just list the diff.

[semver]: https://semver.org/
[keep-a-changelog]: https://keepachangelog.com/
[md-reference-style]: https://www.markdownguide.org/basic-syntax/#reference-style-links
[md054]: https://github.com/DavidAnson/markdownlint/blob/main/doc/md054.md
