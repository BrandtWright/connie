#!/bin/sh
# tests/harness.sh
#
# Test harness for connie. Inspired by the slipbox test architecture
# (https://github.com/...): tests are written as behavior specifications
# using a `given`/`when`/`expect` DSL where each step is a named function
# that the framework calls AND records. The function names themselves are
# the documentation; there are no description strings.
#
# Conventions documented in tests/README.md.
#
# Output: TAP version 13 by default. Pretty mode with --pretty.
#
# Per-test:
#   - subshell isolation (variables, cwd, set -e do not leak)
#   - fake-home workspace (HOME, XDG_*) in mktemp -d so connie's path-
#     derived globals resolve into a sandbox
#   - stdout/stderr captured to per-test files exposed via $TEST_STDOUT
#     and $TEST_STDERR (so assertions can read them without setting up
#     redirection themselves)
#   - given/when/expect breadcrumbs accumulated into a detail file that
#     is printed on failure (or always, with --verbose)
#
# Convention: ONE LOGICAL CLAIM PER TEST. Multiple `expect` lines are
# allowed when they describe inseparable aspects of the same claim. The
# harness does NOT exit after the first failed `expect`, so all failures
# in a single test are reported together.

# ── Parent-shell state ─────────────────────────────────────────────────────

_harness_total=0
_harness_passed=0
_harness_failed=0
_harness_failed_names=""
_harness_mode=tap  # tap | pretty
_harness_verbose=0 # 0 | 1
_harness_filter="" # substring match against test name

# ── Test discovery ─────────────────────────────────────────────────────────

# Parse a file for *_test_case() function definitions. Uses awk rather than
# shell introspection (which varies across POSIX implementations).
_harness_find_tests() {
    awk '/^[a-zA-Z_][a-zA-Z0-9_]*_test_case[[:space:]]*\(\)[[:space:]]*\{/ {
        name = $1
        sub(/\(\)/, "", name)
        print name
    }' "$1"
}

# ── Per-test sandbox setup ─────────────────────────────────────────────────

# Create a fresh fake-home and point HOME + XDG_* at it. connie's path-
# derived globals (CONFIG_DIR, STATE_DIR, etc.) are computed from these
# at sourcing time, so the harness must export them BEFORE sourcing connie.
_harness_setup_workspace() {
    # An explicit XXXXXX template is required for portability: BSD/macOS
    # mktemp rejects a bare `mktemp -d` (it wants a template or -t), whereas
    # GNU and busybox accept both. The template form works everywhere.
    #
    # Strip any trailing slash from the tmp base first: macOS sets $TMPDIR
    # with a trailing '/', so a naive "$TMPDIR/connie-ws.XXXXXX" yields a
    # '//' in WORKSPACE. connie normalizes that away in the paths it returns,
    # so tests that build an expected path by string-concatenating $WORKSPACE
    # would otherwise mismatch connie's normalized output.
    _ws_base="${TMPDIR:-/tmp}"
    WORKSPACE=$(mktemp -d "${_ws_base%/}/connie-ws.XXXXXX" 2>/dev/null) || {
        printf 'harness: mktemp -d failed\n' >&2
        exit 99
    }

    # Point CONNIE_LIB_DIR at the in-tree src/ so connie's path-derived
    # globals (LIB_DIR, DEFAULTS_FILE, PROJECT_TEMPLATE) resolve to the
    # repo's files rather than the system-installed paths. This matters
    # for unit tests that call internal functions directly (e.g.
    # _merge_configs, which reads $DEFAULTS_FILE). CLI tests don't strictly
    # need this — exercise_connie sets CONNIE_LIB_DIR explicitly when
    # invoking the subprocess — but exporting it here makes the env
    # uniform for both shapes of test.
    export CONNIE_LIB_DIR="$_HARNESS_REPO_ROOT/src"

    # Redirect the system-wide Claude Code policy path into the sandbox
    # so emit_user_context (and anything that calls it) reads from a
    # test-controlled location rather than /etc/claude-code/CLAUDE.md on
    # the host. Tests that need the file present create it at this path;
    # tests that need it absent leave it alone. Without this override the
    # suite would behave differently inside a connie container (where
    # /etc/ is populated) versus on a developer's host machine (where it
    # almost certainly isn't).
    export CONNIE_ETC_CLAUDE_MD="$WORKSPACE/system-claude.md"

    export HOME="$WORKSPACE/home"
    export XDG_CONFIG_HOME="$HOME/.config"
    export XDG_STATE_HOME="$HOME/.local/state"
    export XDG_DATA_HOME="$HOME/.local/share"
    export XDG_CONFIG_DIRS="$WORKSPACE/etc/xdg"

    mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" \
        "$XDG_DATA_HOME" "$XDG_CONFIG_DIRS"
}

