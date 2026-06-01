# tests/cli/list_test_cases.sh
#
# CLI-level tests for `connie list`, which enumerates the workspaces
# recorded in the registry ($PROJECTS_FILE). It prints one absolute
# project path per line to stdout, sorted, and keeps stdout an empty
# pipe-safe list when nothing is registered (explaining that on stderr).
# The harness redirects XDG_DATA_HOME into a per-test sandbox, so
# preconditions can seed the registry via _register_project and the real
# binary reads it back through exercise_connie. No Docker required.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Preconditions ──────────────────────────────────────────────────────────

an_empty_registry() {
    # A registry file that exists but maps nothing — distinct from the
    # no-file case below, exercising the empty-`keys` branch of cmd_list.
    mkdir -p "$DATA_DIR"
    printf '{}' > "$PROJECTS_FILE"
}

no_registry_file() {
    # Default sandbox state: $DATA_DIR/projects.yml was never created.
    [ -f "$PROJECTS_FILE" ] && rm -f "$PROJECTS_FILE"
    return 0
}

a_registered_project() {
    project_path="$WORKSPACE/project"
    mkdir -p "$project_path"
    _register_project "$project_path" "$(_project_slug "$project_path")"
}

two_registered_projects_in_reverse_order() {
    # Register beta before alpha so a passing sorted-output assertion
    # proves cmd_list sorts rather than echoing insertion order.
    beta_path="$WORKSPACE/beta"
    alpha_path="$WORKSPACE/alpha"
    mkdir -p "$beta_path" "$alpha_path"
    _register_project "$beta_path" "$(_project_slug "$beta_path")"
    _register_project "$alpha_path" "$(_project_slug "$alpha_path")"
    # LC_ALL=C sort order: alpha before beta.
    expected_listing="$alpha_path
$beta_path"
}

# ── Stimuli ────────────────────────────────────────────────────────────────

the_user_lists_workspaces() {
    exercise_connie list
}

# ── Test cases ─────────────────────────────────────────────────────────────

connie_list_succeeds_with_an_empty_registry_test_case() {
    given an_empty_registry
    when the_user_lists_workspaces
    expect it_succeeds
}

connie_list_prints_nothing_to_stdout_with_an_empty_registry_test_case() {
    given an_empty_registry
    when the_user_lists_workspaces
    expect it_logs_to_stdout ""
}

connie_list_explains_the_empty_registry_on_stderr_test_case() {
    given an_empty_registry
    when the_user_lists_workspaces
    expect stderr_to_contain "No workspaces"
}

connie_list_succeeds_when_no_registry_file_exists_test_case() {
    given no_registry_file
    when the_user_lists_workspaces
    expect it_succeeds
    expect it_logs_to_stdout ""
}

connie_list_prints_a_registered_project_path_to_stdout_test_case() {
    given a_registered_project
    when the_user_lists_workspaces
    expect it_logs_to_stdout "$project_path"
}

connie_list_prints_all_registered_paths_sorted_test_case() {
    given two_registered_projects_in_reverse_order
    when the_user_lists_workspaces
    expect it_logs_to_stdout "$expected_listing"
}
