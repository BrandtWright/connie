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
    printf 'unsafe_extra_mounts: []\n' >"$merged_file"
}

a_project_with_one_extra_volume() {
    a_project_with_no_extra_volumes
    cat >"$merged_file" <<EOF
unsafe_extra_mounts:
  - /data:/data:ro
EOF
}

a_project_with_multiple_extra_volumes() {
    a_project_with_no_extra_volumes
    cat >"$merged_file" <<EOF
unsafe_extra_mounts:
  - /data:/data:ro
  - /cache:/cache:rw
EOF
}

a_project_mounting_the_docker_socket() {
    a_project_with_no_extra_volumes
    cat >"$merged_file" <<EOF
unsafe_extra_mounts:
  - /var/run/docker.sock:/var/run/docker.sock
EOF
}

# A docker.sock living at a non-standard path must still be caught — the
# rejection keys on the socket filename, not the conventional directory.
a_project_mounting_the_docker_socket_from_a_custom_path() {
    a_project_with_no_extra_volumes
    cat >"$merged_file" <<EOF
unsafe_extra_mounts:
  - /home/me/run/docker.sock:/var/run/docker.sock:rw
EOF
}

# Mounting the socket's *directory* re-exposes it at the conventional path
# without naming the socket — the guard must catch this too.
a_project_mounting_the_socket_parent_directory() {
    a_project_with_no_extra_volumes
    cat >"$merged_file" <<EOF
unsafe_extra_mounts:
  - /var/run:/var/run
EOF
}

# A trailing slash must not defeat the directory check.
a_project_mounting_run_with_a_trailing_slash() {
    a_project_with_no_extra_volumes
    cat >"$merged_file" <<EOF
unsafe_extra_mounts:
  - /run/:/run
EOF
}

# Path-equivalent spellings of the socket directory (//, .., .) must
# normalize and be caught even when no socket exists at scan time.
a_project_mounting_the_socket_dir_via_double_slash() {
    a_project_with_no_extra_volumes
    cat >"$merged_file" <<EOF
unsafe_extra_mounts:
  - /var//run:/var/run
EOF
}

a_project_mounting_the_socket_dir_via_dotdot() {
    a_project_with_no_extra_volumes
    cat >"$merged_file" <<EOF
unsafe_extra_mounts:
  - /var/run/../run:/var/run
EOF
}

# The Docker data root is a host-takeover primitive comparable to the socket.
a_project_mounting_the_docker_data_root() {
    a_project_with_no_extra_volumes
    cat >"$merged_file" <<EOF
unsafe_extra_mounts:
  - /var/lib/docker:/var/lib/docker
EOF
}

# Leading whitespace on the host source must not dodge the guard.
a_project_mounting_the_socket_dir_with_leading_space() {
    a_project_with_no_extra_volumes
    cat >"$merged_file" <<EOF
unsafe_extra_mounts:
  - " /var/run:/x"
EOF
}

# Kernel/device/daemon-data escape mounts — catastrophic and unrelated to
# the socket; the guard must reject this whole class, not just docker.sock.
a_project_mounting_proc() {
    a_project_with_no_extra_volumes
    printf 'unsafe_extra_mounts:\n  - /proc:/host/proc:rw\n' >"$merged_file"
}

a_project_mounting_a_raw_device() {
    a_project_with_no_extra_volumes
    printf 'unsafe_extra_mounts:\n  - /dev/mem:/m:rw\n' >"$merged_file"
}

a_project_mounting_a_daemon_data_root_child() {
    a_project_with_no_extra_volumes
    printf 'unsafe_extra_mounts:\n  - /var/lib/docker/volumes:/v:rw\n' >"$merged_file"
}

# A non-docker.sock-named source mapped onto the conventional in-container
# socket path — the container-TARGET bypass.
a_project_remapping_a_renamed_socket_to_the_conventional_target() {
    a_project_with_no_extra_volumes
    printf 'unsafe_extra_mounts:\n  - /home/me/api.sock:/var/run/docker.sock\n' >"$merged_file"
}

