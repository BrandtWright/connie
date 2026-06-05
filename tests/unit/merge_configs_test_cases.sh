# tests/unit/merge_configs_test_cases.sh
#
# Behavior specifications for _merge_configs. The function deep-merges
# YAML config layers in ascending precedence:
#
#     defaults.yml  →  /etc/xdg/connie/config.yml  →
#         ~/.config/connie/config.yml  →
#             ~/.config/connie/projects/<slug>/config.yml
#
# Composition is ADDITIVE and keyed (see docs/config-merge.md): maps and
# scalars deep-merge with the most-specific layer winning per leaf;
# build_commands append in precedence order; and the keyed-set arrays
# (packages, ports, unsafe_extra_mounts) accumulate across layers, then
# collapse to one entry per identity — package name, host port, container
# target — keeping the most-specific. The tests below verify the precedence
# chain and each of those behaviours.
#
# The harness exports CONNIE_LIB_DIR pointing at the in-tree src/ so
# $DEFAULTS_FILE resolves to the repo's defaults.yml (not the
# system-installed path that does not exist in the sandbox).

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Preconditions ──────────────────────────────────────────────────────────

a_project_path_in_the_workspace() {
    project_path="$WORKSPACE/project"
    mkdir -p "$project_path"
}

a_user_config_that_overrides_memory() {
    mkdir -p "$XDG_CONFIG_HOME/connie"
    cat >"$XDG_CONFIG_HOME/connie/config.yml" <<EOF
resources:
  memory: 8g
EOF
}

a_project_config_that_overrides_memory() {
    _cfg_dir="$XDG_CONFIG_HOME/connie/projects/$(_project_slug "$project_path")"
    mkdir -p "$_cfg_dir"
    cat >"$_cfg_dir/config.yml" <<EOF
resources:
  memory: 16g
EOF
}

a_project_config_with_a_custom_package_list() {
    _cfg_dir="$XDG_CONFIG_HOME/connie/projects/$(_project_slug "$project_path")"
    mkdir -p "$_cfg_dir"
    cat >"$_cfg_dir/config.yml" <<EOF
packages:
  - vim
  - htop
EOF
}

a_user_config_that_sets_only_cpus_and_a_project_config_that_sets_only_memory() {
    mkdir -p "$XDG_CONFIG_HOME/connie"
    cat >"$XDG_CONFIG_HOME/connie/config.yml" <<EOF
resources:
  cpus: "4.0"
EOF
    _cfg_dir="$XDG_CONFIG_HOME/connie/projects/$(_project_slug "$project_path")"
    mkdir -p "$_cfg_dir"
    cat >"$_cfg_dir/config.yml" <<EOF
resources:
  memory: 8g
EOF
}

a_user_config_with_one_package_list_and_a_project_config_with_another() {
    mkdir -p "$XDG_CONFIG_HOME/connie"
    cat >"$XDG_CONFIG_HOME/connie/config.yml" <<EOF
packages:
  - shellcheck
  - markdownlint
EOF
    _cfg_dir="$XDG_CONFIG_HOME/connie/projects/$(_project_slug "$project_path")"
    mkdir -p "$_cfg_dir"
    cat >"$_cfg_dir/config.yml" <<EOF
packages:
  - vim
EOF
}

a_corrupted_defaults_file_path() {
    # Override CONNIE_LIB_DIR to point at a directory with no defaults.yml.
    export CONNIE_LIB_DIR="$WORKSPACE/no-such-lib"
    # Re-source connie so DEFAULTS_FILE picks up the new value.
    CONNIE_NO_DISPATCH=1
    export CONNIE_NO_DISPATCH
    # shellcheck source=/dev/null
    . "$_HARNESS_REPO_ROOT/src/connie"
    unset CONNIE_NO_DISPATCH
}

a_user_and_project_config_sharing_a_package() {
    mkdir -p "$XDG_CONFIG_HOME/connie"
    cat >"$XDG_CONFIG_HOME/connie/config.yml" <<EOF
packages:
  - git
  - vim
EOF
    _cfg_dir="$XDG_CONFIG_HOME/connie/projects/$(_project_slug "$project_path")"
    mkdir -p "$_cfg_dir"
    cat >"$_cfg_dir/config.yml" <<EOF
packages:
  - vim
  - htop
EOF
}

a_user_and_project_config_each_with_build_commands() {
    mkdir -p "$XDG_CONFIG_HOME/connie"
    cat >"$XDG_CONFIG_HOME/connie/config.yml" <<EOF
build_commands:
  - echo user
EOF
    _cfg_dir="$XDG_CONFIG_HOME/connie/projects/$(_project_slug "$project_path")"
    mkdir -p "$_cfg_dir"
    cat >"$_cfg_dir/config.yml" <<EOF
build_commands:
  - echo project
EOF
}

