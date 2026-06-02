# tests/cli/remove_test_cases.sh
#
# Behavior specifications for `connie remove` — the inverse of
# `connie init`. Removes connie-owned state (image + network + state
# dir + config dir + registry entry) without touching the project
# directory itself.
#
# Confirmation contract: interactive y/N prompt by default; --yes
# skips it; in non-TTY contexts (no terminal on stdin), --yes is
# REQUIRED — otherwise connie dies with a clear hint rather than
# hang waiting for input that won't come.
#
# Granularity flags:
#   --keep-state   preserve OAuth + history under STATE_DIR/<slug>/
#   --keep-image   skip Docker image + network removal
#   --dry-run      print what would be removed, touch nothing
#
# Tests run against an init'd project in the fake-home sandbox
# unless otherwise noted. Docker is not on PATH in this harness, so
# the image-removal branch always hits the "skipping" fallback —
# behavior verified there.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Preconditions ──────────────────────────────────────────────────────────

a_fresh_initialized_project() {
    project_path="$WORKSPACE/project"
    mkdir -p "$project_path"
    exercise_connie init "$project_path" >/dev/null 2>&1
}

a_fresh_initialized_project_with_a_sentinel_file() {
    a_fresh_initialized_project
    # Drop a sentinel inside the project to assert it survives.
    # `connie remove` MUST NOT touch the project directory.
    printf 'do-not-delete-me' >"$project_path/SENTINEL"
}

an_uninitialized_target_directory() {
    project_path="$WORKSPACE/uninitialized"
    mkdir -p "$project_path"
}

# ── Stimuli ────────────────────────────────────────────────────────────────

the_user_runs_connie_remove_with_yes() {
    exercise_connie remove "$project_path" --yes
}

the_user_runs_connie_remove_dry_run() {
    exercise_connie remove "$project_path" --dry-run
}

the_user_runs_connie_remove_keep_state() {
    exercise_connie remove "$project_path" --yes --keep-state
}

the_user_runs_connie_remove_keep_image() {
    exercise_connie remove "$project_path" --yes --keep-image
}

# Bypass exercise_connie to redirect stdin from /dev/null so the
# `[ ! -t 0 ]` non-TTY check fires deterministically. With stdin
# inherited from a possibly-interactive harness, the test outcome
# would depend on how the user invoked `make test`.
the_user_runs_connie_remove_without_yes_in_non_tty() {
    "$_HARNESS_REPO_ROOT/src/connie" remove "$project_path" \
        >"$TEST_STDOUT" 2>"$TEST_STDERR" </dev/null
    # shellcheck disable=SC2034 # read by `it_fails` downstream
    actual_exit_status=$?
}

# ── Assertions ─────────────────────────────────────────────────────────────

the_state_dir_to_no_longer_exist() {
    _state_dir="$STATE_DIR/$(_project_slug "$project_path")"
    if [ ! -d "$_state_dir" ]; then
        return 0
    fi
    _assertion_failure "state dir to be absent" "$_state_dir" \
        "actual" "directory still present"
}

the_state_dir_to_still_exist() {
    _state_dir="$STATE_DIR/$(_project_slug "$project_path")"
    if [ -d "$_state_dir" ]; then
        return 0
    fi
    _assertion_failure "state dir to be present" "$_state_dir" \
        "actual" "no such directory"
}

the_config_dir_to_no_longer_exist() {
    _config_dir="$CONFIG_DIR/projects/$(_project_slug "$project_path")"
    if [ ! -d "$_config_dir" ]; then
        return 0
    fi
    _assertion_failure "config dir to be absent" "$_config_dir" \
        "actual" "directory still present"
}

the_registry_entry_to_be_absent() {
    _actual=$(ROOT="$project_path" yq '.[env(ROOT)] // "absent"' \
        "$PROJECTS_FILE" 2>/dev/null || printf 'absent')
    expect_equal "absent" "$_actual"
}

