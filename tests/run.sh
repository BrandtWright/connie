#!/bin/sh
# tests/run.sh
# Test runner — discovers and runs every tests/{unit,integration,cli}/*.sh
# file through the harness, then prints a TAP-style summary.
set -eu

_HARNESS_REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
export _HARNESS_REPO_ROOT

# shellcheck disable=SC1091 # harness.sh is sourced at runtime, not lint time
. "$_HARNESS_REPO_ROOT/tests/harness.sh"

printf 'TAP version 13\n'

for _dir in unit integration cli; do
    _path="$_HARNESS_REPO_ROOT/tests/$_dir"
    [ -d "$_path" ] || continue
    for _file in "$_path"/*.sh; do
        [ -f "$_file" ] || continue
        _harness_run_file "$_file"
    done
done

_harness_print_summary
