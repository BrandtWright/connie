# tests/helpers/preconditions.sh
#
# Shared fixtures, stimuli, and assertion primitives for connie's test
# suite. Sourced by the harness inside each test's subshell, after connie's
# function definitions but before the test file.
#
# Convention (per tests/README.md):
#   - Preconditions (fixtures): a_*, an_*    e.g. an_existing_project_config
#   - Stimuli (actions):        the_user_*    e.g. the_user_runs_connie_init
#   - Assertions:               it_*, expect_  e.g. it_succeeds, expect_match
#
# Test-file-specific helpers may live in the test file itself.

# ── Formatting helper for assertion failures ───────────────────────────────
#
# Every named assertion that fails should call this so the failure detail
# in the test breadcrumbs is consistent.

# Append a structured "expected vs actual" block to the test detail file.
# Used by every named assertion that fails. Each `*_label` is the brief
# noun phrase that follows the literal "expected:" / "actual:" prefix.
_assertion_failure() {
    _expected_label="$1"
    _expected_value="$2"
    _actual_label="$3"
    _actual_value="$4"
    {
        printf 'expected: %s\n' "$_expected_label"
        printf '%s\n' "$_expected_value" | sed 's/^/  /'
        printf 'actual:   %s\n' "$_actual_label"
        printf '%s\n' "$_actual_value" | sed 's/^/  /'
    } >> "$TEST_DETAIL"
    return 1
}

# ── Assertion primitives ───────────────────────────────────────────────────
#
# These are low-level building blocks. Named assertions in test files (or
# below) wrap these to produce sentence-like names.

expect_equal() {
    [ "$1" = "$2" ] && return 0
    _assertion_failure "value to equal" "$1" "value was" "$2"
}

expect_not_equal() {
    [ "$1" != "$2" ] && return 0
    _assertion_failure "values to differ" "$1" "values were" "$2"
}

expect_match() {
    printf '%s\n' "$1" | grep -E -q -- "$2" && return 0
    _assertion_failure "value to match pattern" "$2" "value was" "$1"
}

expect_starts_with() {
    case "$1" in
        "$2"*) return 0 ;;
    esac
    _assertion_failure "value to start with" "$2" "value was" "$1"
}

expect_contains() {
    case "$1" in
        *"$2"*) return 0 ;;
    esac
    _assertion_failure "value to contain" "$2" "value was" "$1"
}

expect_empty() {
    [ -z "$1" ] && return 0
    _assertion_failure "value to be empty" "(empty)" "value was" "$1"
}

expect_not_empty() {
    [ -n "$1" ] && return 0
    _assertion_failure "value to be non-empty" "(any)" "value was" "(empty)"
}

expect_file_to_exist() {
    [ -f "$1" ] && return 0
    _assertion_failure "file to exist" "$1" "file status" "no such file"
}

expect_directory_to_exist() {
    [ -d "$1" ] && return 0
    _assertion_failure "directory to exist" "$1" "directory status" "no such directory"
}

# Compare a value against a stored snapshot under tests/snapshots/<name>.
# Use this for assertions over multi-line outputs (markdown blobs, YAML
# templates, etc.) where line-by-line assertions would be noisier than
# a single golden-file comparison.
#
# On mismatch, prints a unified diff (snapshot first, actual second) so
# the failure detail makes it obvious what changed. To accept the current
# output as the new snapshot (e.g. after an intentional change), re-run
# the suite with UPDATE_SNAPSHOTS=1.
expect_to_match_snapshot() {
    _snapshot_name="$1"
    _actual_value="$2"
    _snapshot="$_HARNESS_REPO_ROOT/tests/snapshots/$_snapshot_name"

    if [ "${UPDATE_SNAPSHOTS:-0}" = "1" ]; then
        mkdir -p "$(dirname "$_snapshot")"
        printf '%s' "$_actual_value" > "$_snapshot"
        return 0
    fi

    if [ ! -f "$_snapshot" ]; then
        _assertion_failure \
            "snapshot to exist at" "$_snapshot" \
            "snapshot status" "missing (run UPDATE_SNAPSHOTS=1 make test to create)"
        return 1
    fi

    _actual_tmp=$(mktemp)
    printf '%s' "$_actual_value" > "$_actual_tmp"
    if diff -q "$_snapshot" "$_actual_tmp" >/dev/null 2>&1; then
        rm -f "$_actual_tmp"
        return 0
    fi
    _diff_output=$(diff -u "$_snapshot" "$_actual_tmp" 2>&1 || true)
    rm -f "$_actual_tmp"
    _assertion_failure \
        "value to match snapshot" "$_snapshot_name" \
        "diff (- = snapshot / + = actual)" "$_diff_output"
}

# ── Process-level assertions (require exercise_connie / actual_exit_status) ─

it_succeeds() {
    [ "${actual_exit_status:-1}" = "0" ] && return 0
    _assertion_failure "exit status to be" "0" \
                       "exit status was" "${actual_exit_status:-unset}"
}

it_fails() {
    [ "${actual_exit_status:-0}" != "0" ] && return 0
    _assertion_failure "exit status to be" "non-zero" \
                       "exit status was" "${actual_exit_status:-unset}"
}

it_logs_to_stderr() {
    _expected="$1"
    _actual=$(cat -- "$TEST_STDERR")
    [ "$_actual" = "$_expected" ] && return 0
    _assertion_failure "stderr to be" "$_expected" "stderr was" "$_actual"
}

it_logs_to_stdout() {
    _expected="$1"
    _actual=$(cat -- "$TEST_STDOUT")
    [ "$_actual" = "$_expected" ] && return 0
    _assertion_failure "stdout to be" "$_expected" "stdout was" "$_actual"
}

stderr_to_contain() {
    _pattern="$1"
    grep -E -q -- "$_pattern" "$TEST_STDERR" && return 0
    _assertion_failure "stderr to match pattern" "$_pattern" \
                       "stderr was" "$(cat "$TEST_STDERR")"
}

stdout_to_contain() {
    _pattern="$1"
    grep -E -q -- "$_pattern" "$TEST_STDOUT" && return 0
    _assertion_failure "stdout to match pattern" "$_pattern" \
                       "stdout was" "$(cat "$TEST_STDOUT")"
}

# ── Stimuli: running connie ────────────────────────────────────────────────

# Invoke connie as a subprocess with stdout and stderr captured to the
# per-test files. Sets `actual_exit_status` for assertions to read.
exercise_connie() {
    CONNIE_LIB_DIR="$_HARNESS_REPO_ROOT/src" \
        "$_HARNESS_REPO_ROOT/src/connie" "$@" \
        >"$TEST_STDOUT" 2>"$TEST_STDERR"
    actual_exit_status=$?
}