the_project_directory_to_be_untouched() {
    if [ -f "$project_path/SENTINEL" ] &&
        [ "$(cat "$project_path/SENTINEL")" = "do-not-delete-me" ]; then
        return 0
    fi
    _assertion_failure \
        "sentinel file to survive at" "$project_path/SENTINEL" \
        "actual" "missing or modified"
}

# ── Test cases ─────────────────────────────────────────────────────────────

remove_yes_removes_the_state_dir_test_case() {
    given a_fresh_initialized_project
    when the_user_runs_connie_remove_with_yes
    expect it_succeeds
    expect the_state_dir_to_no_longer_exist
}

remove_yes_removes_the_config_dir_test_case() {
    given a_fresh_initialized_project
    when the_user_runs_connie_remove_with_yes
    expect the_config_dir_to_no_longer_exist
}

remove_yes_removes_the_registry_entry_test_case() {
    given a_fresh_initialized_project
    when the_user_runs_connie_remove_with_yes
    expect the_registry_entry_to_be_absent
}

remove_never_touches_the_project_directory_test_case() {
    # Load-bearing claim: a `connie remove` must never delete project
    # files. The sentinel survives if and only if the project dir
    # itself is left alone end-to-end.
    given a_fresh_initialized_project_with_a_sentinel_file
    when the_user_runs_connie_remove_with_yes
    expect it_succeeds
    expect the_project_directory_to_be_untouched
}

remove_keep_state_preserves_the_state_dir_test_case() {
    # The "log out but I might come back" middle ground. Config and
    # registry go, OAuth + history stay so re-running `connie init`
    # against the same path lands the user with their Claude Code
    # session intact.
    given a_fresh_initialized_project
    when the_user_runs_connie_remove_keep_state
    expect it_succeeds
    expect the_state_dir_to_still_exist
    expect the_config_dir_to_no_longer_exist
}

remove_dry_run_does_not_modify_the_filesystem_test_case() {
    given a_fresh_initialized_project
    when the_user_runs_connie_remove_dry_run
    expect it_succeeds
    # Everything that would have been removed is still present.
    expect the_state_dir_to_still_exist
    _config_dir="$CONFIG_DIR/projects/$(_project_slug "$project_path")"
    expect_dir_to_exist "$_config_dir"
    expect_equal "$(_project_slug "$project_path")" \
        "$(ROOT="$project_path" yq '.[env(ROOT)]' "$PROJECTS_FILE")"
}

remove_dry_run_lists_every_asset_it_would_touch_test_case() {
    given a_fresh_initialized_project
    when the_user_runs_connie_remove_dry_run
    # The dry-run output is the same thing the confirmation prompt
    # would show, so this assertion locks down the user-visible
    # contract for both code paths simultaneously.
    expect stderr_to_contain "Docker image:"
    expect stderr_to_contain "Docker network:"
    expect stderr_to_contain "State dir:"
    expect stderr_to_contain "Config dir:"
    expect stderr_to_contain "Registry entry:"
    expect stderr_to_contain "dry run"
}

remove_without_yes_in_a_non_tty_context_dies_with_a_hint_test_case() {
    # The confirmation prompt would hang forever waiting for input
    # in a non-TTY context, so connie refuses instead. The error
    # mentions --yes so a user reading the message knows the fix.
    given a_fresh_initialized_project
    when the_user_runs_connie_remove_without_yes_in_non_tty
    expect it_fails
    expect stderr_to_contain "non-interactive"
    expect stderr_to_contain '\-\-yes'
    # State dir wasn't touched because we never got past the
    # confirmation check.
    expect the_state_dir_to_still_exist
}

remove_against_an_unregistered_project_succeeds_gracefully_test_case() {
    # No `connie init` was run for this path. There's nothing in the
    # state or config dirs, no registry entry. `connie remove` should
    # still succeed — calling it on a clean path is a no-op, not an
    # error. Matches the convention that `rm -f` doesn't fail on
    # absent files.
    given an_uninitialized_target_directory
    when the_user_runs_connie_remove_with_yes
    expect it_succeeds
}
