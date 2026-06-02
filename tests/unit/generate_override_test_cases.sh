# tests/unit/generate_override_test_cases.sh
#
# Behavior specifications for _generate_override — the function that
# composes the per-project Docker Compose override file from the merged
# config plus CLI flag overrides. The output is YAML that gets passed to
# docker compose as a second -f file (the static base file at
# $LIB_DIR/docker/docker-compose.yml plus this generated override).
#
# Strategy:
#   - Verify the output parses as YAML and has the expected top-level
#     structure (services.workspace.{build,environment,volumes,...})
#   - Verify scalar values (resource limits, command) propagate from the
#     merged config
#   - Verify the CONNIE_* override env vars take precedence over the
#     merged config
#   - Verify the CLI flags propagate (--package appends, --cmd replaces)
#
# We assert via `yq` queries on the captured output rather than
# snapshotting, because the output includes WORKSPACE-derived paths that
# change every test run.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Preconditions ──────────────────────────────────────────────────────────

a_project_with_a_merged_config_at_defaults() {
    project_path="$WORKSPACE/project"
    mkdir -p "$project_path"
    merged_file="$WORKSPACE/merged.yml"
    cp "$_HARNESS_REPO_ROOT/src/config/defaults.yml" "$merged_file"
    extra_packages=""
    extra_env=""
    override_cmd=""
    unset CONNIE_MEMORY CONNIE_CPUS CONNIE_MAX_PIDS CONNIE_CMD
}

a_project_with_a_merged_config_specifying_packages() {
    a_project_with_a_merged_config_at_defaults
    yq -i '.packages = ["python3", "py3-pip"]' "$merged_file"
}

connie_memory_set_to_an_override_value() {
    export CONNIE_MEMORY=16g
}

connie_cmd_set_to_an_override_value() {
    export CONNIE_CMD=sh
}

a_cli_package_flag_for_an_additional_package() {
    extra_packages="vim"
}

a_cli_cmd_override() {
    override_cmd="bash"
}

# A start command containing characters that are special to YAML: double
# quotes (which broke the old `command: "${...}"` interpolation) and a
# ` #` sequence (read as a comment if emitted as a bare scalar).
a_cli_cmd_override_with_yaml_breaking_characters() {
    override_cmd='sh -c "echo hi # not-a-comment"'
}

a_merged_config_with_a_volume_path_that_needs_quoting() {
    a_project_with_a_merged_config_at_defaults
    yq -i '.volumes = ["/weird path:/data:ro"]' "$merged_file"
}

a_merged_config_with_a_port_mapping() {
    a_project_with_a_merged_config_at_defaults
    yq -i '.ports = ["8080:8080"]' "$merged_file"
}

# ── Stimuli ────────────────────────────────────────────────────────────────

the_override_is_generated() {
    override_output_file="$WORKSPACE/override.yml"
    _generate_override "$project_path" "$merged_file" \
        "$extra_packages" "$extra_env" "$override_cmd" \
        >"$override_output_file"
}

# ── Assertions ─────────────────────────────────────────────────────────────

the_override_parses_as_yaml() {
    if yq eval-all 'null' "$override_output_file" >/dev/null 2>&1; then
        return 0
    fi
    _assertion_failure "valid YAML" "parseable by yq" \
        "yq error" "$(yq 'null' "$override_output_file" 2>&1)"
}

the_override_has_a_workspace_service() {
    _actual=$(yq '.services.workspace | type' "$override_output_file")
    expect_equal "!!map" "$_actual"
}

the_override_value_at_path_to_be() {
    _path="$1"
    _expected="$2"
    _actual=$(yq "$_path" "$override_output_file")
    expect_equal "$_expected" "$_actual"
}

the_override_build_arg_extra_packages_to_be() {
    the_override_value_at_path_to_be '.services.workspace.build.args.EXTRA_PACKAGES' "$1"
}

the_override_volumes_list_contains() {
    _actual=$(yq '.services.workspace.volumes[]' "$override_output_file")
    expect_contains "$_actual" "$1"
}

the_override_ports_list_contains() {
    _actual=$(yq '.services.workspace.ports[]' "$override_output_file")
    expect_contains "$_actual" "$1"
}

# ── Test cases ─────────────────────────────────────────────────────────────

generate_override_produces_parseable_yaml_test_case() {
    given a_project_with_a_merged_config_at_defaults
    when the_override_is_generated
    expect the_override_parses_as_yaml
}

generate_override_includes_a_workspace_service_test_case() {
    given a_project_with_a_merged_config_at_defaults
    when the_override_is_generated
    expect the_override_has_a_workspace_service
}

generate_override_carries_memory_from_the_merged_config_test_case() {
    given a_project_with_a_merged_config_at_defaults
    when the_override_is_generated
    expect the_override_value_at_path_to_be ".services.workspace.mem_limit" "4g"
}

generate_override_carries_cpus_from_the_merged_config_test_case() {
    given a_project_with_a_merged_config_at_defaults
    when the_override_is_generated
    expect the_override_value_at_path_to_be ".services.workspace.cpus" "2.0"
}

