# tests/unit/merge_configs_test_cases.sh
#
# Behavior specifications for _merge_configs. The function deep-merges
# YAML config layers in ascending precedence:
#
#     defaults.yml  →  /etc/xdg/connie/config.yml  →
#         ~/.config/connie/config.yml  →
#             ~/.config/connie/projects/<slug>/config.yml
#
# yq's `*` operator does a deep merge: subsequent maps overlay the
# previous (each key takes the later value, and nested maps merge
# recursively), but arrays are REPLACED rather than concatenated. The
# tests below verify both the precedence chain and that map/array
# semantics work as documented.
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

merge_configs_replaces_array_values_rather_than_concatenating_them_test_case() {
    given a_project_path_in_the_workspace
    given a_user_config_with_one_package_list_and_a_project_config_with_another
    when the_configs_are_merged
    # Project config sets ["vim"]; user config sets ["shellcheck",
    # "markdownlint"]. The merged result should be ["vim"] alone, because
    # yq's `*` operator replaces arrays rather than concatenating them.
    expect the_packages_to_be_exactly '["vim"]'
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
