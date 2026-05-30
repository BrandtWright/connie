# tests/helpers/docker.sh
#
# Docker-specific fixtures, stimuli, and assertions for tests under
# tests/docker/. Sourced by the harness alongside preconditions.sh
# (harness sources every tests/helpers/*.sh), but the helpers here only
# do useful work when docker is on $PATH and a test uses them.
#
# Image isolation: tests set $CONNIE_BASE_IMAGE via
# `a_unique_test_base_image_tag` so connie writes to a one-off tag
# under the connie-test/base namespace. The fixture also registers a
# trap to `docker rmi` that tag at subshell exit, so a clean run leaves
# the user's `connie/base:latest` untouched and no stray test images
# behind. If a test is killed mid-run the orphan can be removed later
# with `docker image rm $(docker image ls -q connie-test/base)`.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Fixtures ───────────────────────────────────────────────────────────────

# Generate a unique image tag under the connie-test/base namespace and
# export it as CONNIE_BASE_IMAGE so connie's BASE_IMAGE constant picks it
# up. Registers a trap to remove the tag at subshell exit; an explicit
# `docker image rm -f` is used so test images don't accumulate even when
# they're tagged in interim build layers.
a_unique_test_base_image_tag() {
    # $TEST_NAME comes from the harness; $$ is the test subshell's PID.
    # The combination is guaranteed unique within a harness run.
    test_base_image="connie-test/base:harness-${TEST_NAME}-$$"
    export CONNIE_BASE_IMAGE="$test_base_image"
    # shellcheck disable=SC2064 # we want the variable resolved now
    trap "docker image rm -f '$test_base_image' >/dev/null 2>&1 || true" EXIT
}

# Variant for tests that exercise per-project image builds: also sets
# up a project directory and pre-computes the docker compose-derived
# workspace image name so cleanup removes BOTH the base and the
# workspace image at subshell exit. Docker compose names service images
# `<project>-<service>` when no explicit `image:` key is set; here that
# resolves to `connie-<slug>-workspace`.
a_unique_test_base_image_tag_and_an_initialized_project() {
    test_base_image="connie-test/base:harness-${TEST_NAME}-$$"
    export CONNIE_BASE_IMAGE="$test_base_image"
    project_path="$WORKSPACE/project"
    mkdir -p "$project_path"
    exercise_connie init "$project_path" >/dev/null 2>&1
    workspace_image="$(_compose_project_name "$project_path")-workspace"
    # shellcheck disable=SC2064 # we want the variables resolved now
    trap "docker image rm -f '$test_base_image' '$workspace_image' >/dev/null 2>&1 || true" EXIT
}

# Drop a sentinel file with known content into the project directory so
# tests can verify the /workspace bind mount surfaces it inside the
# container. Composes with the initialized-project fixture above.
a_sentinel_file_in_the_workspace() {
    printf 'sentinel-content' > "$project_path/SENTINEL"
}

# Variant that skips `connie init` and instead pre-creates a legacy
# `.connie/` directory inside the project root with a config.yml stub.
# This is the state a developer reaches when they upgrade connie across
# the XDG-migration boundary; `_prepare` should detect it and call
# `_migrate_project` before doing anything else.
a_unique_test_base_image_tag_and_a_legacy_dot_connie_project() {
    test_base_image="connie-test/base:harness-${TEST_NAME}-$$"
    export CONNIE_BASE_IMAGE="$test_base_image"
    project_path="$WORKSPACE/project"
    mkdir -p "$project_path/.connie"
    # Use the project template so the migrated config is a known-good
    # starting point that the build pipeline accepts. Without this,
    # `_prepare` would synthesize one from PROJECT_TEMPLATE — fine, but
    # then the test wouldn't be able to claim "the legacy config was
    # moved" since it could've been created from scratch.
    cp "$_HARNESS_REPO_ROOT/src/config/project-template.yml" \
       "$project_path/.connie/config.yml"
    workspace_image="$(_compose_project_name "$project_path")-workspace"
    # shellcheck disable=SC2064 # we want the variables resolved now
    trap "docker image rm -f '$test_base_image' '$workspace_image' >/dev/null 2>&1 || true" EXIT
}

# Variant that stages a fingerprint in the project's merged config — a
# unique env-var key/value pair that flows through _generate_connie_context
# into BOTH the in-container /etc/claude-code/CLAUDE.md AND the host's
# `connie context` preview. The fingerprint anchors the parity claim:
# the same config produces the same context text on both sides.
a_unique_test_base_image_tag_and_an_initialized_project_with_a_parity_fingerprint() {
    a_unique_test_base_image_tag_and_an_initialized_project
    _cfg=$(_project_config "$project_path")
    yq -i '.env.PARITY_CHECK = "fp-deadbeef-2026"' "$_cfg"
}

# ── Stimuli ────────────────────────────────────────────────────────────────

the_user_runs_connie_build_base() {
    exercise_connie build-base
}

the_user_runs_connie_build_against_the_project() {
    exercise_connie build "$project_path"
}

the_user_runs_connie_clean_against_the_project() {
    exercise_connie clean "$project_path"
}

