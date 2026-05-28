# TODO

Ideas and planned features for future development. Items here are under
consideration — not committed to any release.

---

## Features

### SSH Agent Forwarding

Forward the host's `SSH_AUTH_SOCK` into the container so Claude Code can
perform authenticated git operations (clone, push, fetch) without embedding
credentials in the image.

Planned approach: a `ssh:` config key in `.containerrc` that opts in to the
mount. The socket path is taken from `$SSH_AUTH_SOCK` on the host.

### `connie init --update`

Refresh the tool-managed files (`docker-compose.yml`, `extend.Dockerfile`)
from the current installed templates without overwriting `.containerrc`.

Useful after a `connie` upgrade that ships improved templates.

### Multiple Containers Per Project

Allow `.containerrc` to define a `services:` key describing a multi-container
stack (e.g. app + database). The current config structure was designed to
accommodate this without breaking changes.

### Registry Publishing

Support pushing the base image to a private registry so teams can share a
single built base rather than each developer building it locally.

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