a_user_and_project_config_with_different_ports() {
    mkdir -p "$XDG_CONFIG_HOME/connie"
    cat >"$XDG_CONFIG_HOME/connie/config.yml" <<EOF
ports:
  - "9090:90"
EOF
    _cfg_dir="$XDG_CONFIG_HOME/connie/projects/$(_project_slug "$project_path")"
    mkdir -p "$_cfg_dir"
    cat >"$_cfg_dir/config.yml" <<EOF
ports:
  - "8080:3000"
EOF
}

a_user_and_project_config_mapping_the_same_host_port() {
    mkdir -p "$XDG_CONFIG_HOME/connie"
    cat >"$XDG_CONFIG_HOME/connie/config.yml" <<EOF
ports:
  - "8080:80"
EOF
    _cfg_dir="$XDG_CONFIG_HOME/connie/projects/$(_project_slug "$project_path")"
    mkdir -p "$_cfg_dir"
    cat >"$_cfg_dir/config.yml" <<EOF
ports:
  - "8080:3000"
EOF
}

a_user_and_project_config_with_different_mount_targets() {
    mkdir -p "$XDG_CONFIG_HOME/connie"
    cat >"$XDG_CONFIG_HOME/connie/config.yml" <<EOF
unsafe_extra_mounts:
  - /srv/data:/data:ro
EOF
    _cfg_dir="$XDG_CONFIG_HOME/connie/projects/$(_project_slug "$project_path")"
    mkdir -p "$_cfg_dir"
    cat >"$_cfg_dir/config.yml" <<EOF
unsafe_extra_mounts:
  - /srv/logs:/logs:ro
EOF
}

a_user_and_project_config_redefining_the_same_mount_target() {
    mkdir -p "$XDG_CONFIG_HOME/connie"
    cat >"$XDG_CONFIG_HOME/connie/config.yml" <<EOF
unsafe_extra_mounts:
  - /srv/data:/data:ro
EOF
    _cfg_dir="$XDG_CONFIG_HOME/connie/projects/$(_project_slug "$project_path")"
    mkdir -p "$_cfg_dir"
    cat >"$_cfg_dir/config.yml" <<EOF
unsafe_extra_mounts:
  - /srv/newdata:/data:rw
EOF
}

a_fully_commented_user_config_and_a_project_with_packages() {
    mkdir -p "$XDG_CONFIG_HOME/connie"
    cat >"$XDG_CONFIG_HOME/connie/config.yml" <<EOF
# entirely comments, so this user config parses to null
# packages:
#   - ripgrep
EOF
    _cfg_dir="$XDG_CONFIG_HOME/connie/projects/$(_project_slug "$project_path")"
    mkdir -p "$_cfg_dir"
    cat >"$_cfg_dir/config.yml" <<EOF
packages:
  - vim
EOF
}

# ── Stimuli ────────────────────────────────────────────────────────────────

the_configs_are_merged() {
    merged_output=$(_merge_configs "$project_path")
}

the_configs_are_merged_capturing_the_exit_status() {
    merged_output=$(_merge_configs "$project_path" 2>"$TEST_STDERR") ||
        merge_exit_status=$?
    merge_exit_status=${merge_exit_status:-0}
}

# ── Assertions ─────────────────────────────────────────────────────────────

the_memory_value_to_be() {
    _expected="$1"
    _actual=$(printf '%s' "$merged_output" | yq '.resources.memory')
    expect_equal "$_expected" "$_actual"
}

the_cpus_value_to_be() {
    _expected="$1"
    _actual=$(printf '%s' "$merged_output" | yq '.resources.cpus')
    expect_equal "$_expected" "$_actual"
}

the_packages_to_be_exactly() {
    _expected="$1"
    _actual=$(printf '%s' "$merged_output" | yq -o=json -I=0 '.packages')
    expect_equal "$_expected" "$_actual"
}

the_build_commands_to_be_exactly() {
    _expected="$1"
    _actual=$(printf '%s' "$merged_output" | yq -o=json -I=0 '.build_commands')
    expect_equal "$_expected" "$_actual"
}

the_ports_to_be_exactly() {
    _expected="$1"
    _actual=$(printf '%s' "$merged_output" | yq -o=json -I=0 '.ports')
    expect_equal "$_expected" "$_actual"
}

the_mounts_to_be_exactly() {
    _expected="$1"
    _actual=$(printf '%s' "$merged_output" | yq -o=json -I=0 '.unsafe_extra_mounts')
    expect_equal "$_expected" "$_actual"
}

merge_to_fail_with_a_useful_error() {
    expect_not_equal "0" "$merge_exit_status"
    grep -F "defaults.yml not found" "$TEST_STDERR" >/dev/null && return 0
    _assertion_failure "stderr to mention defaults.yml" "defaults.yml not found" \
        "stderr was" "$(cat "$TEST_STDERR")"
}

# ── Test cases ─────────────────────────────────────────────────────────────

