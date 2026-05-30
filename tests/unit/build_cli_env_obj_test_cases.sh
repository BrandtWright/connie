# tests/unit/build_cli_env_obj_test_cases.sh
#
# Behavior specifications for _build_cli_env_obj — the function that
# folds newline-delimited KEY=VALUE pairs from --env CLI flags into a
# JSON object. The output feeds the env-precedence chain in
# _build_env_block, where the CLI object is the highest-precedence
# source (overriding both terminal-forwarding and config .env values).
#
# Pairs are encoded via yq's strenv so values that contain special
# characters (quotes, ampersands, newlines …) survive the round-trip
# without YAML/shell mangling.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Preconditions ──────────────────────────────────────────────────────────

no_cli_env_pairs() {
    cli_env_input=""
}

one_cli_env_pair() {
    cli_env_input="APP_ENV=production"
}

multiple_cli_env_pairs() {
    cli_env_input="APP_ENV=production
LOG_LEVEL=debug
PORT=8080"
}

a_cli_env_pair_with_no_equals_sign() {
    cli_env_input="KEY_WITHOUT_VALUE"
}

a_cli_env_pair_whose_value_contains_a_quote() {
    cli_env_input='QUOTED_VALUE=she said "hi"'
}

# ── Stimuli ────────────────────────────────────────────────────────────────

the_cli_env_object_is_built() {
    cli_env_output=$(_build_cli_env_obj "$cli_env_input")
}

# ── Assertions ─────────────────────────────────────────────────────────────

the_cli_env_output_is_an_empty_json_object() {
    expect_equal "{}" "$cli_env_output"
}

the_cli_env_output_contains_key() {
    _key="$1"
    _value=$(printf '%s' "$cli_env_output" | yq -p=json -o=json ".$_key")
    expect_equal "\"$2\"" "$_value"
}

the_cli_env_output_maps_a_bare_key_to_an_empty_string() {
    _value=$(printf '%s' "$cli_env_output" | yq -p=json -o=json '.KEY_WITHOUT_VALUE')
    expect_equal '""' "$_value"
}

the_quoted_value_round_trips_intact() {
    _value=$(printf '%s' "$cli_env_output" | yq -p=json '.QUOTED_VALUE')
    expect_equal 'she said "hi"' "$_value"
}

# ── Test cases ─────────────────────────────────────────────────────────────

build_cli_env_obj_returns_empty_object_when_no_pairs_provided_test_case() {
    given no_cli_env_pairs
    when the_cli_env_object_is_built
    expect the_cli_env_output_is_an_empty_json_object
}

build_cli_env_obj_encodes_a_single_pair_as_one_key_test_case() {
    given one_cli_env_pair
    when the_cli_env_object_is_built
    expect the_cli_env_output_contains_key APP_ENV production
}

build_cli_env_obj_encodes_every_pair_in_a_multiline_list_test_case() {
    given multiple_cli_env_pairs
    when the_cli_env_object_is_built
    expect the_cli_env_output_contains_key APP_ENV production
    expect the_cli_env_output_contains_key LOG_LEVEL debug
    expect the_cli_env_output_contains_key PORT 8080
}

build_cli_env_obj_maps_a_bare_key_with_no_value_to_an_empty_string_test_case() {
    given a_cli_env_pair_with_no_equals_sign
    when the_cli_env_object_is_built
    expect the_cli_env_output_maps_a_bare_key_to_an_empty_string
}

build_cli_env_obj_round_trips_values_with_special_characters_test_case() {
    given a_cli_env_pair_whose_value_contains_a_quote
    when the_cli_env_object_is_built
    expect the_quoted_value_round_trips_intact
}
