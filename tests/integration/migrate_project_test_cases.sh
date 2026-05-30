# tests/integration/migrate_project_test_cases.sh
#
# Behavior specifications for _migrate_project — the function that
# converts a project from the old in-tree `.connie/` layout to the
# current XDG-directory layout. Invoked automatically by _prepare when
# it detects a `.connie/` directory and no XDG config for the project
# yet.
#
# Migration steps (per the function source):
#   1. Create the XDG config and state directories with 0700 perms on
#      the state hierarchy.
#   2. If $project/.connie/config.yml exists, move it to the XDG path;
#      otherwise create a fresh config from the installed template.
#   3. If $project/.connie/.claude/ exists, move it; otherwise create
#      an empty .claude/ directory with 0700 perms.
#   4. If $project/.connie/.claude.json exists, move it; otherwise
#      create an empty `{}` placeholder file.
#   5. Remove $project/.connie/override.yml if present (a legacy
#      artefact from before overrides were temp-file-only).
#   6. Try to rmdir the now-empty $project/.connie/. If the directory
#      contains unexpected files, leave it for the user to inspect.
#   7. Register the project in the registry under its computed slug.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Preconditions ──────────────────────────────────────────────────────────

a_legacy_project_with_a_dot_connie_config_yml() {
    project_path="$WORKSPACE/legacy-project"
    legacy_dot_connie="$project_path/.connie"
    mkdir -p "$legacy_dot_connie"
    legacy_config_content="# legacy project config — preserved across migration"
    printf '%s' "$legacy_config_content" > "$legacy_dot_connie/config.yml"
}

a_legacy_project_with_no_dot_connie_config_yml() {
    project_path="$WORKSPACE/legacy-project"
    legacy_dot_connie="$project_path/.connie"
    mkdir -p "$legacy_dot_connie"
}

a_legacy_dot_connie_with_a_populated_claude_directory() {
    a_legacy_project_with_no_dot_connie_config_yml
    mkdir -p "$legacy_dot_connie/.claude"
    legacy_session_content="session state from before migration"
    printf '%s' "$legacy_session_content" > "$legacy_dot_connie/.claude/session-marker"
}

a_legacy_dot_connie_with_a_claude_json_file() {
    a_legacy_project_with_no_dot_connie_config_yml
    legacy_claude_json_content='{"oauth_token": "legacy-token-value"}'
    printf '%s' "$legacy_claude_json_content" > "$legacy_dot_connie/.claude.json"
}

a_legacy_dot_connie_with_a_stale_override_yml() {
    a_legacy_project_with_no_dot_connie_config_yml
    printf 'services: {}\n' > "$legacy_dot_connie/override.yml"
}

a_legacy_dot_connie_with_an_unexpected_file() {
    a_legacy_project_with_no_dot_connie_config_yml
    printf 'mystery contents\n' > "$legacy_dot_connie/unexpected-file"
}

# ── Stimuli ────────────────────────────────────────────────────────────────

the_project_is_migrated() {
    _migrate_project "$project_path" 2>/dev/null
}

# ── Assertions ─────────────────────────────────────────────────────────────

the_new_config_file_was_created_at_the_xdg_path() {
    expect_file_to_exist "$(_project_config "$project_path")"
}

the_new_config_contains_the_legacy_content() {
    _actual=$(cat "$(_project_config "$project_path")")
    expect_equal "$legacy_config_content" "$_actual"
}

the_new_config_was_seeded_from_the_installed_template() {
    _expected=$(cat "$_HARNESS_REPO_ROOT/src/config/project.yml")
    _actual=$(cat "$(_project_config "$project_path")")
    expect_equal "$_expected" "$_actual"
}

the_state_directory_was_created() {
    expect_directory_to_exist "$(_project_state_dir "$project_path")"
}

the_claude_state_subdirectory_was_created() {
    expect_directory_to_exist "$(_project_state_dir "$project_path")/.claude"
}

the_claude_session_state_was_preserved_in_the_new_location() {
    expect_file_to_exist "$(_project_state_dir "$project_path")/.claude/session-marker"
    _actual=$(cat "$(_project_state_dir "$project_path")/.claude/session-marker")
    expect_equal "$legacy_session_content" "$_actual"
}

