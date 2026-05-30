# tests/unit/project_slug_test_cases.sh
#
# Behavior specifications for _project_slug — a pure function that derives
# a stable per-project identifier from an absolute project path. The slug
# format is documented as `basename-hash`: a lowercased, dash-folded
# basename followed by the cksum of the full path.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Preconditions ──────────────────────────────────────────────────────────

a_typical_absolute_project_path() {
    project_path="/home/user/repos/myproject"
}

a_project_path_with_uppercase_characters() {
    project_path="/home/user/repos/MyProject"
}

a_project_path_with_dots_and_spaces_in_the_basename() {
    project_path="/home/user/my.weird project"
}

a_project_path_that_would_produce_trailing_dashes() {
    project_path="/home/user/myproject--"
}

two_distinct_paths_with_the_same_basename() {
    project_path_a="/home/user/repos/myproject"
    project_path_b="/var/projects/myproject"
}

# ── Stimuli ────────────────────────────────────────────────────────────────

the_slug_is_computed() {
    slug=$(_project_slug "$project_path")
}

the_slug_is_computed_twice() {
    slug_a=$(_project_slug "$project_path")
    slug_b=$(_project_slug "$project_path")
}

the_slug_is_computed_for_each_path() {
    slug_a=$(_project_slug "$project_path_a")
    slug_b=$(_project_slug "$project_path_b")
}

# ── Assertions (named for sentence-like test bodies) ───────────────────────

it_matches_the_documented_basename_hash_format() {
    expect_match "$slug" '^myproject-[0-9]+$'
}

it_starts_with_a_lowercased_basename() {
    expect_starts_with "$slug" "myproject-"
}

it_folds_non_alphanumeric_characters_to_single_dashes() {
    expect_starts_with "$slug" "my-weird-project-"
}

it_has_exactly_one_dash_between_basename_and_hash() {
    expect_match "$slug" '^myproject-[0-9]+$'
}

both_slugs_are_identical() {
    expect_equal "$slug_a" "$slug_b"
}

the_slugs_differ() {
    expect_not_equal "$slug_a" "$slug_b"
}

# ── Test cases ─────────────────────────────────────────────────────────────

slug_matches_the_documented_format_test_case() {
    given a_typical_absolute_project_path
    when the_slug_is_computed
    expect it_matches_the_documented_basename_hash_format
}

slug_lowercases_uppercase_characters_in_the_basename_test_case() {
    given a_project_path_with_uppercase_characters
    when the_slug_is_computed
    expect it_starts_with_a_lowercased_basename
}

slug_folds_non_alphanumeric_characters_to_dashes_test_case() {
    given a_project_path_with_dots_and_spaces_in_the_basename
    when the_slug_is_computed
    expect it_folds_non_alphanumeric_characters_to_single_dashes
}

slug_strips_trailing_dashes_from_the_basename_test_case() {
    given a_project_path_that_would_produce_trailing_dashes
    when the_slug_is_computed
    expect it_has_exactly_one_dash_between_basename_and_hash
}

slug_is_deterministic_for_the_same_input_test_case() {
    given a_typical_absolute_project_path
    when the_slug_is_computed_twice
    expect both_slugs_are_identical
}

slug_differs_when_the_input_path_differs_test_case() {
    given two_distinct_paths_with_the_same_basename
    when the_slug_is_computed_for_each_path
    expect the_slugs_differ
}
