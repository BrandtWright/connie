# tests/integration/unregister_project_test_cases.sh
#
# Filesystem-level tests for _unregister_project. The function is the
# inverse of _register_project — removes the path→slug entry from
# $PROJECTS_FILE. Used by cmd_remove; documented as a no-op when the
# file or entry is absent so cmd_remove can call it unconditionally
# without checking first.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Preconditions ──────────────────────────────────────────────────────────

a_registry_with_two_projects() {
    project_a="$WORKSPACE/proj-a"
    project_b="$WORKSPACE/proj-b"
    mkdir -p "$project_a" "$project_b"
    _register_project "$project_a" "slug-a"
    _register_project "$project_b" "slug-b"
}

a_path_that_was_never_registered() {
    unregistered_path="$WORKSPACE/never-seen"
    mkdir -p "$unregistered_path"
}

# ── Stimuli ────────────────────────────────────────────────────────────────

the_first_project_is_unregistered() {
    _unregister_project "$project_a"
}

the_unregistered_path_is_unregistered() {
    _unregister_project "$unregistered_path"
}

# ── Test cases ─────────────────────────────────────────────────────────────

unregister_removes_the_entry_for_the_given_path_test_case() {
    given a_registry_with_two_projects
    when the_first_project_is_unregistered
    # After removal, looking up the path in the registry should
    # return null. Use yq to confirm the key is absent.
    _actual=$(ROOT="$project_a" yq '.[env(ROOT)] // "absent"' "$PROJECTS_FILE")
    expect_equal "absent" "$_actual"
}

unregister_preserves_other_entries_test_case() {
    given a_registry_with_two_projects
    when the_first_project_is_unregistered
    # Removing project_a must not touch project_b. Inseparable from
    # the claim above: any removal that wipes the whole file would
    # technically pass the first test but break this one.
    _actual=$(ROOT="$project_b" yq '.[env(ROOT)] // "absent"' "$PROJECTS_FILE")
    expect_equal "slug-b" "$_actual"
}

unregister_is_a_noop_when_the_path_was_never_registered_test_case() {
    given a_registry_with_two_projects
    given a_path_that_was_never_registered
    when the_unregistered_path_is_unregistered
    # No error, no change to the existing entries — the function is
    # safe to call unconditionally during cmd_remove against a
    # project that was never `connie init`-ed.
    expect_equal "slug-a" "$(ROOT="$project_a" yq '.[env(ROOT)] // "absent"' "$PROJECTS_FILE")"
    expect_equal "slug-b" "$(ROOT="$project_b" yq '.[env(ROOT)] // "absent"' "$PROJECTS_FILE")"
}

unregister_is_a_noop_when_the_projects_file_does_not_exist_test_case() {
    # No fixture creating $PROJECTS_FILE — the file is genuinely
    # absent. Calling _unregister_project should succeed silently
    # rather than error on the missing file.
    target_path="$WORKSPACE/orphan"
    mkdir -p "$target_path"
    when _unregister_project "$target_path"
    expect_equal "false" "$([ -f "$PROJECTS_FILE" ] && printf true || printf false)"
}