generate_override_carries_max_pids_from_the_merged_config_test_case() {
    given a_project_with_a_merged_config_at_defaults
    when the_override_is_generated
    expect the_override_value_at_path_to_be ".services.workspace.pids_limit" "512"
}

generate_override_sets_working_dir_to_workspace_test_case() {
    given a_project_with_a_merged_config_at_defaults
    when the_override_is_generated
    expect the_override_value_at_path_to_be ".services.workspace.working_dir" "/workspace"
}

generate_override_carries_the_start_command_from_the_merged_config_test_case() {
    given a_project_with_a_merged_config_at_defaults
    when the_override_is_generated
    expect the_override_value_at_path_to_be ".services.workspace.command" "claude"
}

generate_override_lets_connie_memory_env_var_override_the_merged_config_test_case() {
    given a_project_with_a_merged_config_at_defaults
    given connie_memory_set_to_an_override_value
    when the_override_is_generated
    expect the_override_value_at_path_to_be ".services.workspace.mem_limit" "16g"
}

generate_override_lets_connie_cmd_env_var_override_the_start_command_test_case() {
    given a_project_with_a_merged_config_at_defaults
    given connie_cmd_set_to_an_override_value
    when the_override_is_generated
    expect the_override_value_at_path_to_be ".services.workspace.command" "sh"
}

generate_override_lets_the_cli_cmd_flag_take_highest_precedence_for_the_start_command_test_case() {
    given a_project_with_a_merged_config_at_defaults
    given connie_cmd_set_to_an_override_value
    given a_cli_cmd_override
    when the_override_is_generated
    # CLI --cmd flag is the highest precedence — it should win over
    # CONNIE_CMD env and the config start_cmd.
    expect the_override_value_at_path_to_be ".services.workspace.command" "bash"
}

generate_override_carries_packages_from_the_merged_config_into_the_build_arg_test_case() {
    given a_project_with_a_merged_config_specifying_packages
    when the_override_is_generated
    expect the_override_build_arg_extra_packages_to_be "python3 py3-pip"
}

generate_override_appends_the_cli_package_flag_to_the_packages_build_arg_test_case() {
    given a_project_with_a_merged_config_specifying_packages
    given a_cli_package_flag_for_an_additional_package
    when the_override_is_generated
    expect the_override_build_arg_extra_packages_to_be "python3 py3-pip vim"
}

generate_override_sets_memswap_limit_to_the_same_value_as_mem_limit_test_case() {
    given a_project_with_a_merged_config_at_defaults
    when the_override_is_generated
    # connie pins memswap_limit == mem_limit so the container cannot
    # swap memory under pressure — see DESIGN.md / the security model.
    _mem=$(yq '.services.workspace.mem_limit' "$override_output_file")
    _swap=$(yq '.services.workspace.memswap_limit' "$override_output_file")
    expect_equal "$_mem" "$_swap"
}

generate_override_stays_valid_yaml_when_the_command_has_quotes_and_a_hash_test_case() {
    given a_project_with_a_merged_config_at_defaults
    given a_cli_cmd_override_with_yaml_breaking_characters
    when the_override_is_generated
    # Inseparable claim: the override remains parseable AND the command
    # round-trips byte-for-byte. The old raw `command: "${...}"` splice
    # would have produced invalid YAML for this value.
    expect the_override_parses_as_yaml
    expect the_override_value_at_path_to_be ".services.workspace.command" \
        'sh -c "echo hi # not-a-comment"'
}

generate_override_quotes_a_volume_path_that_needs_it_and_stays_valid_test_case() {
    given a_merged_config_with_a_volume_path_that_needs_quoting
    when the_override_is_generated
    expect the_override_parses_as_yaml
    expect the_override_volumes_list_contains "/weird path:/data:ro"
}

generate_override_carries_a_configured_port_mapping_test_case() {
    given a_merged_config_with_a_port_mapping
    when the_override_is_generated
    expect the_override_parses_as_yaml
    expect the_override_ports_list_contains "8080:8080"
}

generate_override_sets_the_nofile_ulimits_to_the_documented_values_test_case() {
    given a_project_with_a_merged_config_at_defaults
    when the_override_is_generated
    expect the_override_value_at_path_to_be ".services.workspace.ulimits.nofile.soft" "4096"
    expect the_override_value_at_path_to_be ".services.workspace.ulimits.nofile.hard" "8192"
}

generate_override_passes_the_base_image_tag_through_as_a_build_arg_test_case() {
    given a_project_with_a_merged_config_at_defaults
    when the_override_is_generated
    # The BASE_IMAGE build arg propagates the script's BASE_IMAGE shell
    # variable (default `connie/base:latest`, overridable via
    # $CONNIE_BASE_IMAGE) to extend.Dockerfile's `FROM ${BASE_IMAGE}`.
    # Without this, the per-project image would always build from the
    # production tag, which would defeat test isolation.
    expect the_override_value_at_path_to_be ".services.workspace.build.args.BASE_IMAGE" "connie/base:latest"
}
