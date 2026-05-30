# tests/docker/build_test_cases.sh
#
# Behavior specifications for `connie build` — the subcommand that
# builds the per-project workspace image from src/docker/extend.Dockerfile
# on top of the connie base image. The build picks up
#
#   - the project's merged config (via _generate_override)
#   - the connie context content (via _generate_connie_context, embedded
#     in extend.Dockerfile's CONNIE_CONTEXT build arg, written to
#     /etc/claude-code/CLAUDE.md inside the image)
#   - any project packages (apk install via EXTRA_PACKAGES)
#   - any project build commands (BUILD_COMMANDS)
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

build_writes_the_connie_context_to_etc_claude_code_in_the_workspace_image_test_case() {
    given a_unique_test_base_image_tag_and_an_initialized_project
    when the_user_runs_connie_build_against_the_project
    # extend.Dockerfile receives the CONNIE_CONTEXT build arg from
    # _generate_override and writes it to /etc/claude-code/CLAUDE.md
    # inside the image. This is what Claude Code loads as
    # managed-policy context. Verifying the file is present AND
    # contains the expected header is the load-bearing claim — without
    # it, every connie run would start Claude Code with no context.
    expect the_workspace_image_contains_file "/etc/claude-code/CLAUDE.md"
    expect the_workspace_image_file_to_contain "/etc/claude-code/CLAUDE.md" \
        "# Connie Container Environment"
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