# ── DSL: given / when / expect ─────────────────────────────────────────────
#
# Each takes a function name (and optional args) and calls it. They record
# the action in the test detail file for the harness to dump on failure
# (or with --verbose, on every test).
#
# `expect` does NOT exit on failure — it records the failure and lets the
# test continue. The test as a whole is reported as failed if any expect
# in it failed. This is the "one logical claim per test" convention: a
# claim may comprise multiple inseparable assertions, and we want to see
# ALL the assertion failures within that claim, not just the first.

_humanize() {
    # Replace underscores with spaces (POSIX: use tr, not bashism ${1//_/ }).
    # Strip a trailing " test case" suffix added by the underscore-to-space
    # conversion of the *_test_case naming convention.
    _hum_x=$(printf '%s' "$1" | tr '_' ' ')
    printf '%s' "${_hum_x% test case}"
}

# `given` and `when` set up state / perform the action under test. Unlike
# `expect`, their job is not to assert — but a step that exits non-zero
# means the precondition or stimulus itself failed, leaving the test
# running against stale or empty state. Left unchecked that produces a
# false green: the later `expect` lines pass against a half-built fixture.
# So a non-zero step is recorded as a test failure here, exactly as a
# failed `expect` would be. `set -e` is disabled inside the test subshell
# (it runs as the left operand of `||`), so we must check `$?` explicitly
# rather than rely on the shell aborting.
given() {
    _description=$(_humanize "$1")
    "$@"
    _step_status=$?
    if [ "$_step_status" = "0" ]; then
        _emit_detail "given:  $_description"
    else
        _TEST_ASSERTIONS_FAILED=$((_TEST_ASSERTIONS_FAILED + 1))
        _emit_detail "given:  $_description (FAIL: exit $_step_status)"
    fi
}

when() {
    _description=$(_humanize "$1")
    "$@"
    _step_status=$?
    if [ "$_step_status" = "0" ]; then
        _emit_detail "when:   $_description"
    else
        _TEST_ASSERTIONS_FAILED=$((_TEST_ASSERTIONS_FAILED + 1))
        _emit_detail "when:   $_description (FAIL: exit $_step_status)"
    fi
}

expect() {
    _description=$(_humanize "$1")
    "$@"
    _expect_status=$?
    if [ "$_expect_status" = "0" ]; then
        _emit_detail "expect: $_description (ok)"
    else
        _TEST_ASSERTIONS_FAILED=$((_TEST_ASSERTIONS_FAILED + 1))
        _emit_detail "expect: $_description (FAIL)"
    fi
}

_emit_detail() {
    printf '%s\n' "$1" >>"$TEST_DETAIL"
}

# ── Test execution ─────────────────────────────────────────────────────────

