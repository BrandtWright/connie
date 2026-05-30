# tests/unit/generate_connie_context_test_cases.sh
#
# Behavior specifications for _generate_connie_context — the function that
# produces the managed-policy markdown ($CONNIE_CONTEXT) baked into the
# image at /etc/claude-code/CLAUDE.md. The function reads a merged config
# file and emits a markdown blob whose sections appear conditionally based
# on which config keys are populated. Tests:
#
#   - The structural scaffolding (always-present sections, resource limits
#     pulled from the merged config) is correct
#   - Each optional section appears iff its config key has values, and
#     does not appear when the key is empty or absent
#   - The fully populated output matches a stored snapshot, so any
#     accidental change to the generated markdown is surfaced loudly
#
# We avoid asserting tiny details of every line; the snapshot covers the
# regression-catching role. Content-presence assertions over individual
# sections describe the conditional-rendering contract clearly.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Preconditions ──────────────────────────────────────────────────────────

a_minimal_merged_config() {
    merged_file="$WORKSPACE/merged.yml"
    cat > "$merged_file" <<EOF
start_cmd: claude
resources:
  memory: 4g
  cpus: "2.0"
  max_pids: 512
packages: []
build_commands: []
env: {}
volumes: []
ports: []
EOF
    project_root="$WORKSPACE/project"
}

a_merged_config_with_packages() {
    a_minimal_merged_config
    yq -i '.packages = ["python3", "py3-pip"]' "$merged_file"
}

a_merged_config_with_build_commands() {
    a_minimal_merged_config
    yq -i '.build_commands = ["pip install black", "pip install ruff"]' "$merged_file"
}

a_merged_config_with_extra_volumes() {
    a_minimal_merged_config
    yq -i '.volumes = ["/data:/data:ro"]' "$merged_file"
}

a_merged_config_with_exposed_ports() {
    a_minimal_merged_config
    yq -i '.ports = ["8080:8080"]' "$merged_file"
}

a_merged_config_with_environment_variables() {
    a_minimal_merged_config
    yq -i '.env = {"APP_ENV": "test", "LOG_LEVEL": "debug"}' "$merged_file"
}

a_merged_config_with_custom_resource_limits() {
    a_minimal_merged_config
    yq -i '.resources.memory = "8g" | .resources.cpus = "4.0" | .resources.max_pids = 1024' "$merged_file"
}

a_fully_populated_merged_config() {
    a_minimal_merged_config
    yq -i '
        .packages = ["python3", "py3-pip"] |
        .build_commands = ["pip install black"] |
        .volumes = ["/data:/data:ro"] |
        .ports = ["8080:8080"] |
        .env = {"APP_ENV": "test"} |
        .resources.memory = "8g" |
        .resources.cpus = "4.0" |
        .resources.max_pids = 1024
    ' "$merged_file"
}

# ── Stimuli ────────────────────────────────────────────────────────────────

the_connie_context_is_generated() {
    generated=$(_generate_connie_context "$project_root" "$merged_file")
}

# ── Assertions ─────────────────────────────────────────────────────────────

the_output_includes_the_title_heading() {
    expect_starts_with "$generated" "# Connie Container Environment"
}

the_output_describes_the_filesystem_layout() {
    expect_contains "$generated" "## Filesystem"
    expect_contains "$generated" "/workspace"
    expect_contains "$generated" "/tmp"
}

the_output_describes_the_available_tools() {
    expect_contains "$generated" "## Available Tools"
    expect_contains "$generated" "Base image:"
}

the_output_describes_the_resource_limits_with_the_merged_values() {
    expect_contains "$generated" "Memory: 8g"
    expect_contains "$generated" "CPUs: 4.0"
    expect_contains "$generated" "Max PIDs: 1024"
}

the_output_describes_the_security_constraints() {
    expect_contains "$generated" "## Security Constraints"
    expect_contains "$generated" "capabilities are dropped"
}

the_output_lists_the_project_packages() {
    expect_contains "$generated" "Project packages (apk): python3, py3-pip"
}

the_output_does_not_mention_project_packages() {
    case "$generated" in
        *"Project packages"*)
            _assertion_failure "packages section absence" "no packages line" \
                               "actual" "output contained 'Project packages'"
            return 1
            ;;
    esac
}

the_output_lists_the_build_commands() {
    expect_contains "$generated" "Build-time setup commands:"
    expect_contains "$generated" "- pip install black"
    expect_contains "$generated" "- pip install ruff"
}

the_output_does_not_have_a_build_commands_section() {
    case "$generated" in
        *"Build-time setup commands"*)
            _assertion_failure "build commands section absence" "no build-time section" \
                               "actual" "output contained 'Build-time setup commands'"
            return 1
            ;;
    esac
}

