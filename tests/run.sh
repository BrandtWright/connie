#!/bin/sh
# tests/run.sh
#
# Test runner. Discovers and runs every tests/{unit,integration,cli}/*.sh
# file through the harness.
#
# Flags:
#   --pretty   ANSI-coloured human-readable output (TAP is the default)
#   -v         Verbose: print the given/when/expect breadcrumbs for every
#              test (not just failures); preserve per-test artifact dirs
#              under $_HARNESS_TMP for post-mortem inspection
#   -f STR     Run only tests whose name contains STR (substring match)
#   PATH...    Explicit file/directory paths to run. If omitted, runs
#              every *.sh under tests/{unit,integration,cli}/.
#
# Docker-requiring tests live under tests/docker/ and have their own
# entry point — they need a host that can build images.

set -eu

_HARNESS_REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
export _HARNESS_REPO_ROOT

# shellcheck disable=SC1091 # harness.sh is sourced at runtime
. "$_HARNESS_REPO_ROOT/tests/harness.sh"

# ── Argument parsing ───────────────────────────────────────────────────────

_paths=""

while [ $# -gt 0 ]; do
    case "$1" in
        --pretty)
            _harness_mode=pretty
            shift
            ;;
        -v | --verbose)
            _harness_verbose=1
            shift
            ;;
        -f | --filter)
            [ $# -ge 2 ] || {
                printf 'error: -f requires a substring\n' >&2
                exit 2
            }
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

# ── Cleanup ─────────────────────────────────────────────────────────────────

if [ "$_harness_verbose" = "1" ]; then
    printf '# verbose: artifacts kept in %s\n' "$_HARNESS_TMP"
else
    trap 'rm -rf "$_HARNESS_TMP"' EXIT
fi

# ── Test execution ─────────────────────────────────────────────────────────

if [ "$_harness_mode" = "tap" ]; then
    printf 'TAP version 13\n'
fi

if [ -z "$_paths" ]; then
    # Default: discover everything except tests/docker/.
    for _dir in unit integration cli; do
        _full="$_HARNESS_REPO_ROOT/tests/$_dir"
        [ -d "$_full" ] || continue
        for _file in "$_full"/*.sh; do
            [ -f "$_file" ] || continue
            _harness_run_file "$_file"
        done
    done
else
    # User-supplied paths: each can be a directory or a file.
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
