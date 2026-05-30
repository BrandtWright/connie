# tests/docker/migration_test_cases.sh
#
# End-to-end test for the auto-migration trigger inside the build/run
# pipeline. _migrate_project itself is exhaustively unit-tested under
# tests/integration/migrate_project_test_cases.sh — what this layer
# verifies is that `_prepare` (called by both cmd_build and cmd_run)
# actually detects a legacy `.connie/` layout and fires the migration
# BEFORE attempting to read the merged config. Without that trigger,
# every upgrading developer would hit "No project config found" on
# their next `connie run`.
#
# The migration moves config.yml, .claude/, and .claude.json into the
# XDG dirs (here redirected by the harness to $WORKSPACE/home/...), then
# `rmdir`s the now-empty `.connie/`. The build should proceed straight
# through to producing a workspace image without any user intervention.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Test cases ─────────────────────────────────────────────────────────────

build_auto_migrates_a_legacy_dot_connie_project_test_case() {
    given a_unique_test_base_image_tag_and_a_legacy_dot_connie_project
    when the_user_runs_connie_build_against_the_project
    # Three inseparable aspects of the same claim "the trigger fires
    # and the chain completes":
    #   1. the build itself didn't error out partway through
    #   2. the legacy config landed in the XDG location (proves the
    #      migration ran, not just that the build skipped it somehow)
    #   3. the in-tree `.connie/` is gone (proves migration completed
    #      its cleanup phase, not just the file moves)
    expect it_succeeds
    expect the_xdg_config_to_exist_for_the_project
    expect the_legacy_dot_connie_directory_to_be_removed
}
