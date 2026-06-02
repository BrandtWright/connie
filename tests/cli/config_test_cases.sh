# tests/cli/config_test_cases.sh
#
# CLI-level tests for `connie config` against an initialized project.
# Complements the existing error-path test (config_rejects_an_uninitialized
# _project) in tests/cli/usage_test_cases.sh.
#
# `connie config` reads the merged project config, generates the Compose
# override that `connie run` would use, and writes it to stdout for the
# user to inspect. Diagnostic info (project path, config path, state
# path) goes to stderr above the YAML body.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Preconditions ──────────────────────────────────────────────────────────

an_initialized_project_in_the_workspace() {
    project_path="$WORKSPACE/project"
    mkdir -p "$project_path"
    exercise_connie init "$project_path" >/dev/null 2>&1
}

an_initialized_project_with_custom_packages_set_in_the_config() {
    an_initialized_project_in_the_workspace
    yq -i '.packages = ["vim", "htop"]' "$(_project_config "$project_path")"
}

# ── Stimuli ────────────────────────────────────────────────────────────────

the_user_runs_connie_config() {
    exercise_connie config "$project_path"
}

# ── Assertions ─────────────────────────────────────────────────────────────

the_stdout_is_parseable_yaml() {
    if yq eval-all 'null' "$TEST_STDOUT" >/dev/null 2>&1; then
        return 0
    fi
    _assertion_failure "valid YAML on stdout" "parseable by yq" \
        "yq error" "$(yq 'null' "$TEST_STDOUT" 2>&1)"
}

the_stdout_contains_a_workspace_service() {
    _actual=$(yq '.services.workspace | type' "$TEST_STDOUT")
    expect_equal "!!map" "$_actual"
}

the_stdout_at_path_to_be() {
    _path="$1"
    _expected="$2"
    _actual=$(yq "$_path" "$TEST_STDOUT")
    expect_equal "$_expected" "$_actual"
}

the_stderr_mentions_the_project_path() {
    stderr_to_contain "Project:.*$project_path"
}

the_stderr_mentions_the_config_path() {
    stderr_to_contain "Config:.*$(_project_config "$project_path")"
}

the_stderr_mentions_the_state_directory_path() {
    stderr_to_contain "State:.*$(_project_state_dir "$project_path")"
}

# ── Test cases ─────────────────────────────────────────────────────────────

connie_config_succeeds_against_an_initialized_project_test_case() {
    given an_initialized_project_in_the_workspace
    when the_user_runs_connie_config
    expect it_succeeds
}

connie_config_emits_parseable_yaml_on_stdout_test_case() {
    given an_initialized_project_in_the_workspace
    when the_user_runs_connie_config
    expect the_stdout_is_parseable_yaml
}

connie_config_emits_a_workspace_service_in_the_compose_override_test_case() {
    given an_initialized_project_in_the_workspace
    when the_user_runs_connie_config
    expect the_stdout_contains_a_workspace_service
}

connie_config_propagates_default_resource_limits_to_the_override_test_case() {
    given an_initialized_project_in_the_workspace
    when the_user_runs_connie_config
    expect the_stdout_at_path_to_be ".services.workspace.mem_limit" "4g"
    expect the_stdout_at_path_to_be ".services.workspace.cpus" "2.0"
    expect the_stdout_at_path_to_be ".services.workspace.pids_limit" "512"
}

connie_config_reflects_packages_from_the_project_config_in_the_build_arg_test_case() {
    given an_initialized_project_with_custom_packages_set_in_the_config
    when the_user_runs_connie_config
    expect the_stdout_at_path_to_be ".services.workspace.build.args.EXTRA_PACKAGES" "vim htop"
}

connie_config_prints_the_project_path_to_stderr_for_diagnostic_visibility_test_case() {
    given an_initialized_project_in_the_workspace
    when the_user_runs_connie_config
    expect the_stderr_mentions_the_project_path
}

connie_config_prints_the_config_path_to_stderr_for_diagnostic_visibility_test_case() {
    given an_initialized_project_in_the_workspace
    when the_user_runs_connie_config
    expect the_stderr_mentions_the_config_path
}

connie_config_prints_the_state_directory_path_to_stderr_for_diagnostic_visibility_test_case() {
    given an_initialized_project_in_the_workspace
    when the_user_runs_connie_config
    expect the_stderr_mentions_the_state_directory_path
}