# An extra mount whose target shadows a connie standard mount.
a_project_shadowing_the_workspace_mount() {
    a_project_with_no_extra_volumes
    printf 'unsafe_extra_mounts:\n  - /elsewhere:/workspace:rw\n' >"$merged_file"
}

a_project_shadowing_the_claude_state_mount() {
    a_project_with_no_extra_volumes
    printf 'unsafe_extra_mounts:\n  - /attacker:/home/claude-user/.claude:rw\n' >"$merged_file"
}

# Unsafe mount propagation can manipulate the host mount namespace.
a_project_with_unsafe_mount_propagation() {
    a_project_with_no_extra_volumes
    printf 'unsafe_extra_mounts:\n  - /data:/d:rshared\n' >"$merged_file"
}

# The old 'volumes:' key was removed; a stale config using it must fail
# loudly rather than silently dropping a mount the user still expects.
a_project_using_the_removed_volumes_key() {
    a_project_with_no_extra_volumes
    printf 'volumes:\n  - /data:/data:ro\n' >"$merged_file"
}

# Mounting host root exposes the socket (and everything else).
a_project_mounting_host_root() {
    a_project_with_no_extra_volumes
    cat >"$merged_file" <<EOF
unsafe_extra_mounts:
  - /:/host:ro
EOF
}

# Long-syntax (mapping) entries are unsupported and must be rejected rather
# than silently flattened into bogus mounts that also evade the socket guard.
a_project_with_a_long_syntax_volume() {
    a_project_with_no_extra_volumes
    cat >"$merged_file" <<EOF
unsafe_extra_mounts:
  - type: bind
    source: /var/run/docker.sock
    target: /var/run/docker.sock
EOF
}

# A path whose value needs YAML quoting (embedded space) must round-trip
# intact through the yq block emission — the property the emitter exists for.
a_project_with_a_volume_path_needing_quoting() {
    a_project_with_no_extra_volumes
    cat >"$merged_file" <<EOF
unsafe_extra_mounts:
  - "/weird path:/data:ro"
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
    expect_contains "$vol_stderr" "docker socket"
}

the_error_explains_the_unsupported_entry() {
    expect_contains "$vol_stderr" "Unsupported entry in unsafe_extra_mounts"
}

the_error_mentions_a_sensitive_path() {
    expect_contains "$vol_stderr" "sensitive host path"
}

the_error_mentions_target_reexposes_socket() {
    expect_contains "$vol_stderr" "re-exposes the Docker socket"
}

the_error_mentions_shadowing() {
    expect_contains "$vol_stderr" "shadows a standard"
}

the_error_mentions_unsafe_propagation() {
    expect_contains "$vol_stderr" "unsafe propagation"
}

the_error_mentions_the_removed_volumes_key() {
    expect_contains "$vol_stderr" "has been removed"
}

