#!/bin/sh
# tests/run-docker.sh
#
# Runs the Docker-gated test layer (tests/docker/*.sh). These tests
# exercise connie subcommands that actually build images and start
# containers, so they need a real Docker daemon. If docker is absent
# from $PATH or the daemon is unreachable, the runner exits 0 with a
# clear message — skipping is not a test failure.
#
# Flags mirror tests/run.sh: --pretty, -v, -f STR, optional paths.
#
# Tests use $CONNIE_BASE_IMAGE (set per-test by fixtures in
# tests/helpers/docker.sh) to write to a unique image tag rather than
# the production `connie/base:latest`. Even if a test fails partway
# through, the user's real base image is never touched.

set -eu

_HARNESS_REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
export _HARNESS_REPO_ROOT

# ── Skip-when-docker-absent ────────────────────────────────────────────────

if ! command -v docker >/dev/null 2>&1; then
    printf '\033[33m──\033[0m\n' >&2
    printf '\033[33m%s\033[0m\n' "docker not in PATH — skipping the Docker-gated test layer." >&2
    printf '%s\n' "These tests exercise 'connie build-base', 'connie build', etc., and" >&2
    printf '%s\n' "need a real Docker daemon. They live in tests/docker/." >&2
    printf '\033[33m──\033[0m\n' >&2
    exit 0
fi

if ! docker info >/dev/null 2>&1; then
    printf '\033[31m──\033[0m\n' >&2
    printf '\033[31m%s\033[0m\n' "docker is installed but the daemon is unreachable." >&2
    printf '%s\n' "Make sure dockerd is running and your user can reach it" >&2
    printf '%s\n' "(typically by being in the 'docker' group). Skipping Docker tests." >&2
    printf '\033[31m──\033[0m\n' >&2
    exit 1
fi

# shellcheck disable=SC1091 # harness.sh is sourced at runtime
. "$_HARNESS_REPO_ROOT/tests/harness.sh"

# ── Argument parsing (matches tests/run.sh) ────────────────────────────────

_paths=""

while [ $# -gt 0 ]; do
    case "$1" in
        --pretty)
            _harness_mode=pretty
            shift
            ;;
        -v|--verbose)
            _harness_verbose=1
            shift
            ;;
        -f|--filter)
            [ $# -ge 2 ] || { printf 'error: -f requires a substring\n' >&2; exit 2; }
            _harness_filter="$2"
            shift 2
            ;;
        --)
            shift
            while [ $# -gt 0 ]; do
                _paths="$_paths $1"
                shift
            done
            ;;
        -*)
            printf 'error: unknown flag: %s\n' "$1" >&2
            exit 2
            ;;
        *)
            _paths="$_paths $1"
            shift
            ;;
    esac
done

if [ "$_harness_verbose" = "1" ]; then
    printf '# verbose: artifacts kept in %s\n' "$_HARNESS_TMP"
else
    trap 'rm -rf "$_HARNESS_TMP"' EXIT
fi

if [ "$_harness_mode" = "tap" ]; then
    printf 'TAP version 13\n'
fi

# ── Test execution ─────────────────────────────────────────────────────────

if [ -z "$_paths" ]; then
    _full="$_HARNESS_REPO_ROOT/tests/docker"
    if [ ! -d "$_full" ]; then
        printf '# no tests/docker/ directory found — nothing to run\n'
        _harness_print_summary
        exit 0
    fi
    for _file in "$_full"/*.sh; do
        [ -f "$_file" ] || continue
        _harness_run_file "$_file"
    done
else
    for _p in $_paths; do
        if [ -d "$_p" ]; then
            for _file in "$_p"/*.sh; do
                [ -f "$_file" ] || continue
                _harness_run_file "$_file"
            done
        elif [ -f "$_p" ]; then
            _harness_run_file "$_p"
        else
            printf 'error: no such file or directory: %s\n' "$_p" >&2
            exit 2
        fi
    done
fi

_harness_print_summary
