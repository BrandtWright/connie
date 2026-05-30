#!/bin/sh
# tests/harness.sh
#
# Minimal POSIX shell test harness for connie. ~140 lines, no external
# dependencies. Provides:
#
#   - Per-test subshell isolation (variables and cwd don't leak between tests)
#   - Per-test fake-home workspace (HOME, XDG_*) via mktemp -d so connie's
#     path-derived globals (CONFIG_DIR, STATE_DIR, etc.) point at a sandbox
#   - Given/when/then documentation helpers (`then_` and `and_` use a
#     trailing underscore because the unsuffixed forms are POSIX reserved)
#   - Assertion helpers that stop the test on first failure
#   - TAP-compatible output (`ok N - name` / `not ok N - name`) so the
#     output is parseable by external tools
#
# Usage:
#   . tests/harness.sh
#   _harness_run_file tests/unit/test_foo.sh
#   _harness_print_summary

# ── Parent-shell state (counters) ──────────────────────────────────────────

_harness_total=0
_harness_passed=0
_harness_failed=0

# ── Test discovery ─────────────────────────────────────────────────────────

# Print the names of all test_* functions defined in a file. Parses the file
# rather than relying on `set` or shell-specific introspection (which varies
# across POSIX sh implementations).
_harness_find_tests() {
    awk '/^test_[a-zA-Z0-9_]+[[:space:]]*\(\)[[:space:]]*\{/ {
        name = $1
        sub(/\(\)/, "", name)
        print name
    }' "$1"
}

# ── Per-test sandbox ───────────────────────────────────────────────────────

# Create a fresh fake-home directory and point HOME + XDG_* at it. connie's
# path-derived globals (CONFIG_DIR, STATE_DIR, DATA_DIR, etc.) are computed
# at sourcing time, so the harness must export these BEFORE sourcing connie.
_harness_setup_workspace() {
    WORKSPACE=$(mktemp -d 2>/dev/null) || {
        printf 'harness: mktemp -d failed\n' >&2
        exit 99
    }
    trap 'rm -rf "$WORKSPACE"' EXIT

    export HOME="$WORKSPACE/home"
    export XDG_CONFIG_HOME="$HOME/.config"
    export XDG_STATE_HOME="$HOME/.local/state"
    export XDG_DATA_HOME="$HOME/.local/share"
    export XDG_CONFIG_DIRS="$WORKSPACE/etc/xdg"

    mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" \
             "$XDG_DATA_HOME" "$XDG_CONFIG_DIRS"
}

# ── Test execution ─────────────────────────────────────────────────────────

# Run a single test by name. The test runs in a subshell so it can't pollute
# the harness's state. stderr from the subshell is captured and printed as
# TAP diagnostic lines on failure.
_harness_run_test() {
    _file="$1"
    _name="$2"

    _harness_total=$((_harness_total + 1))

    # `|| _status=$?` puts the subshell in a "handled" context so set -e in
    # the runner doesn't bail on a failing test — the harness needs to keep
    # going and record the failure.
    _status=0
    (
        _harness_setup_workspace
        # shellcheck source=/dev/null
        CONNIE_NO_DISPATCH=1 . "$_HARNESS_REPO_ROOT/src/connie"
        # shellcheck source=/dev/null
        . "$_file"
        "$_name"
    ) >"$_HARNESS_TMP/stdout" 2>"$_HARNESS_TMP/stderr" || _status=$?

    if [ "$_status" = "0" ]; then
        _harness_passed=$((_harness_passed + 1))
        printf 'ok %d - %s\n' "$_harness_total" "$_name"
    else
        _harness_failed=$((_harness_failed + 1))
        printf 'not ok %d - %s\n' "$_harness_total" "$_name"
        # Print captured diagnostic output indented as TAP YAML-ish comments
        if [ -s "$_HARNESS_TMP/stderr" ]; then
            sed 's/^/  # /' "$_HARNESS_TMP/stderr"
        fi
    fi
}

# Run every test in a file.
_harness_run_file() {
    _file="$1"
    _rel=${_file#"$_HARNESS_REPO_ROOT"/}
    printf '\n# %s\n' "$_rel"
    for _t in $(_harness_find_tests "$_file"); do
        _harness_run_test "$_file" "$_t"
    done
}

# ── Given / when / then (documentation helpers) ────────────────────────────
# These are no-ops behaviourally; they print to stderr so they appear in the
# captured diagnostic output when a test fails. `then_` and `and_` use a
# trailing underscore because `then` and `and` are POSIX reserved words.

given() { printf 'GIVEN: %s\n' "$*" >&2; }
when()  { printf ' WHEN: %s\n' "$*" >&2; }
then_() { printf ' THEN: %s\n' "$*" >&2; }
and_()  { printf '  AND: %s\n' "$*" >&2; }

# ── Assertion helpers ──────────────────────────────────────────────────────
# Each helper prints a diagnostic and exits the test subshell on failure.
# Stop-on-first-failure semantics keep per-test output focused.

_fail() {
    printf 'FAIL: %s\n' "$1" >&2
    shift
    for _line in "$@"; do
        printf '      %s\n' "$_line" >&2
    done
    exit 1
}

assert_equal() {
    [ "$1" = "$2" ] && return 0
    _fail "${3:-assert_equal}" "expected: '$1'" "actual:   '$2'"
}

assert_not_equal() {
    [ "$1" != "$2" ] && return 0
    _fail "${3:-assert_not_equal}" "both values are: '$1'"
}

assert_starts_with() {
    case "$1" in
        "$2"*) return 0 ;;
    esac
    _fail "${3:-assert_starts_with}" "expected prefix: '$2'" "actual value:    '$1'"
}

assert_ends_with() {
    case "$1" in
        *"$2") return 0 ;;
    esac
    _fail "${3:-assert_ends_with}" "expected suffix: '$2'" "actual value:    '$1'"
}

assert_contains() {
    case "$1" in
        *"$2"*) return 0 ;;
    esac
    _fail "${3:-assert_contains}" "expected to find: '$2'" "in value:         '$1'"
}

assert_matches() {
    printf '%s\n' "$1" | grep -E -q -- "$2" && return 0
    _fail "${3:-assert_matches}" "expected to match: '$2'" "actual value:      '$1'"
}

assert_empty() {
    [ -z "$1" ] && return 0
    _fail "${2:-assert_empty}" "expected empty" "actual: '$1'"
}

assert_not_empty() {
    [ -n "$1" ] && return 0
    _fail "${2:-assert_not_empty}" "expected non-empty"
}

assert_file_exists() {
    [ -f "$1" ] && return 0
    _fail "${2:-assert_file_exists}" "no file at: '$1'"
}

# ── Summary ────────────────────────────────────────────────────────────────

_harness_print_summary() {
    printf '\n# tests: %d, passed: %d, failed: %d\n' \
        "$_harness_total" "$_harness_passed" "$_harness_failed"
    [ "$_harness_failed" = "0" ]
}

# ── One-time harness setup ─────────────────────────────────────────────────

_HARNESS_TMP=$(mktemp -d) || exit 99
trap 'rm -rf "$_HARNESS_TMP"' EXIT