# Re-parse the emitted block (indented items are valid under a volumes: key)
# and assert the mount survived intact.
the_vol_output_round_trips_to_contain() {
    _parsed=$(printf 'volumes:\n%s\n' "$vol_output" | yq '.volumes[]')
    expect_contains "$_parsed" "$1"
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

build_vol_block_refuses_mounting_the_socket_parent_directory_test_case() {
    given a_project_mounting_the_socket_parent_directory
    when the_volumes_block_build_is_attempted
    expect it_rejects_the_mount
    expect the_error_explains_the_docker_socket_refusal
}

build_vol_block_refuses_a_socket_directory_with_a_trailing_slash_test_case() {
    given a_project_mounting_run_with_a_trailing_slash
    when the_volumes_block_build_is_attempted
    expect it_rejects_the_mount
}

build_vol_block_refuses_mounting_host_root_test_case() {
    given a_project_mounting_host_root
    when the_volumes_block_build_is_attempted
    expect it_rejects_the_mount
}

build_vol_block_normalizes_a_double_slash_socket_dir_and_refuses_it_test_case() {
    given a_project_mounting_the_socket_dir_via_double_slash
    when the_volumes_block_build_is_attempted
    expect it_rejects_the_mount
}

build_vol_block_normalizes_a_dotdot_socket_dir_and_refuses_it_test_case() {
    given a_project_mounting_the_socket_dir_via_dotdot
    when the_volumes_block_build_is_attempted
    expect it_rejects_the_mount
}

build_vol_block_refuses_mounting_the_docker_data_root_test_case() {
    given a_project_mounting_the_docker_data_root
    when the_volumes_block_build_is_attempted
    expect it_rejects_the_mount
}

build_vol_block_refuses_a_socket_dir_with_leading_whitespace_test_case() {
    given a_project_mounting_the_socket_dir_with_leading_space
    when the_volumes_block_build_is_attempted
    expect it_rejects_the_mount
}

build_vol_block_refuses_mounting_the_proc_tree_test_case() {
    given a_project_mounting_proc
    when the_volumes_block_build_is_attempted
    expect it_rejects_the_mount
    expect the_error_mentions_a_sensitive_path
}

build_vol_block_refuses_mounting_a_raw_device_test_case() {
    given a_project_mounting_a_raw_device
    when the_volumes_block_build_is_attempted
    expect it_rejects_the_mount
    expect the_error_mentions_a_sensitive_path
}

build_vol_block_refuses_mounting_a_daemon_data_root_child_test_case() {
    given a_project_mounting_a_daemon_data_root_child
    when the_volumes_block_build_is_attempted
    expect it_rejects_the_mount
}

build_vol_block_refuses_a_renamed_socket_on_the_conventional_target_test_case() {
    given a_project_remapping_a_renamed_socket_to_the_conventional_target
    when the_volumes_block_build_is_attempted
    # The host name is not docker.sock, so the source check passes; the
    # container-target check must catch it re-exposing the socket path.
    expect it_rejects_the_mount
    expect the_error_mentions_target_reexposes_socket
}

build_vol_block_refuses_shadowing_the_workspace_mount_test_case() {
    given a_project_shadowing_the_workspace_mount
    when the_volumes_block_build_is_attempted
    expect it_rejects_the_mount
    expect the_error_mentions_shadowing
}

build_vol_block_refuses_shadowing_the_claude_state_mount_test_case() {
    given a_project_shadowing_the_claude_state_mount
    when the_volumes_block_build_is_attempted
    expect it_rejects_the_mount
    expect the_error_mentions_shadowing
}

build_vol_block_refuses_unsafe_mount_propagation_test_case() {
    given a_project_with_unsafe_mount_propagation
    when the_volumes_block_build_is_attempted
    expect it_rejects_the_mount
    expect the_error_mentions_unsafe_propagation
}

build_vol_block_rejects_the_removed_volumes_key_test_case() {
    given a_project_using_the_removed_volumes_key
    when the_volumes_block_build_is_attempted
    # Migration: the old key must error loudly, not silently drop the mount.
    expect it_rejects_the_mount
    expect the_error_mentions_the_removed_volumes_key
}

build_vol_block_rejects_long_syntax_volume_entries_test_case() {
    given a_project_with_a_long_syntax_volume
    when the_volumes_block_build_is_attempted
    # Inseparable claim: the unsupported entry is rejected AND the message
    # tells the user to use short-syntax (not silently mangled into mounts).
    expect it_rejects_the_mount
    expect the_error_explains_the_unsupported_entry
}

build_vol_block_preserves_a_volume_path_that_needs_quoting_test_case() {
    given a_project_with_a_volume_path_needing_quoting
    when the_volumes_block_is_built
    expect the_vol_output_round_trips_to_contain "/weird path:/data:ro"
}
