#!/bin/sh
# tests/unit/test_project_slug.sh
#
# Tests for the _project_slug function — a pure function that derives a
# stable per-project identifier from an absolute project path. The slug
# format is documented as `basename-hash`: a lowercased, dash-folded
# basename followed by the cksum of the full path.

test_slug_matches_documented_basename_dash_hash_format() {
    given "an absolute project path"
    path="/home/user/repos/myproject"

    when "computing the slug"
    slug=$(_project_slug "$path")

    then_ "the slug matches the documented basename-hash pattern"
    assert_matches "$slug" '^myproject-[0-9]+$'
}

test_slug_lowercases_uppercase_characters_in_basename() {
    given "a project path whose basename has uppercase characters"
    path="/home/user/repos/MyProject"

    when "computing the slug"
    slug=$(_project_slug "$path")

    then_ "the basename portion of the slug is lowercase"
    assert_starts_with "$slug" "myproject-"
}

test_slug_folds_non_alphanumeric_characters_to_dashes() {
    given "a project path with dots and spaces in the basename"
    path="/home/user/my.weird project"

    when "computing the slug"
    slug=$(_project_slug "$path")

    then_ "the non-alphanumeric characters are replaced by single dashes"
    assert_starts_with "$slug" "my-weird-project-"
}

test_slug_strips_trailing_dashes_from_basename() {
    given "a basename whose translation would otherwise end in dashes"
    path="/home/user/myproject--"

    when "computing the slug"
    slug=$(_project_slug "$path")

    then_ "the slug has exactly one dash between basename and hash"
    assert_matches "$slug" '^myproject-[0-9]+$'
}

test_slug_is_deterministic_for_the_same_input_path() {
    given "the same absolute project path used twice"
    path="/home/user/repos/myproject"

    when "computing the slug from each invocation"
    slug_a=$(_project_slug "$path")
    slug_b=$(_project_slug "$path")

    then_ "the two slugs are identical"
    assert_equal "$slug_a" "$slug_b"
}

test_slug_differs_when_the_input_path_differs() {
    given "two distinct project paths with the same basename"
    path_a="/home/user/repos/myproject"
    path_b="/var/projects/myproject"

    when "computing slugs for each"
    slug_a=$(_project_slug "$path_a")
    slug_b=$(_project_slug "$path_b")

    then_ "the slugs differ (because the hashed path differs)"
    assert_not_equal "$slug_a" "$slug_b"
}