the_output_has_the_additional_mounts_section() {
    expect_contains "$generated" "## Additional Mounts"
    expect_contains "$generated" "- /data:/data:ro"
}

the_output_does_not_have_an_additional_mounts_section() {
    case "$generated" in
        *"Additional Mounts"*)
            _assertion_failure "additional mounts absence" "no additional mounts section" \
                               "actual" "output contained 'Additional Mounts'"
            return 1
            ;;
    esac
}

the_output_has_the_exposed_ports_section() {
    expect_contains "$generated" "## Exposed Ports"
    expect_contains "$generated" "- 8080:8080"
}

the_output_does_not_have_an_exposed_ports_section() {
    # Match the section header specifically (## Exposed Ports on its own
    # line). The string "Exposed Ports" also appears as prose inside the
    # always-present Security Constraints section, so a loose substring
    # check would false-positive.
    case "$generated" in
        *"## Exposed Ports"*)
            _assertion_failure "exposed ports absence" "no '## Exposed Ports' header" \
                               "actual" "output contained '## Exposed Ports'"
            return 1
            ;;
    esac
}

the_output_has_the_environment_variables_section() {
    expect_contains "$generated" "## Environment Variables"
    expect_contains "$generated" "APP_ENV: test"
    expect_contains "$generated" "LOG_LEVEL: debug"
}

the_output_does_not_have_an_environment_variables_section() {
    case "$generated" in
        *"Environment Variables"*)
            _assertion_failure "env vars section absence" "no environment variables section" \
                               "actual" "output contained 'Environment Variables'"
            return 1
            ;;
    esac
}

the_output_matches_the_fully_populated_snapshot() {
    expect_to_match_snapshot "connie_context_fully_populated.md" "$generated"
}

# ── Test cases ─────────────────────────────────────────────────────────────

connie_context_includes_the_standard_scaffolding_test_case() {
    given a_minimal_merged_config
    when the_connie_context_is_generated
    expect the_output_includes_the_title_heading
    expect the_output_describes_the_filesystem_layout
    expect the_output_describes_the_available_tools
    expect the_output_describes_the_security_constraints
}

connie_context_reflects_the_merged_resource_limits_test_case() {
    given a_merged_config_with_custom_resource_limits
    when the_connie_context_is_generated
    expect the_output_describes_the_resource_limits_with_the_merged_values
}

connie_context_lists_packages_when_the_config_has_them_test_case() {
    given a_merged_config_with_packages
    when the_connie_context_is_generated
    expect the_output_lists_the_project_packages
}

connie_context_omits_the_packages_line_when_the_config_has_none_test_case() {
    given a_minimal_merged_config
    when the_connie_context_is_generated
    expect the_output_does_not_mention_project_packages
}

connie_context_lists_build_commands_when_the_config_has_them_test_case() {
    given a_merged_config_with_build_commands
    when the_connie_context_is_generated
    expect the_output_lists_the_build_commands
}

connie_context_omits_the_build_commands_section_when_the_config_has_none_test_case() {
    given a_minimal_merged_config
    when the_connie_context_is_generated
    expect the_output_does_not_have_a_build_commands_section
}

connie_context_includes_additional_mounts_when_the_config_has_extra_volumes_test_case() {
    given a_merged_config_with_extra_volumes
    when the_connie_context_is_generated
    expect the_output_has_the_additional_mounts_section
}

connie_context_omits_the_additional_mounts_section_when_no_extra_volumes_are_set_test_case() {
    given a_minimal_merged_config
    when the_connie_context_is_generated
    expect the_output_does_not_have_an_additional_mounts_section
}

connie_context_includes_exposed_ports_when_the_config_has_them_test_case() {
    given a_merged_config_with_exposed_ports
    when the_connie_context_is_generated
    expect the_output_has_the_exposed_ports_section
}

connie_context_omits_the_exposed_ports_section_when_no_ports_are_set_test_case() {
    given a_minimal_merged_config
    when the_connie_context_is_generated
    expect the_output_does_not_have_an_exposed_ports_section
}

connie_context_includes_environment_variables_when_the_config_has_them_test_case() {
    given a_merged_config_with_environment_variables
    when the_connie_context_is_generated
    expect the_output_has_the_environment_variables_section
}

connie_context_omits_the_env_vars_section_when_no_env_vars_are_set_test_case() {
    given a_minimal_merged_config
    when the_connie_context_is_generated
    expect the_output_does_not_have_an_environment_variables_section
}

connie_context_matches_the_snapshot_for_a_fully_populated_config_test_case() {
    given a_fully_populated_merged_config
    when the_connie_context_is_generated
    expect the_output_matches_the_fully_populated_snapshot
}
