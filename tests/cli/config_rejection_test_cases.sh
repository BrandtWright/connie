# tests/cli/config_rejection_test_cases.sh
#
# End-to-end rejection tests: the security guards (dangerous-mount,
# control-char env key, resource validation) are enforced through a real
# `connie config` invocation, not just at the _generate_override unit level.
# This locks in the cmd_config -> _generate_override -> guard -> `|| exit $?`
# -> set -eu abort wiring, and proves no override is emitted on rejection
# (so `connie run` would never reach `docker compose`).

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Preconditions ──────────────────────────────────────────────────────────

an_initialized_project() {
    project_path="$WORKSPACE/project"
    mkdir -p "$project_path"
    exercise_connie init "$project_path" >/dev/null 2>&1
}

a_project_whose_config_mounts_the_docker_socket() {
    an_initialized_project
    yq -i '.unsafe_extra_mounts = ["/var/run/docker.sock:/var/run/docker.sock"]' \
        "$(_project_config "$project_path")"
}

a_project_whose_config_mounts_a_kernel_tree() {
    an_initialized_project
    yq -i '.unsafe_extra_mounts = ["/proc:/host/proc:rw"]' "$(_project_config "$project_path")"
}

a_project_whose_config_has_a_control_char_env_key() {
    an_initialized_project
    K=$(printf 'BAD\302\205KEY') yq -i '.env = {(strenv(K)): "v"}' \
        "$(_project_config "$project_path")"
}

a_project_whose_config_has_an_invalid_resource_value() {
    an_initialized_project
    yq -i '.resources.max_pids = "-"' "$(_project_config "$project_path")"
}

# ── Stimuli ────────────────────────────────────────────────────────────────

the_user_runs_connie_config() {
    exercise_connie config "$project_path"
}

# ── Assertions ─────────────────────────────────────────────────────────────

the_override_was_not_emitted() {
    # On rejection connie aborts before the override heredoc runs, so stdout
    # (where the override is written) must be empty.
    if [ ! -s "$TEST_STDOUT" ]; then
        return 0
    fi
    _assertion_failure "stdout to be empty (no override)" "(nothing)" \
        "stdout was" "$(cat "$TEST_STDOUT")"
}

# ── Test cases ─────────────────────────────────────────────────────────────

connie_config_aborts_on_a_docker_socket_volume_test_case() {
    given a_project_whose_config_mounts_the_docker_socket
    when the_user_runs_connie_config
    # Inseparable claim: it fails, emits no override, and says why.
    expect it_fails
    expect the_override_was_not_emitted
    expect stderr_to_contain "docker socket"
}

connie_config_aborts_on_a_kernel_tree_mount_test_case() {
    given a_project_whose_config_mounts_a_kernel_tree
    when the_user_runs_connie_config
    expect it_fails
    expect the_override_was_not_emitted
    expect stderr_to_contain "sensitive host path"
}

connie_config_aborts_on_a_control_char_env_key_test_case() {
    given a_project_whose_config_has_a_control_char_env_key
    when the_user_runs_connie_config
    expect it_fails
    expect stderr_to_contain "environment variable name"
}

connie_config_aborts_on_an_invalid_resource_value_test_case() {
    given a_project_whose_config_has_an_invalid_resource_value
    when the_user_runs_connie_config
    expect it_fails
    expect stderr_to_contain "Invalid resources.max_pids"
}
