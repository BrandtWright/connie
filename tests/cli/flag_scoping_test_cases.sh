# tests/cli/flag_scoping_test_cases.sh
#
# CLI-level tests for per-subcommand flag scoping. connie parses every flag
# into a global regardless of subcommand (flags and the subcommand can appear
# in any order), then a post-parse pass rejects a flag the chosen subcommand
# does not accept — instead of silently ignoring it. Allowed sets mirror the
# "Options (...)" groups in `connie help`:
#   --package / --env / --cmd                  → run, build, config
#   --user                                     → edit-config, edit-context
#   --yes / --keep-state / --keep-image / ...  → remove

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Preconditions ──────────────────────────────────────────────────────────

an_initialized_project() {
    project_path="$WORKSPACE/project"
    mkdir -p "$project_path"
    exercise_connie init "$project_path" >/dev/null 2>&1
}

# ── Test cases: rejection ──────────────────────────────────────────────────

flag_scoping_rejects_a_build_flag_on_list_test_case() {
    when exercise_connie list --package vim
    expect it_fails
    expect stderr_to_contain "does not accept --package"
}

flag_scoping_rejects_a_remove_flag_on_config_test_case() {
    # The flag is rejected before dispatch even on an otherwise-valid command.
    given an_initialized_project
    when exercise_connie config "$project_path" --yes
    expect it_fails
    expect stderr_to_contain "does not accept --yes"
}

flag_scoping_rejects_the_user_flag_on_init_test_case() {
    when exercise_connie init "$WORKSPACE/anywhere" --user
    expect it_fails
    expect stderr_to_contain "does not accept --user"
}

flag_scoping_rejects_a_flag_given_without_a_subcommand_test_case() {
    when exercise_connie --package vim
    expect it_fails
    expect stderr_to_contain "does not accept --package"
}

# ── Test cases: acceptance ─────────────────────────────────────────────────

flag_scoping_accepts_a_build_flag_on_config_test_case() {
    given an_initialized_project
    when exercise_connie config "$project_path" --package vim
    expect it_succeeds
    # The package reaches the generated override's build arg.
    expect stdout_to_contain "vim"
}

flag_scoping_accepts_a_remove_flag_on_remove_test_case() {
    given an_initialized_project
    # --dry-run exercises the remove allow-set (shared by --yes/--keep-*)
    # without touching anything.
    when exercise_connie remove "$project_path" --dry-run
    expect it_succeeds
}
