# tests/integration/init_test_cases.sh
#
# Filesystem-level tests for `connie init`. Verifies that init creates the
# project config from the template, sets up the per-project state
# directory with .claude/ and .claude.json pre-created (needed before the
# container starts because of the read-only root filesystem), registers
# the project in projects.yml, and treats config.yml as developer-owned
# (never overwriting it on re-init).
#
# These tests do not require Docker. `connie init` calls `docker image
# inspect` to decide whether to print a "base image will be built on
# first run" note, but the absence of docker just means the note prints —
# init still succeeds.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Preconditions ──────────────────────────────────────────────────────────

a_new_project_directory_in_the_workspace() {
    project_path="$WORKSPACE/project"
    mkdir -p "$project_path"
}

the_project_has_already_been_initialized_once() {
    exercise_connie init "$project_path"
}

the_config_file_has_been_edited_with_custom_content() {
    custom_config_content="# user-edited content that init should never overwrite"
    printf '%s\n' "$custom_config_content" >"$(_project_config "$project_path")"
}

# ── Stimuli ────────────────────────────────────────────────────────────────

the_user_initializes_the_project() {
    exercise_connie init "$project_path"
}

the_user_initializes_the_project_again() {
    exercise_connie init "$project_path"
}

# ── Assertions ─────────────────────────────────────────────────────────────

the_project_config_file_was_created() {
    expect_file_to_exist "$(_project_config "$project_path")"
}

the_project_config_matches_the_installed_template() {
    _expected=$(cat "$_HARNESS_REPO_ROOT/src/config/project.yml")
    _actual=$(cat "$(_project_config "$project_path")")
    expect_equal "$_expected" "$_actual"
}

the_per_project_state_directory_was_created() {
    expect_directory_to_exist "$(_project_state_dir "$project_path")"
}

the_claude_state_subdirectory_was_created() {
    expect_directory_to_exist "$(_project_state_dir "$project_path")/.claude"
}

the_claude_json_file_was_created_as_an_empty_object() {
    _claude_json="$(_project_state_dir "$project_path")/.claude.json"
    expect_file_to_exist "$_claude_json"
    expect_equal "{}" "$(cat "$_claude_json")"
}

the_project_was_added_to_the_registry() {
    _registry="$XDG_DATA_HOME/connie/projects.yml"
    expect_file_to_exist "$_registry"
    _slug=$(ROOT="$project_path" yq '.[env(ROOT)]' "$_registry")
    expect_not_equal "null" "$_slug"
}

the_custom_config_content_persisted() {
    _actual=$(cat "$(_project_config "$project_path")")
    expect_equal "$custom_config_content" "$_actual"
}

# ── Test cases ─────────────────────────────────────────────────────────────

init_succeeds_against_a_fresh_project_directory_test_case() {
    given a_new_project_directory_in_the_workspace
    when the_user_initializes_the_project
    expect it_succeeds
}

init_creates_the_project_config_from_the_installed_template_test_case() {
    given a_new_project_directory_in_the_workspace
    when the_user_initializes_the_project
    expect the_project_config_file_was_created
    expect the_project_config_matches_the_installed_template
}

init_creates_the_per_project_state_directory_test_case() {
    given a_new_project_directory_in_the_workspace
    when the_user_initializes_the_project
    expect the_per_project_state_directory_was_created
    expect the_claude_state_subdirectory_was_created
}

init_creates_an_empty_claude_json_file_test_case() {
    given a_new_project_directory_in_the_workspace
    when the_user_initializes_the_project
    expect the_claude_json_file_was_created_as_an_empty_object
}

init_registers_the_project_in_the_registry_test_case() {
    given a_new_project_directory_in_the_workspace
    when the_user_initializes_the_project
    expect the_project_was_added_to_the_registry
}

init_does_not_overwrite_a_user_edited_config_on_re_init_test_case() {
    given a_new_project_directory_in_the_workspace
    given the_project_has_already_been_initialized_once
    given the_config_file_has_been_edited_with_custom_content
    when the_user_initializes_the_project_again
    expect the_custom_config_content_persisted
}