the_claude_json_file_was_preserved_in_the_new_location() {
    _actual=$(cat "$(_project_state_dir "$project_path")/.claude.json")
    expect_equal "$legacy_claude_json_content" "$_actual"
}

an_empty_claude_json_object_was_created_in_the_new_location() {
    _actual=$(cat "$(_project_state_dir "$project_path")/.claude.json")
    expect_equal "{}" "$_actual"
}

the_legacy_dot_connie_directory_was_removed() {
    if [ ! -d "$legacy_dot_connie" ]; then
        return 0
    fi
    _assertion_failure "directory removed" "$legacy_dot_connie absent" \
                       "actual" "$legacy_dot_connie still exists"
    return 1
}

the_legacy_dot_connie_directory_remains_with_the_unexpected_file() {
    expect_directory_to_exist "$legacy_dot_connie"
    expect_file_to_exist "$legacy_dot_connie/unexpected-file"
}

the_legacy_override_yml_was_removed() {
    if [ ! -e "$legacy_dot_connie/override.yml" ]; then
        return 0
    fi
    _assertion_failure "legacy override.yml removed" "absent" \
                       "actual" "still present at $legacy_dot_connie/override.yml"
    return 1
}

the_project_was_registered_in_the_registry() {
    _registry="$XDG_DATA_HOME/connie/projects.yml"
    expect_file_to_exist "$_registry"
    _slug=$(ROOT="$project_path" yq '.[env(ROOT)]' "$_registry")
    expect_not_equal "null" "$_slug"
}

# ── Test cases ─────────────────────────────────────────────────────────────

migrate_project_moves_an_existing_legacy_config_yml_to_the_xdg_path_test_case() {
    given a_legacy_project_with_a_dot_connie_config_yml
    when the_project_is_migrated
    expect the_new_config_file_was_created_at_the_xdg_path
    expect the_new_config_contains_the_legacy_content
}

migrate_project_seeds_a_fresh_config_from_the_template_when_no_legacy_config_existed_test_case() {
    given a_legacy_project_with_no_dot_connie_config_yml
    when the_project_is_migrated
    expect the_new_config_was_seeded_from_the_installed_template
}

migrate_project_creates_the_xdg_state_directory_test_case() {
    given a_legacy_project_with_no_dot_connie_config_yml
    when the_project_is_migrated
    expect the_state_directory_was_created
}

migrate_project_preserves_session_state_from_the_legacy_claude_directory_test_case() {
    given a_legacy_dot_connie_with_a_populated_claude_directory
    when the_project_is_migrated
    expect the_claude_session_state_was_preserved_in_the_new_location
}

migrate_project_creates_an_empty_claude_directory_when_no_legacy_one_existed_test_case() {
    given a_legacy_project_with_no_dot_connie_config_yml
    when the_project_is_migrated
    expect the_claude_state_subdirectory_was_created
}

migrate_project_preserves_an_existing_claude_json_file_test_case() {
    given a_legacy_dot_connie_with_a_claude_json_file
    when the_project_is_migrated
    expect the_claude_json_file_was_preserved_in_the_new_location
}

migrate_project_creates_an_empty_claude_json_when_no_legacy_one_existed_test_case() {
    given a_legacy_project_with_no_dot_connie_config_yml
    when the_project_is_migrated
    expect an_empty_claude_json_object_was_created_in_the_new_location
}

migrate_project_removes_an_empty_legacy_dot_connie_directory_test_case() {
    given a_legacy_project_with_no_dot_connie_config_yml
    when the_project_is_migrated
    expect the_legacy_dot_connie_directory_was_removed
}

migrate_project_removes_the_legacy_override_yml_artefact_test_case() {
    given a_legacy_dot_connie_with_a_stale_override_yml
    when the_project_is_migrated
    expect the_legacy_override_yml_was_removed
}

migrate_project_leaves_dot_connie_in_place_when_it_still_contains_unexpected_files_test_case() {
    given a_legacy_dot_connie_with_an_unexpected_file
    when the_project_is_migrated
    expect the_legacy_dot_connie_directory_remains_with_the_unexpected_file
}

migrate_project_registers_the_migrated_project_in_the_registry_test_case() {
    given a_legacy_project_with_no_dot_connie_config_yml
    when the_project_is_migrated
    expect the_project_was_registered_in_the_registry
}
