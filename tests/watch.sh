#!/usr/bin/env sh
# tests/watch.sh
#
# Re-run the test suite on file change. Uses `entr` to watch every
# git-tracked file in the repo and re-runs tests/run.sh whenever any
# of them change. Any extra args are forwarded to run.sh, so you can
# do e.g. `tests/watch.sh --pretty -f slug`.
#
# Requires: git, entr.

set -eu

SCRIPT_DIR=$(cd "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

_require() {
    command -v "$1" >/dev/null 2>&1 || {
        printf "error: required command '%s' not found in PATH.\n" "$1" >&2
        exit 1
    }
}

cleanup() {
    printf '\033[?12h' # restore cursor blink
    printf '\033[?25h' # show cursor
}
trap cleanup EXIT INT TERM

_require git
_require entr

printf '\033[?25l' # hide cursor
printf '\033[?12l' # disable cursor blink

cd "$REPO_ROOT"
# shellcheck disable=SC2016 # the single quotes are intentional — sh -c receives
# the literal string and resolves $0/$@ from the args entr passes after it.
git ls-files | entr -r sh -c 'clear; "$0" "$@"' "$SCRIPT_DIR/run.sh" "$@"
