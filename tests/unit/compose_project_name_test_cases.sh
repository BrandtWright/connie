# tests/unit/compose_project_name_test_cases.sh
#
# Behavior specifications for _compose_project_name — a thin wrapper that
# prepends "connie-" to the project slug. The compose project name is used
# as Docker Compose's `-p` argument so each project's containers and images
# live in their own Compose namespace.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Preconditions ──────────────────────────────────────────────────────────

a_typical_absolute_project_path() {
    project_path="/home/user/repos/myproject"
}

two_distinct_project_paths_with_the_same_basename() {
    project_path_a="/home/user/repos/myproject"
    project_path_b="/var/projects/myproject"
}

# ── Stimuli ────────────────────────────────────────────────────────────────

the_compose_project_name_is_computed() {
    compose_name=$(_compose_project_name "$project_path")
}

the_compose_project_name_is_computed_for_each_path() {
    compose_name_a=$(_compose_project_name "$project_path_a")
    compose_name_b=$(_compose_project_name "$project_path_b")
}

# ── Assertions ─────────────────────────────────────────────────────────────

it_starts_with_the_connie_prefix() {
    expect_starts_with "$compose_name" "connie-"
}

it_appends_the_project_slug_after_the_prefix() {
    _expected_slug=$(_project_slug "$project_path")
    expect_equal "$compose_name" "connie-$_expected_slug"
}

the_compose_names_differ() {
    expect_not_equal "$compose_name_a" "$compose_name_b"
}

# ── Test cases ─────────────────────────────────────────────────────────────

compose_project_name_starts_with_the_connie_prefix_test_case() {
    given a_typical_absolute_project_path
    when the_compose_project_name_is_computed
    expect it_starts_with_the_connie_prefix
}

compose_project_name_appends_the_project_slug_test_case() {
    given a_typical_absolute_project_path
    when the_compose_project_name_is_computed
    expect it_appends_the_project_slug_after_the_prefix
}

compose_project_name_differs_for_different_paths_test_case() {
    given two_distinct_project_paths_with_the_same_basename
    when the_compose_project_name_is_computed_for_each_path
    expect the_compose_names_differ
}
