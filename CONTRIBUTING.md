# Contributing to connie

---

## Development Setup

connie is a self-hosting tool — once it is working you can use it to develop
itself. For bootstrapping, install your working copy locally:

```sh
git clone https://github.com/yourorg/connie
cd connie
make install PREFIX=~/.local       # install without sudo
```

The base image is built automatically on first `connie run`. To build it
explicitly (e.g. to pre-warm the cache before testing):

```sh
connie build-base
```

To test changes without reinstalling, invoke the script directly and override
the library path:

```sh
CONNIE_LIB_DIR=./lib/connie ./bin/connie build-base
CONNIE_LIB_DIR=./lib/connie ./bin/connie init ~/repos/some-project
CONNIE_LIB_DIR=./lib/connie ./bin/connie run  ~/repos/some-project
```

`CONNIE_LIB_DIR` overrides the default library path (`/usr/local/lib/connie`),
so template and Dockerfile changes are picked up without reinstalling.

---

## Code Style

The CLI script (`bin/connie`) must remain POSIX-compliant `sh`. No bashisms.
This ensures connie works on any system with a POSIX shell, including Alpine
Linux (which is what the container itself runs) and CI environments where bash
may not be the default.

Specific rules:

- Use `[ ]` not `[[ ]]`
- Use `$(cmd)` not `` `cmd` ``
- No `local` keyword — prefix private variables with `_` instead
- No bash arrays — use space-separated strings or newline-separated values
- Use `.` not `source`
- Syntax-check with: `sh -n bin/connie`
- `make check` runs the syntax check

---

## Project Structure

```text
connie/
├── Makefile                         Install / uninstall / syntax check
├── README.md                        User-facing documentation
├── DESIGN.md                        Architecture and design decisions
├── CONTRIBUTING.md                  This file
├── CHANGELOG.md                     Version history
├── bin/
│   └── connie                       The CLI script
└── lib/
    └── connie/
        ├── base.Dockerfile          Alpine + core tools + Claude Code
        ├── entrypoint.sh            Container startup script
        ├── docker-compose.yml       Hardened Compose base (shared, not per-project)
        ├── extend.Dockerfile        Build template (shared, not per-project)
        ├── templates/
        │   └── config.yml         Default project config template
        └── config/
            └── defaults.yml         Compiled-in defaults
```

---

## Making Changes

### Changes to `bin/connie`

1. Run `make check` (`sh -n bin/connie`) to catch syntax errors
2. Test `connie init` against a scratch project
3. Test `connie run` — verify the container starts and Claude Code launches
4. Test `connie clean` removes the project image
5. Verify all config layers work (defaults, user config, project config, flags)

### Changes to `lib/connie/base.Dockerfile`

The base Dockerfile defines what every connie container includes. Changes here
affect all projects on the next `connie build-base`. When making changes:

- Keep the image as small as possible — Alpine's value is its minimal footprint
- Add packages to the `apk add` block; do not add separate `RUN` layers
  unless there is a strong reason (each layer adds image size)
- Update `DESIGN.md` if the contents of the base image change
- Test with `connie build-base && connie run <some-project>`

### Changes to `docker-compose.yml` or `extend.Dockerfile`

These files live in `lib/connie/` and are read directly from `$LIB_DIR` at
runtime — they are not copied into projects. Changes take effect for all
projects immediately after reinstalling (no `connie init` re-run needed).

When making security-relevant changes to `docker-compose.yml`, update
`DESIGN.md` to reflect the new security posture.

### Changes to `config.yml` template

`lib/connie/templates/config.yml` is copied into new projects by `connie init`.
Changing it does not affect already-initialised projects — only new
`connie init` runs pick up the change.

### Changes to `defaults.yml`

Changing a default value is a potentially breaking change — it affects all
projects that rely on that default. Treat default changes with the same care
as a public API change and document them in `CHANGELOG.md`.

---

## Versioning

connie uses [Semantic Versioning](https://semver.org/):

- **Patch** — bug fixes, no behaviour changes
- **Minor** — new features, backward compatible
- **Major** — breaking changes to `config.yml` format or CLI interface

The version is defined in one place: the `VERSION` variable at the top of
`bin/connie`. Update it and add an entry to `CHANGELOG.md` with each release.

---

## Changelog

Maintain `CHANGELOG.md` in [Keep a Changelog](https://keepachangelog.com/)
format. Each entry should explain what changed and why, not just list the diff.
