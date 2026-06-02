# tests/unit/compose_hardening_test_cases.sh
#
# The whole containment model rests on the STATIC src/docker/docker-compose.yml
# carrying the hardening: read_only root, cap_drop ALL, no-new-privileges, a
# nosuid /tmp tmpfs, and init. connie's generated override is merged on top of
# this base, and every other test inspects only the override — so without these
# assertions a future edit that dropped cap_drop or no-new-privileges from the
# base file would leave the whole suite green while every container ran with
# full Linux capabilities. These tests pin the base posture directly.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Preconditions ──────────────────────────────────────────────────────────

a_path_to_the_base_compose_file() {
    compose_file="$_HARNESS_REPO_ROOT/src/docker/docker-compose.yml"
}

# ── Stimuli ────────────────────────────────────────────────────────────────

# $1 = a yq expression evaluated against the base compose file.
the_compose_value_at() {
    compose_value=$(yq "$1" "$compose_file")
}

# ── Test cases ─────────────────────────────────────────────────────────────

compose_base_enables_read_only_root_filesystem_test_case() {
    given a_path_to_the_base_compose_file
    when the_compose_value_at '.services.workspace.read_only'
    expect expect_equal "true" "$compose_value"
}

compose_base_drops_all_capabilities_test_case() {
    given a_path_to_the_base_compose_file
    when the_compose_value_at '.services.workspace.cap_drop | contains(["ALL"])'
    expect expect_equal "true" "$compose_value"
}

compose_base_sets_no_new_privileges_test_case() {
    given a_path_to_the_base_compose_file
    when the_compose_value_at '.services.workspace.security_opt | contains(["no-new-privileges:true"])'
    expect expect_equal "true" "$compose_value"
}

compose_base_injects_an_init_process_test_case() {
    given a_path_to_the_base_compose_file
    when the_compose_value_at '.services.workspace.init'
    expect expect_equal "true" "$compose_value"
}

compose_base_pins_the_non_root_user_test_case() {
    given a_path_to_the_base_compose_file
    when the_compose_value_at '.services.workspace.user'
    # Non-root enforced at the compose layer, not only via the image USER —
    # holds regardless of the base image built from.
    expect expect_equal "1000:1000" "$compose_value"
}

compose_base_mounts_tmp_as_a_nosuid_tmpfs_test_case() {
    given a_path_to_the_base_compose_file
    when the_compose_value_at '.services.workspace.tmpfs | join(" ")'
    # Inseparable claim about the one tmpfs entry: it is /tmp AND nosuid.
    expect expect_contains "$compose_value" "/tmp"
    expect expect_contains "$compose_value" "nosuid"
}
