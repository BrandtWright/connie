# tests/docker/build_base_test_cases.sh
#
# Behavior specifications for `connie build-base` — the subcommand that
# builds the locally-tagged base image (default tag `connie/base:latest`,
# overridable via $CONNIE_BASE_IMAGE) from src/docker/base.Dockerfile.
# The base image is the foundation every per-project workspace image
# extends, so its security and runtime properties are load-bearing.
#
# These tests run from a Docker-capable host only (tests/run-docker.sh
# guards entry). Each test sets a unique $CONNIE_BASE_IMAGE so the
# user's real `connie/base:latest` is never overwritten — the trap in
# `a_unique_test_base_image_tag` rm's the test tag at subshell exit.
#
# The first test builds the image from scratch (slow — minutes); the
# rest hit Docker's layer cache so subsequent builds are seconds.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Test cases ─────────────────────────────────────────────────────────────

build_base_succeeds_against_a_clean_environment_test_case() {
    given a_unique_test_base_image_tag
    when the_user_runs_connie_build_base
    expect it_succeeds
}

build_base_produces_an_image_at_the_configured_tag_test_case() {
    given a_unique_test_base_image_tag
    when the_user_runs_connie_build_base
    expect the_image_exists
}

build_base_produces_an_image_configured_to_run_as_claude_user_test_case() {
    given a_unique_test_base_image_tag
    when the_user_runs_connie_build_base
    # The Config.User field on the image — set by the final `USER
    # claude-user` directive in base.Dockerfile — controls the default
    # uid the container runs as. Non-root is the load-bearing claim
    # here; capability dropping is layered on top at runtime, but if
    # this is wrong everything else degrades to root-in-container.
    expect the_image_user_field_to_be "claude-user"
}

build_base_produces_an_image_with_claude_user_at_uid_1000_test_case() {
    given a_unique_test_base_image_tag
    when the_user_runs_connie_build_base
    expect the_image_has_user_at_uid "claude-user" "1000"
}

build_base_produces_an_image_with_disable_autoupdater_baked_in_test_case() {
    given a_unique_test_base_image_tag
    when the_user_runs_connie_build_base
    # DISABLE_AUTOUPDATER=1 is what stops Claude Code's auto-updater
    # from hanging silently on the container's read-only filesystem at
    # startup — see DESIGN.md / base.Dockerfile. The env var must be
    # baked into the image, not just into the running container's env.
    expect the_image_to_have_env_var "DISABLE_AUTOUPDATER" "1"
}

build_base_produces_an_image_with_entrypoint_at_the_documented_path_test_case() {
    given a_unique_test_base_image_tag
    when the_user_runs_connie_build_base
    expect the_image_entrypoint_to_include "/usr/local/bin/entrypoint.sh"
}

build_base_produces_an_image_with_claude_code_installed_test_case() {
    given a_unique_test_base_image_tag
    when the_user_runs_connie_build_base
    # The Claude Code binary is installed by `install.sh` into
    # claude-user's $HOME/.local/bin/. Its presence at that path is
    # what makes `claude` resolvable as the default container command.
    expect the_image_contains_file "/home/claude-user/.local/bin/claude"
}

build_base_is_idempotent_when_the_image_already_exists_test_case() {
    given a_unique_test_base_image_tag
    given the_user_runs_connie_build_base
    # The image is now built. Re-running build-base should succeed
    # against the layer cache and leave the image at the same tag.
    when the_user_runs_connie_build_base
    expect it_succeeds
    expect the_image_exists
}