merge_configs_returns_defaults_when_no_other_configs_exist_test_case() {
    given a_project_path_in_the_workspace
    when the_configs_are_merged
    expect the_memory_value_to_be "4g"
}

merge_configs_lets_user_config_override_defaults_test_case() {
    given a_project_path_in_the_workspace
    given a_user_config_that_overrides_memory
    when the_configs_are_merged
    expect the_memory_value_to_be "8g"
}

merge_configs_lets_project_config_override_user_config_test_case() {
    given a_project_path_in_the_workspace
    given a_user_config_that_overrides_memory
    given a_project_config_that_overrides_memory
    when the_configs_are_merged
    expect the_memory_value_to_be "16g"
}

merge_configs_accumulates_package_lists_across_layers_test_case() {
    given a_project_path_in_the_workspace
    given a_user_config_with_one_package_list_and_a_project_config_with_another
    when the_configs_are_merged
    # User sets ["shellcheck", "markdownlint"]; project sets ["vim"]. Additive
    # composition keeps all three, in precedence order (user before project).
    expect the_packages_to_be_exactly '["shellcheck","markdownlint","vim"]'
}

merge_configs_deep_merges_maps_so_partial_overrides_compose_test_case() {
    given a_project_path_in_the_workspace
    given a_user_config_that_sets_only_cpus_and_a_project_config_that_sets_only_memory
    when the_configs_are_merged
    # The user config sets only resources.cpus; the project config sets
    # only resources.memory. Both should survive in the merged map
    # because map merging is recursive.
    expect the_memory_value_to_be "8g"
    expect the_cpus_value_to_be "4.0"
}

merge_configs_uses_only_defaults_when_no_project_config_exists_yet_test_case() {
    given a_project_path_in_the_workspace
    given a_user_config_that_overrides_memory
    when the_configs_are_merged
    # No project config yet — user config is the highest layer present.
    expect the_memory_value_to_be "8g"
}

merge_configs_includes_packages_from_the_project_config_test_case() {
    given a_project_path_in_the_workspace
    given a_project_config_with_a_custom_package_list
    when the_configs_are_merged
    expect the_packages_to_be_exactly '["vim","htop"]'
}

merge_configs_fails_with_a_clear_error_when_defaults_file_is_missing_test_case() {
    given a_project_path_in_the_workspace
    given a_corrupted_defaults_file_path
    when the_configs_are_merged_capturing_the_exit_status
    expect merge_to_fail_with_a_useful_error
}

merge_configs_dedupes_packages_present_in_multiple_layers_test_case() {
    given a_project_path_in_the_workspace
    given a_user_and_project_config_sharing_a_package
    when the_configs_are_merged
    # User [git, vim] + project [vim, htop]; the shared 'vim' appears once.
    expect the_packages_to_be_exactly '["git","vim","htop"]'
}

merge_configs_appends_build_commands_in_precedence_order_test_case() {
    given a_project_path_in_the_workspace
    given a_user_and_project_config_each_with_build_commands
    when the_configs_are_merged
    # Ordered list: user's command runs before the project's, no dedupe.
    expect the_build_commands_to_be_exactly '["echo user","echo project"]'
}

merge_configs_keeps_ports_for_distinct_host_ports_test_case() {
    given a_project_path_in_the_workspace
    given a_user_and_project_config_with_different_ports
    when the_configs_are_merged
    expect the_ports_to_be_exactly '["9090:90","8080:3000"]'
}

merge_configs_lets_a_lower_layer_remap_a_host_port_test_case() {
    given a_project_path_in_the_workspace
    given a_user_and_project_config_mapping_the_same_host_port
    when the_configs_are_merged
    # Both map host port 8080; the project (most specific) wins and the user's
    # 8080:80 is dropped — no invalid double host-port binding is emitted.
    expect the_ports_to_be_exactly '["8080:3000"]'
}

merge_configs_keeps_mounts_for_distinct_targets_test_case() {
    given a_project_path_in_the_workspace
    given a_user_and_project_config_with_different_mount_targets
    when the_configs_are_merged
    expect the_mounts_to_be_exactly '["/srv/data:/data:ro","/srv/logs:/logs:ro"]'
}

merge_configs_lets_a_lower_layer_redefine_a_mount_target_test_case() {
    given a_project_path_in_the_workspace
    given a_user_and_project_config_redefining_the_same_mount_target
    when the_configs_are_merged
    # Both mount container target /data; the project's source and mode win.
    expect the_mounts_to_be_exactly '["/srv/newdata:/data:rw"]'
}

merge_configs_tolerates_a_present_but_null_layer_test_case() {
    given a_project_path_in_the_workspace
    given a_fully_commented_user_config_and_a_project_with_packages
    when the_configs_are_merged
    # The all-comments user config parses to null and contributes nothing;
    # the project's packages still come through.
    expect the_packages_to_be_exactly '["vim"]'
}
