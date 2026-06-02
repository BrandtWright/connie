# tests/unit/build_vol_block_test_cases.sh
#
# Behavior specifications for _build_vol_block — the function that emits
# the YAML `volumes:` block in the generated Compose override. The block
# always begins with three standard mounts (the project at /workspace,
# and the per-project Claude Code state at ~/.claude/ and ~/.claude.json),
# then appends any extra volumes from the merged config.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Preconditions ──────────────────────────────────────────────────────────

a_project_with_no_extra_volumes() {
    project_path="$WORKSPACE/project"
    mkdir -p "$project_path"
    merged_file="$WORKSPACE/merged.yml"
    printf 'volumes: []\n' >"$merged_file"
}

a_project_with_one_extra_volume() {
    a_project_with_no_extra_volumes
    cat >"$merged_file" <<EOF
volumes:
  - /data:/data:ro
EOF
}

a_project_with_multiple_extra_volumes() {
    a_project_with_no_extra_volumes
    cat >"$merged_file" <<EOF
volumes:
  - /data:/data:ro
  - /cache:/cache:rw
EOF
}

a_project_mounting_the_docker_socket() {
    a_project_with_no_extra_volumes
    cat >"$merged_file" <<EOF
volumes:
  - /var/run/docker.sock:/var/run/docker.sock
EOF
}

# A docker.sock living at a non-standard path must still be caught — the
# rejection keys on the socket filename, not the conventional directory.
a_project_mounting_the_docker_socket_from_a_custom_path() {
    a_project_with_no_extra_volumes
    cat >"$merged_file" <<EOF
volumes:
  - /home/me/run/docker.sock:/var/run/docker.sock:rw
EOF
}

# ── Stimuli ────────────────────────────────────────────────────────────────

the_volumes_block_is_built() {
    vol_output=$(_build_vol_block "$project_path" "$merged_file")
}

# _build_vol_block calls _die (which exits) on a rejected mount. Run it in
# a subshell so the exit is captured as a status rather than aborting the
# test, and merge its stderr into a variable so the message can be checked.
the_volumes_block_build_is_attempted() {
    vol_stderr=$({ _build_vol_block "$project_path" "$merged_file" >/dev/null; } 2>&1)
    vol_status=$?
}

# ── Assertions ─────────────────────────────────────────────────────────────

the_vol_output_includes_the_workspace_mount() {
    expect_contains "$vol_output" "- ${project_path}:/workspace:rw"
}

the_vol_output_includes_the_claude_state_mount() {
    _state_dir=$(_project_state_dir "$project_path")
    expect_contains "$vol_output" "- ${_state_dir}/.claude:/home/claude-user/.claude"
}

the_vol_output_includes_the_claude_json_mount() {
    _state_dir=$(_project_state_dir "$project_path")
    expect_contains "$vol_output" "- ${_state_dir}/.claude.json:/home/claude-user/.claude.json"
}

the_vol_output_contains() {
    expect_contains "$vol_output" "$1"
}

it_rejects_the_mount() {
    expect_not_equal "0" "$vol_status"
}

the_error_explains_the_docker_socket_refusal() {
    expect_contains "$vol_stderr" "Docker socket"
}

# ── Test cases ─────────────────────────────────────────────────────────────

build_vol_block_always_includes_the_three_standard_mounts_test_case() {
    given a_project_with_no_extra_volumes
    when the_volumes_block_is_built
    expect the_vol_output_includes_the_workspace_mount
    expect the_vol_output_includes_the_claude_state_mount
    expect the_vol_output_includes_the_claude_json_mount
}

build_vol_block_appends_a_single_extra_volume_after_the_standard_mounts_test_case() {
    given a_project_with_one_extra_volume
    when the_volumes_block_is_built
    expect the_vol_output_includes_the_workspace_mount
    expect the_vol_output_contains "- /data:/data:ro"
}

build_vol_block_appends_each_extra_volume_from_the_merged_config_test_case() {
    given a_project_with_multiple_extra_volumes
    when the_volumes_block_is_built
    expect the_vol_output_contains "- /data:/data:ro"
    expect the_vol_output_contains "- /cache:/cache:rw"
}

build_vol_block_refuses_to_mount_the_docker_socket_test_case() {
    given a_project_mounting_the_docker_socket
    when the_volumes_block_build_is_attempted
    # Inseparable claim: the mount is rejected AND the user is told why.
    expect it_rejects_the_mount
    expect the_error_explains_the_docker_socket_refusal
}

build_vol_block_refuses_a_docker_socket_at_a_nonstandard_path_test_case() {
    given a_project_mounting_the_docker_socket_from_a_custom_path
    when the_volumes_block_build_is_attempted
    expect it_rejects_the_mount
}
