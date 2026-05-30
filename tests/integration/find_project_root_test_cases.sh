# tests/integration/find_project_root_test_cases.sh
#
# Filesystem-level tests for _find_project_root. The function takes a
# directory (defaulting to $PWD), resolves it to an absolute path via
# `cd && pwd`, then:
#
#   1. If $PROJECTS_FILE exists, walks UP the directory tree from the
#      resolved path looking for an entry whose key matches one of the
#      ancestors. Returns the first match found.
#
#   2. Otherwise, walks UP looking for an old-style .connie/ directory.
#      Returns that ancestor (used as the migration trigger by _prepare).
#
#   3. Otherwise, returns the resolved input directory unchanged. The
#      caller is expected to handle the "no project found" case (e.g.
#      cmd_config dies with "No project config found").

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Preconditions ──────────────────────────────────────────────────────────

a_registered_project_in_the_workspace() {
    project_path="$WORKSPACE/project"
    mkdir -p "$project_path"
    _register_project "$project_path" "$(_project_slug "$project_path")"
}

a_deeply_nested_subdirectory_of_a_registered_project() {
    a_registered_project_in_the_workspace
    nested_subdirectory="$project_path/src/nested/deep"
    mkdir -p "$nested_subdirectory"
}

an_unregistered_directory_in_the_workspace() {
    unregistered_path="$WORKSPACE/not-a-project"
    mkdir -p "$unregistered_path"
}

an_unregistered_directory_when_other_projects_are_already_registered() {
    a_registered_project_in_the_workspace
    unregistered_path="$WORKSPACE/something-else"
    mkdir -p "$unregistered_path"
}

a_legacy_project_with_a_dot_connie_directory() {
    legacy_path="$WORKSPACE/legacy-project"
    mkdir -p "$legacy_path/.connie"
}

a_subdirectory_of_a_legacy_project() {
    a_legacy_project_with_a_dot_connie_directory
    legacy_subdirectory="$legacy_path/src"
    mkdir -p "$legacy_subdirectory"
}

a_registered_project_reachable_via_a_relative_path() {
    a_registered_project_in_the_workspace
    cd "$WORKSPACE" || return 1
    relative_input_path="project"
}

# ── Stimuli ────────────────────────────────────────────────────────────────

the_project_root_is_resolved_for_the_project_directory_itself() {
    resolved=$(_find_project_root "$project_path")
}

the_project_root_is_resolved_from_the_nested_subdirectory() {
    resolved=$(_find_project_root "$nested_subdirectory")
}

the_project_root_is_resolved_for_the_unregistered_path() {
    resolved=$(_find_project_root "$unregistered_path")
}

the_project_root_is_resolved_for_the_legacy_project() {
    resolved=$(_find_project_root "$legacy_path")
}

the_project_root_is_resolved_from_the_legacy_subdirectory() {
    resolved=$(_find_project_root "$legacy_subdirectory")
}

the_project_root_is_resolved_for_the_relative_path() {
    resolved=$(_find_project_root "$relative_input_path")
}

# ── Assertions ─────────────────────────────────────────────────────────────

the_resolved_path_equals_the_project_path() {
    expect_equal "$project_path" "$resolved"
}

the_resolved_path_equals_the_unregistered_path() {
    expect_equal "$unregistered_path" "$resolved"
}

the_resolved_path_equals_the_legacy_project_path() {
    expect_equal "$legacy_path" "$resolved"
}

# ── Test cases ─────────────────────────────────────────────────────────────

find_project_root_returns_the_project_path_when_called_against_it_directly_test_case() {
    given a_registered_project_in_the_workspace
    when the_project_root_is_resolved_for_the_project_directory_itself
    expect the_resolved_path_equals_the_project_path
}

find_project_root_returns_the_registered_ancestor_from_a_nested_subdirectory_test_case() {
    given a_deeply_nested_subdirectory_of_a_registered_project
    when the_project_root_is_resolved_from_the_nested_subdirectory
    expect the_resolved_path_equals_the_project_path
}

find_project_root_returns_the_input_when_no_match_and_no_registry_exists_test_case() {
    given an_unregistered_directory_in_the_workspace
    when the_project_root_is_resolved_for_the_unregistered_path
    expect the_resolved_path_equals_the_unregistered_path
}

find_project_root_returns_the_input_when_no_match_in_a_populated_registry_test_case() {
    given an_unregistered_directory_when_other_projects_are_already_registered
    when the_project_root_is_resolved_for_the_unregistered_path
    expect the_resolved_path_equals_the_unregistered_path
}

find_project_root_falls_back_to_a_dot_connie_directory_for_legacy_projects_test_case() {
    given a_legacy_project_with_a_dot_connie_directory
    when the_project_root_is_resolved_for_the_legacy_project
    expect the_resolved_path_equals_the_legacy_project_path
}

find_project_root_walks_up_to_a_dot_connie_directory_from_a_subdirectory_test_case() {
    given a_subdirectory_of_a_legacy_project
    when the_project_root_is_resolved_from_the_legacy_subdirectory
    expect the_resolved_path_equals_the_legacy_project_path
}

find_project_root_resolves_relative_paths_to_absolute_paths_test_case() {
    given a_registered_project_reachable_via_a_relative_path
    when the_project_root_is_resolved_for_the_relative_path
    expect the_resolved_path_equals_the_project_path
}