# Run a one-shot command inside the workspace container via `connie run
# --cmd <command>`. The command is executed by sh as the container's
# start command (see the override's `command: "${_final_cmd}"`). Auto-
# TTY detection inside cmd_run will pass -T to docker compose because
# exercise_connie redirects stdout to a file, so the container's
# stdout/stderr land in $TEST_STDOUT/$TEST_STDERR cleanly.
the_user_runs_connie_run_with_command() {
    exercise_connie run --cmd "$1" "$project_path"
}

# Preview the four-scope context for the project on the host. Used by
# parity tests to verify that the managed-policy section reflects the
# same config values as the in-container /etc/claude-code/CLAUDE.md.
the_user_runs_connie_context_against_the_project() {
    exercise_connie context "$project_path"
}

# ── Assertions ─────────────────────────────────────────────────────────────

the_image_exists() {
    if docker image inspect "$test_base_image" >/dev/null 2>&1; then
        return 0
    fi
    _assertion_failure "image to exist" "$test_base_image" \
                       "actual" "no such image (docker image inspect failed)"
    return 1
}

the_image_user_field_to_be() {
    _expected="$1"
    _actual=$(docker image inspect "$test_base_image" --format '{{.Config.User}}')
    expect_equal "$_expected" "$_actual"
}

the_image_to_have_env_var() {
    _name="$1"
    _expected="$2"
    _actual=$(docker image inspect "$test_base_image" \
        --format "{{range .Config.Env}}{{println .}}{{end}}" \
        | grep "^${_name}=" | sed "s/^${_name}=//")
    expect_equal "$_expected" "$_actual"
}

the_image_entrypoint_to_include() {
    _expected="$1"
    _actual=$(docker image inspect "$test_base_image" --format '{{.Config.Entrypoint}}')
    expect_contains "$_actual" "$_expected"
}

# Verify that `id` for a given user inside the image yields the
# expected uid. Combines image-run with the assertion in one call so
# tests don't have to thread state between separate steps.
the_image_has_user_at_uid() {
    _user="$1"
    _expected_uid="$2"
    _actual=$(docker run --rm "$test_base_image" id -u "$_user" 2>/dev/null)
    expect_equal "$_expected_uid" "$_actual"
}

# Verify that a file exists inside the image at the given path (run
# inside a transient container).
the_image_contains_file() {
    _path="$1"
    if docker run --rm "$test_base_image" test -f "$_path" >/dev/null 2>&1; then
        return 0
    fi
    _assertion_failure "file to exist in image" "$_path" \
                       "actual" "no such file in container filesystem"
    return 1
}

# Verify a directory exists inside the image at the given path.
the_image_contains_directory() {
    _path="$1"
    if docker run --rm "$test_base_image" test -d "$_path" >/dev/null 2>&1; then
        return 0
    fi
    _assertion_failure "directory to exist in image" "$_path" \
                       "actual" "no such directory in container filesystem"
    return 1
}

# ── Workspace-image assertions ────────────────────────────────────────────
#
# Mirror the base-image assertions above but target $workspace_image (set
# by a_unique_test_base_image_tag_and_an_initialized_project) so per-
# project build tests can introspect the image cmd_build produced.

the_workspace_image_exists() {
    if docker image inspect "$workspace_image" >/dev/null 2>&1; then
        return 0
    fi
    _assertion_failure "image to exist" "$workspace_image" \
                       "actual" "no such image (docker image inspect failed)"
    return 1
}

the_workspace_image_contains_file() {
    _path="$1"
    if docker run --rm "$workspace_image" test -f "$_path" >/dev/null 2>&1; then
        return 0
    fi
    _assertion_failure "file to exist in workspace image" "$_path" \
                       "actual" "no such file in container filesystem"
    return 1
}

the_workspace_image_file_to_contain() {
    _path="$1"
    _expected="$2"
    _actual=$(docker run --rm "$workspace_image" cat "$_path" 2>/dev/null)
    case "$_actual" in
        *"$_expected"*) return 0 ;;
    esac
    _assertion_failure "file to contain" "$_expected (in $_path)" \
                       "actual contents" "$_actual"
    return 1
}

the_workspace_image_no_longer_exists() {
    if ! docker image inspect "$workspace_image" >/dev/null 2>&1; then
        return 0
    fi
    _assertion_failure "image to be absent" "$workspace_image" \
                       "actual" "image still present (cleanup did not run)"
    return 1
}

# ── Migration assertions ──────────────────────────────────────────────────
#
# These check that `_prepare`'s auto-migration moved a legacy `.connie/`
# layout into the XDG paths the harness has redirected HOME/XDG_* to.

the_xdg_config_to_exist_for_the_project() {
    _path=$(_project_config "$project_path")
    if [ -f "$_path" ]; then
        return 0
    fi
    _assertion_failure "XDG config to exist" "$_path" \
                       "actual" "no such file"
    return 1
}

the_legacy_dot_connie_directory_to_be_removed() {
    if [ ! -d "$project_path/.connie" ]; then
        return 0
    fi
    _assertion_failure "legacy .connie/ to be absent" "$project_path/.connie" \
                       "actual" "directory still present (rmdir skipped — non-empty?)"
    return 1
}
