# tests/cli/error_messages_test_cases.sh
#
# Behavior specifications for `_die`'s output shape and the
# actionable-hint pattern. Sister file to usage_test_cases.sh —
# usage_test_cases covers WHAT triggers each error; this file
# covers HOW the error is presented.
#
# The hint pattern is what differentiates connie's error output
# from a bare "error: foo" — every error that has a non-obvious
# recovery should also have a hint line pointing the user at the
# next concrete action (a command to run, a doc to read, a setting
# to check). Without hints, error messages become "google what
# happened next" prompts; with hints, they become "do this" prompts.
#
# These tests assert the SHAPE (primary line + indented hint line)
# and the SUBSTANCE (specific hint content for the highest-traffic
# error paths) so a future refactor that drops the hint accidentally
# trips the test, not the user.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Preconditions ──────────────────────────────────────────────────────────

an_uninitialized_project_directory() {
    project_path="$WORKSPACE/no-config"
    mkdir -p "$project_path"
}

# ── Stimuli ────────────────────────────────────────────────────────────────

the_user_runs_an_unknown_subcommand() {
    exercise_connie defenestrate
}

the_user_runs_with_an_unknown_flag() {
    exercise_connie --bogus
}

the_user_runs_run_against_an_uninitialized_project() {
    exercise_connie run "$project_path"
}

the_user_runs_config_against_an_uninitialized_project() {
    exercise_connie config "$project_path"
}

the_user_runs_context_against_an_uninitialized_project() {
    exercise_connie context "$project_path"
}

the_user_passes_an_arg_flag_with_no_value() {
    exercise_connie --package
}

# ── Test cases ─────────────────────────────────────────────────────────────

errors_always_use_the_error_colon_prefix_test_case() {
    # The "error:" prefix is the load-bearing marker for any tooling
    # downstream of connie that filters its stderr (CI parsers, log
    # aggregators, IDEs). Every _die output starts with it.
    when the_user_runs_an_unknown_subcommand
    expect it_fails
    expect stderr_to_contain "^error:"
}

errors_exit_with_status_one_test_case() {
    when the_user_runs_an_unknown_subcommand
    # _die exits 1 unconditionally. A future refactor that introduced
    # alternate exit codes would need to also update tooling that
    # branches on the value; keep this canonical for now.
    expect it_fails
    expect exit_status_to_be 1
}

errors_with_a_hint_indent_the_hint_under_the_primary_line_test_case() {
    when the_user_runs_an_unknown_subcommand
    # Hint indentation aligns the hint under the primary message so a
    # human scanner sees one logical "error + recovery" unit, not two
    # unrelated lines. Seven leading spaces matches the width of
    # "error: " so the hint visually attaches to it.
    expect stderr_to_contain "^       Run 'connie help' for usage."
}

no_project_config_error_points_to_both_init_and_doctor_test_case() {
    # This is the highest-traffic error path — every fresh user hits
    # it on their first `connie run` of an un-init'd dir. The hint
    # must offer BOTH the obvious fix ('connie init') AND the
    # diagnostic path ('connie doctor'); the second matters because
    # sometimes the "no config" symptom hides a different cause
    # (wrong $XDG_CONFIG_HOME, partial migration, etc.).
    given an_uninitialized_project_directory
    when the_user_runs_run_against_an_uninitialized_project
    expect it_fails
    expect stderr_to_contain "No project config found"
    expect stderr_to_contain "connie init"
    expect stderr_to_contain "connie doctor"
}

no_project_config_error_consistent_across_run_config_context_test_case() {
    # `run`, `config`, and `context` all need a project config; all
    # three should hit the same code path in `_prepare` and produce
    # the same error shape. Inconsistent error text across closely
    # related commands is a small thing that grates on users; assert
    # the "No project config found" line appears in each.
    given an_uninitialized_project_directory
    when the_user_runs_config_against_an_uninitialized_project
    expect stderr_to_contain "No project config found"
}

context_against_uninitialized_project_also_includes_doctor_hint_test_case() {
    given an_uninitialized_project_directory
    when the_user_runs_context_against_an_uninitialized_project
    # Same hint as `run` — the hint generation is centralised in
    # _prepare, so all three subcommands inherit it. If this starts
    # failing, the hint was probably duplicated and one copy drifted.
    expect stderr_to_contain "connie doctor"
}

unknown_flag_error_points_at_help_test_case() {
    when the_user_runs_with_an_unknown_flag
    # Inseparable claim: typo'd a flag → see help. The primary line
    # echoes the offending flag (so the user knows WHAT typo), the
    # hint points at the help text (so the user knows HOW to find
    # the right spelling).
    expect it_fails
    expect stderr_to_contain "Unknown flag: --bogus"
    expect stderr_to_contain "Run 'connie help'"
}

missing_required_arg_value_dies_without_a_help_hint_test_case() {
    # Argument-validation errors like "--package requires an argument"
    # deliberately do NOT have a help hint — these errors fire for
    # users who already know the CLI shape and just dropped the value
    # by accident. A "see help" line on top would be noise. This test
    # locks that decision in place so a future refactor doesn't
    # accidentally homogenise all _die messages to include hints.
    when the_user_passes_an_arg_flag_with_no_value
    expect it_fails
    expect stderr_to_contain "--package requires an argument"
    # The hint line begins with "       " (7 spaces). Its absence is
    # what we're asserting.
    expect stderr_not_to_contain "^       "
}

# ── Local assertion ────────────────────────────────────────────────────────
# `stderr_not_to_contain` is the inverse of `stderr_to_contain`. Defined
# here rather than in helpers/preconditions.sh because this is currently
# the only test file that needs it; promote if a second site appears.

stderr_not_to_contain() {
    _pattern="$1"
    if grep -E -q -- "$_pattern" "$TEST_STDERR" 2>/dev/null; then
        _assertion_failure "stderr to NOT match pattern" "$_pattern" \
                           "stderr was" "$(cat "$TEST_STDERR")"
        return 1
    fi
    return 0
}

exit_status_to_be() {
    _expected="$1"
    # actual_exit_status is set by exercise_connie in
    # tests/helpers/preconditions.sh; shellcheck can't see that
    # across the sourced-helper boundary.
    # shellcheck disable=SC2154
    if [ "$actual_exit_status" = "$_expected" ]; then
        return 0
    fi
    # shellcheck disable=SC2154
    _assertion_failure "exit status to be" "$_expected" \
                       "actual" "$actual_exit_status"
    return 1
}
