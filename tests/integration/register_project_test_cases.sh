# tests/integration/register_project_test_cases.sh
#
# Filesystem-level tests for _register_project. The function records a
# project's absolute path → slug mapping in $PROJECTS_FILE
# (XDG_DATA_HOME/connie/projects.yml), creating the data directory and
# the JSON-empty-object initial file when they don't already exist. The
# yq -i update is what makes the entry idempotent: re-registering the
# same path replaces the slug rather than appending a duplicate.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Preconditions ──────────────────────────────────────────────────────────

an_unregistered_project_in_the_workspace() {
    project_path="$WORKSPACE/project"
    mkdir -p "$project_path"
    slug=$(_project_slug "$project_path")
}

a_second_unregistered_project_in_the_workspace() {
    second_project_path="$WORKSPACE/other-project"
    mkdir -p "$second_project_path"
    second_slug=$(_project_slug "$second_project_path")
}

a_pre_existing_registration_under_a_stale_slug() {
    _register_project "$project_path" "stale-slug-value"
}

# ── Stimuli ────────────────────────────────────────────────────────────────

the_project_is_registered() {
    _register_project "$project_path" "$slug"
}

the_project_is_re_registered_under_its_current_slug() {
    _register_project "$project_path" "$slug"
}

both_projects_are_registered_in_sequence() {
    _register_project "$project_path" "$slug"
    _register_project "$second_project_path" "$second_slug"
}

# ── Assertions ─────────────────────────────────────────────────────────────

the_data_directory_was_created() {
    expect_directory_to_exist "$DATA_DIR"
}

the_projects_file_was_created() {
    expect_file_to_exist "$PROJECTS_FILE"
}

the_registry_maps_the_project_path_to_its_slug() {
    _actual=$(ROOT="$project_path" yq '.[env(ROOT)]' "$PROJECTS_FILE")
    expect_equal "$slug" "$_actual"
}

the_registry_contains_both_projects() {
    _first=$(ROOT="$project_path" yq '.[env(ROOT)]' "$PROJECTS_FILE")
    _second=$(ROOT="$second_project_path" yq '.[env(ROOT)]' "$PROJECTS_FILE")
    expect_equal "$slug" "$_first"
    expect_equal "$second_slug" "$_second"
}

the_stale_slug_was_replaced_with_the_current_slug() {
    _actual=$(ROOT="$project_path" yq '.[env(ROOT)]' "$PROJECTS_FILE")
    expect_equal "$slug" "$_actual"
}

# ── Test cases ─────────────────────────────────────────────────────────────

register_project_creates_the_xdg_data_directory_when_missing_test_case() {
    given an_unregistered_project_in_the_workspace
    when the_project_is_registered
    expect the_data_directory_was_created
}

register_project_creates_the_projects_file_when_missing_test_case() {
    given an_unregistered_project_in_the_workspace
    when the_project_is_registered
    expect the_projects_file_was_created
}

register_project_records_the_path_to_slug_mapping_test_case() {
    given an_unregistered_project_in_the_workspace
    when the_project_is_registered
    expect the_registry_maps_the_project_path_to_its_slug
}

register_project_preserves_earlier_entries_when_adding_a_new_one_test_case() {
    given an_unregistered_project_in_the_workspace
    given a_second_unregistered_project_in_the_workspace
    when both_projects_are_registered_in_sequence
    expect the_registry_contains_both_projects
}

register_project_replaces_a_stale_slug_for_the_same_path_test_case() {
    given an_unregistered_project_in_the_workspace
    given a_pre_existing_registration_under_a_stale_slug
    when the_project_is_re_registered_under_its_current_slug
    expect the_stale_slug_was_replaced_with_the_current_slug
}