_harness_run_test() {
    _file="$1"
    _name="$2"

    # Apply filter (substring match against function name).
    if [ -n "$_harness_filter" ]; then
        case "$_name" in
            *"$_harness_filter"*) : ;;
            *) return 0 ;;
        esac
    fi

    _harness_total=$((_harness_total + 1))

    _artifact_dir=$(mktemp -d "$_HARNESS_TMP/${_name}.XXXXXX")
    _test_stdout="$_artifact_dir/stdout"
    _test_stderr="$_artifact_dir/stderr"
    _test_detail="$_artifact_dir/detail"
    : >"$_test_detail"

    _status=0
    (
        _harness_setup_workspace

        export TEST_STDOUT="$_test_stdout"
        export TEST_STDERR="$_test_stderr"
        export TEST_DETAIL="$_test_detail"
        export TEST_NAME="$_name"

        # Source connie's function definitions. The dispatch guard prevents
        # the CLI from firing.
        #
        # Per POSIX (and bash --posix), variable assignments before a
        # "special builtin" like `.` persist in the current shell AND get
        # exported — so `CONNIE_NO_DISPATCH=1 . connie` would leave
        # CONNIE_NO_DISPATCH=1 in the environment, which would propagate to
        # subsequent connie subprocess invocations in `exercise_connie`,
        # causing those subprocesses to silently skip `_main`. Set and
        # unset explicitly to keep the flag scoped to just the source step.
        CONNIE_NO_DISPATCH=1
        export CONNIE_NO_DISPATCH
        # shellcheck source=/dev/null
        . "$_HARNESS_REPO_ROOT/src/connie"
        unset CONNIE_NO_DISPATCH

        # Source all helper files. They define fixtures, stimuli, and
        # assertion primitives.
        for _h in "$_HARNESS_REPO_ROOT"/tests/helpers/*.sh; do
            [ -f "$_h" ] || continue
            # shellcheck source=/dev/null
            . "$_h"
        done

        # Source the test file (defines test_case functions plus any
        # test-specific fixtures/stimuli/assertions).
        # shellcheck source=/dev/null
        . "$_file"

        # Per-test failed-assertion counter (used by `expect`).
        _TEST_ASSERTIONS_FAILED=0

        # Run the test function.
        "$_name"

        # Exit non-zero if any expect inside this test failed.
        [ "$_TEST_ASSERTIONS_FAILED" = "0" ]
    ) >"$_artifact_dir/test_run_stdout" 2>"$_artifact_dir/test_run_stderr" ||
        _status=$?

    if [ "$_status" = "0" ]; then
        _harness_passed=$((_harness_passed + 1))
        _emit_pass "$_name" "$_test_detail"
    else
        _harness_failed=$((_harness_failed + 1))
        _harness_failed_names="$_harness_failed_names$_name
"
        _emit_fail "$_name" "$_test_detail" "$_artifact_dir/test_run_stderr"
    fi

    if [ "$_harness_verbose" = "0" ]; then
        rm -rf "$_artifact_dir"
    fi
}

_harness_run_file() {
    _file="$1"
    _rel=${_file#"$_HARNESS_REPO_ROOT/"}
    _count=$(_harness_find_tests "$_file" | wc -l | tr -d ' ')
    _emit_file_header "$_rel" "$_count"
    for _t in $(_harness_find_tests "$_file"); do
        _harness_run_test "$_file" "$_t"
    done
}

# ── Output: TAP vs pretty ──────────────────────────────────────────────────

_emit_file_header() {
    case "$_harness_mode" in
        tap)
            printf '\n# %s — %d test(s)\n' "$1" "$2"
            ;;
        pretty)
            _plural=s
            [ "$2" = "1" ] && _plural=""
            printf '\n\033[1m%s\033[0m (%d test%s)\n' "$1" "$2" "$_plural"
            ;;
    esac
}

_emit_pass() {
    _name="$1"
    _detail="$2"
    case "$_harness_mode" in
        tap)
            printf 'ok %d - %s\n' "$_harness_total" "$_name"
            if [ "$_harness_verbose" = "1" ] && [ -s "$_detail" ]; then
                _emit_yaml_block "$_detail" ""
            fi
            ;;
        pretty)
            printf '  \033[32m✓\033[0m %s\n' "$(_humanize "$_name")"
            if [ "$_harness_verbose" = "1" ] && [ -s "$_detail" ]; then
                sed 's/^/      /' "$_detail"
            fi
            ;;
    esac
}

_emit_fail() {
    _name="$1"
    _detail="$2"
    _stderr="$3"
    case "$_harness_mode" in
        tap)
            printf 'not ok %d - %s\n' "$_harness_total" "$_name"
            _emit_yaml_block "$_detail" "$_stderr"
            ;;
        pretty)
            printf '  \033[31m✗\033[0m %s\n' "$(_humanize "$_name")"
            [ -s "$_detail" ] && sed 's/^/      /' "$_detail"
            if [ -s "$_stderr" ]; then
                printf '      \033[33m--- stderr ---\033[0m\n'
                sed 's/^/      | /' "$_stderr"
            fi
            ;;
    esac
}

# Print test detail and (optional) stderr as a TAP-version-13 YAML block.
_emit_yaml_block() {
    _detail="$1"
    _stderr="${2:-}"
    printf '  ---\n'
    [ -s "$_detail" ] && sed 's/^/  /' "$_detail"
    if [ -n "$_stderr" ] && [ -s "$_stderr" ]; then
        printf '  stderr: |\n'
        sed 's/^/    /' "$_stderr"
    fi
    printf '  ...\n'
}

_harness_print_summary() {
    case "$_harness_mode" in
        tap)
            printf '\n# tests: %d, passed: %d, failed: %d\n' \
                "$_harness_total" "$_harness_passed" "$_harness_failed"
            if [ -n "$_harness_failed_names" ]; then
                printf '# failed:\n'
                printf '%s' "$_harness_failed_names" | while IFS= read -r _n; do
                    [ -n "$_n" ] && printf '#   - %s\n' "$_n"
                done
            fi
            ;;
        pretty)
            if [ "$_harness_failed" = "0" ]; then
                printf '\n\033[32m✔ %d test(s) passed\033[0m\n' \
                    "$_harness_total"
            else
                printf '\n\033[32m%d passed\033[0m · \033[31m%d failed\033[0m\n' \
                    "$_harness_passed" "$_harness_failed"
                printf '\nFailed:\n'
                printf '%s' "$_harness_failed_names" | while IFS= read -r _n; do
                    [ -n "$_n" ] && printf '  \033[31m✗\033[0m %s\n' \
                        "$(_humanize "$_n")"
                done
            fi
            ;;
    esac
    [ "$_harness_failed" = "0" ]
}

# ── One-time harness init ──────────────────────────────────────────────────

# Explicit template + trailing-slash strip for BSD/macOS portability
# (see _harness_setup_workspace).
_HARNESS_BASE="${TMPDIR:-/tmp}"
_HARNESS_TMP=$(mktemp -d "${_HARNESS_BASE%/}/connie-harness.XXXXXX") || exit 99
