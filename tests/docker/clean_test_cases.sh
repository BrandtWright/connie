# tests/docker/clean_test_cases.sh
#
# Behavior specifications for `connie clean` — the subcommand that
# removes the per-project workspace image (and any one-off containers
# left behind by `connie run`) while leaving the base image intact.
#
# Implementation: `docker compose -p <project> down --rmi local`. The
# `--rmi local` flag is what makes Compose remove the workspace image
# (the locally-built one without a remote registry tag) but skip the
# base image — pulled from elsewhere or locally tagged but not built
# by this Compose project — so a developer's `connie/base:latest`
# survives.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Test cases ─────────────────────────────────────────────────────────────

clean_succeeds_against_a_built_project_test_case() {
    given a_unique_test_base_image_tag_and_an_initialized_project
    given the_user_runs_connie_build_against_the_project
    when the_user_runs_connie_clean_against_the_project
    expect it_succeeds
}

clean_removes_the_per_project_workspace_image_test_case() {
    given a_unique_test_base_image_tag_and_an_initialized_project
    given the_user_runs_connie_build_against_the_project
    when the_user_runs_connie_clean_against_the_project
    expect the_workspace_image_no_longer_exists
}

clean_leaves_the_base_image_in_place_test_case() {
    given a_unique_test_base_image_tag_and_an_initialized_project
    given the_user_runs_connie_build_against_the_project
    when the_user_runs_connie_clean_against_the_project
    # The base image is a shared resource — other connie projects on
    # the same host build atop it. `--rmi local` skips images that
    # weren't built by the Compose project, so the base survives.
    expect the_image_exists
}

clean_is_idempotent_when_no_workspace_image_exists_yet_test_case() {
    given a_unique_test_base_image_tag_and_an_initialized_project
    # No build step — there is no workspace image to clean. `docker
    # compose down` should still exit cleanly; the user shouldn't get
    # an error just for running clean before build.
    when the_user_runs_connie_clean_against_the_project
    expect it_succeeds
}
