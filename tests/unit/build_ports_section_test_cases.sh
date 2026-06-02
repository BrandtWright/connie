# tests/unit/build_ports_section_test_cases.sh
#
# Behavior specifications for _build_ports_section — the function that
# emits the `ports:` block in the generated Compose override. The block
# is conditional: if no ports are configured the function returns
# silently with empty output, so the override does not include an empty
# `ports:` key.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Preconditions ──────────────────────────────────────────────────────────

a_merged_config_with_no_ports() {
    merged_file="$WORKSPACE/merged.yml"
    printf 'ports: []\n' >"$merged_file"
}

a_merged_config_with_one_port() {
    merged_file="$WORKSPACE/merged.yml"
    cat >"$merged_file" <<EOF
ports:
  - "8080:8080"
EOF
}

a_merged_config_with_multiple_ports() {
    merged_file="$WORKSPACE/merged.yml"
    cat >"$merged_file" <<EOF
ports:
  - "8080:8080"
  - "9090:9090"
EOF
}

# ── Stimuli ────────────────────────────────────────────────────────────────

the_ports_section_is_built() {
    ports_output=$(_build_ports_section "$merged_file")
}

# ── Assertions ─────────────────────────────────────────────────────────────

the_ports_output_is_empty() {
    expect_empty "$ports_output"
}

the_ports_output_starts_with_the_ports_header() {
    expect_starts_with "$ports_output" "    ports:"
}

the_ports_output_contains() {
    expect_contains "$ports_output" "$1"
}

# ── Test cases ─────────────────────────────────────────────────────────────

build_ports_section_emits_nothing_when_no_ports_are_configured_test_case() {
    given a_merged_config_with_no_ports
    when the_ports_section_is_built
    expect the_ports_output_is_empty
}

build_ports_section_starts_with_the_ports_header_when_ports_are_configured_test_case() {
    given a_merged_config_with_one_port
    when the_ports_section_is_built
    expect the_ports_output_starts_with_the_ports_header
}

build_ports_section_includes_each_configured_port_mapping_test_case() {
    given a_merged_config_with_multiple_ports
    when the_ports_section_is_built
    expect the_ports_output_contains '- "8080:8080"'
    expect the_ports_output_contains '- "9090:9090"'
}
