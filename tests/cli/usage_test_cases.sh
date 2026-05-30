# tests/cli/usage_test_cases.sh
#
# CLI-level tests for connie's help, version, and error-path behaviors.
# These exercise the binary as a subprocess and check exit code + output.
# No filesystem fixtures or Docker required.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Stimuli ───────────────────────────────────────────────────────────────

the_user_invokes_connie_with_no_arguments() {
    exercise_connie
}

the_user_invokes_connie_with_the_help_subcommand() {
    exercise_connie help
}

the_user_invokes_connie_with_the_version_subcommand() {
    exercise_connie version
}

the_user_invokes_connie_with_the_version_flag() {
    exercise_connie --version
}

the_user_invokes_connie_with_a_typoed_subcommand() {
    exercise_connie buld
}

the_user_invokes_connie_with_an_unknown_flag() {
    exercise_connie --unknown-flag
}

the_user_invokes_connie_with_package_but_no_value() {
    exercise_connie --package
}

the_user_invokes_connie_with_env_but_no_value() {
    exercise_connie --env
}

the_user_invokes_connie_with_cmd_but_no_value() {
    exercise_connie --cmd
}

the_user_invokes_connie_with_two_positional_arguments() {
    exercise_connie run /tmp/a /tmp/b
}

the_user_invokes_connie_init_with_a_nonexistent_directory() {
    exercise_connie init /nonexistent/directory/path
}

the_user_invokes_connie_clean_without_an_initialized_project() {
    exercise_connie clean "$WORKSPACE"
}

the_user_invokes_connie_config_without_an_initialized_project() {
    exercise_connie config "$WORKSPACE"
}

the_user_invokes_connie_context_without_an_initialized_project() {
    exercise_connie context "$WORKSPACE"
}

# ── Tests: no arguments ───────────────────────────────────────────────────

connie_succeeds_when_invoked_with_no_arguments_test_case() {
    when the_user_invokes_connie_with_no_arguments
    expect it_succeeds
}

connie_prints_usage_to_stdout_when_invoked_with_no_arguments_test_case() {
    when the_user_invokes_connie_with_no_arguments
    expect stdout_to_contain "^Usage:$"
}

# ── Tests: help subcommand ────────────────────────────────────────────────

connie_help_succeeds_test_case() {
    when the_user_invokes_connie_with_the_help_subcommand
    expect it_succeeds
}

connie_help_prints_usage_to_stdout_test_case() {
    when the_user_invokes_connie_with_the_help_subcommand
    expect stdout_to_contain "^Usage:$"
}

# ── Tests: version subcommand ─────────────────────────────────────────────

connie_version_subcommand_succeeds_test_case() {
    when the_user_invokes_connie_with_the_version_subcommand
    expect it_succeeds
}

connie_version_subcommand_prints_version_to_stdout_test_case() {
    when the_user_invokes_connie_with_the_version_subcommand
    expect stdout_to_contain "^connie [0-9]"
}

# ── Tests: --version flag ─────────────────────────────────────────────────

connie_version_flag_succeeds_test_case() {
    when the_user_invokes_connie_with_the_version_flag
    expect it_succeeds
}

connie_version_flag_prints_version_to_stdout_test_case() {
    when the_user_invokes_connie_with_the_version_flag
    expect stdout_to_contain "^connie [0-9]"
}

# ── Tests: typoed subcommand ──────────────────────────────────────────────

connie_rejects_typoed_subcommand_with_a_useful_error_test_case() {
    when the_user_invokes_connie_with_a_typoed_subcommand
    expect it_fails
    expect stderr_to_contain "Unknown command: buld"
}

# ── Tests: unknown flag ───────────────────────────────────────────────────

connie_rejects_unknown_flag_with_a_useful_error_test_case() {
    when the_user_invokes_connie_with_an_unknown_flag
    expect it_fails
    expect stderr_to_contain "Unknown flag: --unknown-flag"
}

# ── Tests: missing flag argument ──────────────────────────────────────────

connie_rejects_package_flag_with_no_value_test_case() {
    when the_user_invokes_connie_with_package_but_no_value
    expect it_fails
    expect stderr_to_contain "package requires an argument"
}

connie_rejects_env_flag_with_no_value_test_case() {
    when the_user_invokes_connie_with_env_but_no_value
    expect it_fails
    expect stderr_to_contain "env requires an argument"
}

connie_rejects_cmd_flag_with_no_value_test_case() {
    when the_user_invokes_connie_with_cmd_but_no_value
    expect it_fails
    expect stderr_to_contain "cmd requires an argument"
}

# ── Tests: duplicate positional argument ──────────────────────────────────

connie_rejects_duplicate_positional_argument_with_a_useful_error_test_case() {
    when the_user_invokes_connie_with_two_positional_arguments
    expect it_fails
    expect stderr_to_contain "Unexpected argument"
}

# ── Tests: nonexistent directory ──────────────────────────────────────────

connie_init_rejects_a_nonexistent_directory_test_case() {
    when the_user_invokes_connie_init_with_a_nonexistent_directory
    expect it_fails
    expect stderr_to_contain "Directory not found"
}

# ── Tests: commands that require an initialized project ───────────────────

connie_clean_rejects_an_uninitialized_project_test_case() {
    when the_user_invokes_connie_clean_without_an_initialized_project
    expect it_fails
    expect stderr_to_contain "No project config found"
}

connie_config_rejects_an_uninitialized_project_test_case() {
    when the_user_invokes_connie_config_without_an_initialized_project
    expect it_fails
    expect stderr_to_contain "No project config found"
}

connie_context_rejects_an_uninitialized_project_test_case() {
    when the_user_invokes_connie_context_without_an_initialized_project
    expect it_fails
    expect stderr_to_contain "No project config found"
}
