# tests/unit/normalize_abs_path_test_cases.sh
#
# _normalize_abs_path is the lexical defense that makes the volume guard
# robust against equivalent spellings of a path (//, ., ..). It was only
# exercised indirectly via two _build_vol_block fixtures; these pin its
# behavior directly, since a regression here would silently weaken the
# socket/dangerous-mount guard.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Stimuli ────────────────────────────────────────────────────────────────

the_path_is_normalized() {
    normalized=$(_normalize_abs_path "$1")
}

# ── Assertions ─────────────────────────────────────────────────────────────

it_normalizes_to() {
    expect_equal "$1" "$normalized"
}

# ── Test cases ─────────────────────────────────────────────────────────────

normalize_collapses_double_slashes_test_case() {
    when the_path_is_normalized "/var//run"
    expect it_normalizes_to "/var/run"
}

normalize_drops_single_dot_segments_test_case() {
    when the_path_is_normalized "/var/./run/."
    expect it_normalizes_to "/var/run"
}

normalize_resolves_dotdot_segments_test_case() {
    when the_path_is_normalized "/var/run/../run"
    expect it_normalizes_to "/var/run"
}

normalize_resolves_multi_segment_dotdot_test_case() {
    when the_path_is_normalized "/a/b/c/../../d"
    expect it_normalizes_to "/a/d"
}

normalize_clamps_dotdot_past_root_to_root_test_case() {
    when the_path_is_normalized "/../../var/run"
    expect it_normalizes_to "/var/run"
}

normalize_strips_a_trailing_slash_test_case() {
    when the_path_is_normalized "/var/run/"
    expect it_normalizes_to "/var/run"
}

normalize_maps_root_and_dotdot_only_to_root_test_case() {
    when the_path_is_normalized "/.."
    expect it_normalizes_to "/"
}

normalize_passes_relative_input_through_unchanged_test_case() {
    # Relative inputs are not host bind sources that can reach the socket
    # dir, so they are returned as-is (named-volume / relative case).
    when the_path_is_normalized "named-volume"
    expect it_normalizes_to "named-volume"
}
