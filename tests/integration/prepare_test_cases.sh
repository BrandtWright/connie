# tests/integration/prepare_test_cases.sh
#
# Behavior specifications for _prepare — the orchestration step that
# validates a project, auto-migrates a legacy .connie/ layout, ensures the
# base image exists, pre-creates the per-project Claude Code state on the
# host (with 0700 perms and a non-directory .claude.json), and writes the
# merged config for the caller. Previously this function was only exercised
# transitively through the Docker-gated layer; these tests cover it without
# a real Docker daemon by putting a stub `docker` on PATH that reports the
# base image as already present (so _prepare never tries to build).

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Preconditions ──────────────────────────────────────────────────────────

# Shadow docker with a shell function whose `image inspect` succeeds, so
# _prepare treats the base image as built and skips cmd_build_base. A
# function (resolved before PATH, no exec) is used because the harness
# sandbox lives under a noexec tmpdir where a stub script can't be exec'd.
a_stub_docker_with_the_base_image_present() {
    # shellcheck disable=SC2317 # invoked indirectly by connie via PATH shadowing
    docker() { return 0; }
}

an_initialized_project() {
    project_path="$WORKSPACE/project"
    mkdir -p "$project_path"
    exercise_connie init "$project_path" >/dev/null 2>&1
    prep_out="$WORKSPACE/merged.yml"
}

# A project that has never been initialized: no XDG config, no .connie/.
an_uninitialized_project() {
    project_path="$WORKSPACE/project"
    mkdir -p "$project_path"
    prep_out="$WORKSPACE/merged.yml"
}

# A project still on the legacy .connie/ layout with no XDG config — the
# state that should trigger auto-migration inside _prepare.
a_legacy_dot_connie_project() {
    project_path="$WORKSPACE/project"
    mkdir -p "$project_path/.connie"
    cp "$_HARNESS_REPO_ROOT/src/config/project.yml" \
        "$project_path/.connie/config.yml"
    prep_out="$WORKSPACE/merged.yml"
}

# Replace the pre-created .claude.json with known non-empty content so we can
# prove _prepare leaves an existing (authenticated) config untouched.
an_existing_non_empty_claude_json() {
    _json="$(_project_state_dir "$project_path")/.claude.json"
    printf '{"oauth":"keep-me"}' >"$_json"
}

# ── Stimuli ────────────────────────────────────────────────────────────────

the_project_is_prepared() {
    _prepare "$project_path" "$prep_out"
}

# _prepare calls _die (which exits) on an uninitialized project. Run it in a
# subshell so the exit becomes a captured status rather than aborting the
# test, and merge stderr so the message can be asserted.
prepare_is_attempted() {
    prep_stderr=$({ _prepare "$project_path" "$prep_out" >/dev/null; } 2>&1)
    prep_status=$?
}

# ── Assertions ─────────────────────────────────────────────────────────────

the_state_claude_dir_exists() {
    expect_directory_to_exist "$(_project_state_dir "$project_path")/.claude"
}

the_claude_json_is_a_nonempty_file() {
    _json="$(_project_state_dir "$project_path")/.claude.json"
    expect_file_to_exist "$_json"
    [ -s "$_json" ] || _assertion_failure ".claude.json to be non-empty" \
        "(content)" "size" "empty"
}

the_claude_json_contents_to_be() {
    _json="$(_project_state_dir "$project_path")/.claude.json"
    expect_equal "$1" "$(cat "$_json")"
}

the_state_dir_is_mode_700() {
    _dir=$(_project_state_dir "$project_path")
    if find "$_dir" -maxdepth 0 -type d -perm 700 2>/dev/null | grep -q .; then
        return 0
    fi
    _assertion_failure "state dir mode" "700" "mode was" "$(ls -ld "$_dir")"
}

the_merged_config_was_written() {
    expect_file_to_exist "$prep_out"
    expect_equal "4g" "$(yq '.resources.memory' "$prep_out")"
}

the_xdg_config_now_exists() {
    expect_file_to_exist "$(_project_config "$project_path")"
}

the_legacy_dot_connie_is_gone() {
    if [ ! -d "$project_path/.connie" ]; then
        return 0
    fi
    _assertion_failure "legacy .connie/ to be removed" "$project_path/.connie" \
        "status" "still present"
}

# ── Test cases ─────────────────────────────────────────────────────────────

prepare_creates_the_state_claude_directory_test_case() {
    given a_stub_docker_with_the_base_image_present
    given an_initialized_project
    when the_project_is_prepared
    expect the_state_claude_dir_exists
}

prepare_creates_a_nonempty_claude_json_test_case() {
    given a_stub_docker_with_the_base_image_present
    given an_initialized_project
    when the_project_is_prepared
    expect the_claude_json_is_a_nonempty_file
}

prepare_leaves_an_existing_claude_json_untouched_test_case() {
    given a_stub_docker_with_the_base_image_present
    given an_initialized_project
    given an_existing_non_empty_claude_json
    when the_project_is_prepared
    # The OAuth-bearing config must survive prepare — clobbering it would
    # log the user out on every run.
    expect the_claude_json_contents_to_be '{"oauth":"keep-me"}'
}

prepare_hardens_the_state_dir_to_mode_700_test_case() {
    given a_stub_docker_with_the_base_image_present
    given an_initialized_project
    when the_project_is_prepared
    expect the_state_dir_is_mode_700
}

prepare_writes_the_merged_config_to_the_output_path_test_case() {
    given a_stub_docker_with_the_base_image_present
    given an_initialized_project
    when the_project_is_prepared
    expect the_merged_config_was_written
}

prepare_dies_on_an_uninitialized_project_test_case() {
    given a_stub_docker_with_the_base_image_present
    given an_uninitialized_project
    when prepare_is_attempted
    expect expect_not_equal "0" "$prep_status"
    expect expect_contains "$prep_stderr" "No project config found"
}

prepare_auto_migrates_a_legacy_dot_connie_project_test_case() {
    given a_stub_docker_with_the_base_image_present
    given a_legacy_dot_connie_project
    when the_project_is_prepared
    # Inseparable claim: migration moved the config to XDG AND removed the
    # in-tree .connie/ directory.
    expect the_xdg_config_now_exists
    expect the_legacy_dot_connie_is_gone
}
