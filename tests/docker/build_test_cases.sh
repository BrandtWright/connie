# tests/docker/build_test_cases.sh
#
# Behavior specifications for `connie build` — the subcommand that
# builds the per-project workspace image from src/docker/extend.Dockerfile
# on top of the connie base image. The build picks up
#
#   - the project's merged config (via _generate_override)
#   - any project packages (apk install via EXTRA_PACKAGES)
#   - any project build commands (BUILD_COMMANDS)
#
# connie's context is no longer baked into the image; it is appended to
# Claude's system prompt at run time (see run_test_cases.sh), so there is
# no /etc/claude-code/CLAUDE.md build artifact to assert here.
#
# Tests use the isolated CONNIE_BASE_IMAGE tag so they don't touch the
# user's `connie/base:latest`. The first test builds both base + workspace
# from scratch; the rest hit Docker's layer cache for both.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Test cases ─────────────────────────────────────────────────────────────

build_succeeds_against_an_initialized_project_test_case() {
    given a_unique_test_base_image_tag_and_an_initialized_project
    when the_user_runs_connie_build_against_the_project
    expect it_succeeds
}

build_produces_a_per_project_workspace_image_test_case() {
    given a_unique_test_base_image_tag_and_an_initialized_project
    when the_user_runs_connie_build_against_the_project
    expect the_workspace_image_exists
}

build_is_idempotent_when_the_workspace_image_already_exists_test_case() {
    given a_unique_test_base_image_tag_and_an_initialized_project
    given the_user_runs_connie_build_against_the_project
    # Image is now built. Re-running should hit the layer cache for
    # every step and succeed with the image still present at the
    # expected tag.
    when the_user_runs_connie_build_against_the_project
    expect it_succeeds
    expect the_workspace_image_exists
}

build_auto_builds_the_base_image_when_it_does_not_exist_yet_test_case() {
    # No prior build-base step — the fixture stages an isolated base
    # tag but doesn't build the image. cmd_build's _prepare detects
    # the missing base image and runs cmd_build_base before the
    # workspace build proceeds. Verifies the auto-build branch.
    given a_unique_test_base_image_tag_and_an_initialized_project
    when the_user_runs_connie_build_against_the_project
    expect it_succeeds
    expect the_image_exists
    expect the_workspace_image_exists
}
