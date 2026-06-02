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

# A resource value carrying a newline + extra YAML key — the injection the
# bare-scalar splice would otherwise allow.
connie_memory_set_to_a_yaml_injection_attempt() {
    export CONNIE_MEMORY='4g
    privileged: true'
}

# A structurally-degenerate (but charset-valid) max_pids that would emit
# invalid YAML (`pids_limit: -`) if not rejected.
connie_max_pids_set_to_a_lone_dash() {
    export CONNIE_MAX_PIDS='-'
}

# A cpus value carrying a newline + extra YAML key — same injection class as
# the memory case, but cpus had no rejection test.
connie_cpus_set_to_a_yaml_injection_attempt() {
    export CONNIE_CPUS='2.0
    privileged: true'
}

# Docker's "unlimited" pids sentinel; the validator deliberately accepts a
# leading-only minus so -1 works.
connie_max_pids_set_to_unlimited() {
    export CONNIE_MAX_PIDS='-1'
}

# A merged config whose .env KEY contains a U+0085 (NEL) control char —
# @json leaves NEL unescaped and YAML treats it as a line break, so the key
# must be rejected rather than emitted into an unparseable override.
a_merged_config_with_a_control_char_env_key() {
    project_path="$WORKSPACE/project"
    mkdir -p "$project_path"
    merged_file="$WORKSPACE/merged.yml"
    K=$(printf 'BAD\xc2\x85KEY') yq -n '
        {"packages": [], "build_commands": [], "start_cmd": "claude",
         "resources": {"memory": "4g", "cpus": "2.0", "max_pids": 512},
         "env": {(strenv(K)): "v"}}' >"$merged_file"
    extra_packages=""
    extra_env=""
    override_cmd=""
    unset CONNIE_MEMORY CONNIE_CPUS CONNIE_MAX_PIDS CONNIE_CMD
}

# A merged config whose .env KEY embeds a newline crafted to inject a
# sibling compose key (privileged: true) onto the workspace service.
# An env key with YAML-special chars (colon-space, hash) but NO control
# character. It cannot inject a sibling key (that needs a line break, which
# is a control char and rejected separately), but a raw splice would still
# corrupt the mapping — so the @json key encoding must keep the override
# valid with the whole thing contained as one key.
a_merged_config_mounting_the_docker_socket() {
    a_project_with_a_merged_config_at_defaults
    yq -i '.volumes = ["/var/run/docker.sock:/var/run/docker.sock"]' "$merged_file"
}

a_merged_config_with_a_yaml_special_env_key() {
    a_project_with_a_merged_config_at_defaults
    yq -i '.env = {"X: y # privileged: true": "v"}' "$merged_file"
}

a_cli_package_flag_for_an_additional_package() {
    extra_packages="vim"
}

a_cli_cmd_override() {
    override_cmd="bash"
}

# A package token that would be read as an apk flag if passed through.
a_cli_package_flag_that_looks_like_an_apk_flag() {
    extra_packages="--allow-untrusted"
}

# A --env CLI key with a U+0085 (NEL) control char. Must be rejected from
# the raw input — the yq fold would otherwise silently drop it.
a_cli_env_flag_with_a_control_char_key() {
    a_project_with_a_merged_config_at_defaults
    extra_env=$(printf 'BAD\xc2\x85KEY=v')
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

# _generate_override may _die (exit) on an invalid resource value. Run it in
# a subshell so the exit becomes a captured status, and merge stderr.
the_override_generation_is_attempted() {
    override_output_file="$WORKSPACE/override.yml"
    override_gen_stderr=$({ _generate_override "$project_path" "$merged_file" \
        "$extra_packages" "$extra_env" "$override_cmd" \
        >"$override_output_file"; } 2>&1)
    override_gen_status=$?
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

generate_override_rejects_a_resource_value_carrying_a_yaml_injection_test_case() {
    given a_project_with_a_merged_config_at_defaults
    given connie_memory_set_to_a_yaml_injection_attempt
    when the_override_generation_is_attempted
    # The bare-scalar mem_limit splice would otherwise let a newline inject
    # a sibling compose key (e.g. privileged: true). Validation rejects it.
    expect expect_not_equal "0" "$override_gen_status"
    expect expect_contains "$override_gen_stderr" "Invalid resources.memory"
}

generate_override_rejects_a_package_name_that_looks_like_an_apk_flag_test_case() {
    given a_project_with_a_merged_config_at_defaults
    given a_cli_package_flag_that_looks_like_an_apk_flag
    when the_override_generation_is_attempted
    expect expect_not_equal "0" "$override_gen_status"
    expect expect_contains "$override_gen_stderr" "Invalid package name"
}

generate_override_rejects_a_degenerate_max_pids_value_test_case() {
    given a_project_with_a_merged_config_at_defaults
    given connie_max_pids_set_to_a_lone_dash
    when the_override_generation_is_attempted
    # A lone '-' passes the char allowlist but would emit invalid YAML
    # (`pids_limit: -`); reject it with a clean error instead.
    expect expect_not_equal "0" "$override_gen_status"
    expect expect_contains "$override_gen_stderr" "Invalid resources.max_pids"
}

generate_override_rejects_a_cpus_value_carrying_a_yaml_injection_test_case() {
    given a_project_with_a_merged_config_at_defaults
    given connie_cpus_set_to_a_yaml_injection_attempt
    when the_override_generation_is_attempted
    expect expect_not_equal "0" "$override_gen_status"
    expect expect_contains "$override_gen_stderr" "Invalid resources.cpus"
}

generate_override_accepts_max_pids_minus_one_as_unlimited_test_case() {
    given a_project_with_a_merged_config_at_defaults
    given connie_max_pids_set_to_unlimited
    when the_override_is_generated
    # Pins the documented "-1 = unlimited" behaviour against a tightening of
    # the max_pids pattern that would forbid the leading minus.
    expect the_override_value_at_path_to_be ".services.workspace.pids_limit" "-1"
}

generate_override_encodes_a_yaml_special_env_key_safely_test_case() {
    given a_merged_config_with_a_yaml_special_env_key
    when the_override_is_generated
    # @json on the key keeps the override valid and contains the whole
    # string as one key — nothing injected onto the workspace service.
    expect the_override_parses_as_yaml
    expect the_override_value_at_path_to_be ".services.workspace.privileged" "null"
}

generate_override_rejects_an_env_key_with_a_control_character_test_case() {
    given a_merged_config_with_a_control_char_env_key
    when the_override_generation_is_attempted
    # A NEL in the key would emit an unparseable override; reject it cleanly.
    expect expect_not_equal "0" "$override_gen_status"
    expect expect_contains "$override_gen_stderr" "control character"
}

generate_override_rejects_a_cli_env_key_with_a_control_character_test_case() {
    given a_cli_env_flag_with_a_control_char_key
    when the_override_generation_is_attempted
    # A control char in a --env key breaks the yq fold and would be silently
    # dropped; it must be caught from the raw input and rejected instead.
    expect expect_not_equal "0" "$override_gen_status"
    expect expect_contains "$override_gen_stderr" "control character"
}

generate_override_aborts_when_a_volume_exposes_the_docker_socket_test_case() {
    given a_merged_config_mounting_the_docker_socket
    when the_override_generation_is_attempted
    # _build_vol_block _dies inside a command substitution; _generate_override
    # must propagate that and abort, not silently drop the volumes block.
    expect expect_not_equal "0" "$override_gen_status"
    expect expect_contains "$override_gen_stderr" "docker socket"
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
