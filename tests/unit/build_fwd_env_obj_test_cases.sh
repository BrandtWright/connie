# tests/unit/build_fwd_env_obj_test_cases.sh
#
# Behavior specifications for _build_fwd_env_obj — the function that
# derives a JSON object of terminal-forwarding env vars from the host's
# $TERM and $COLORTERM. These vars become the lowest-precedence layer of
# the container's environment so Claude Code renders with the host's
# colour depth even though Docker -t hardcodes TERM=xterm and forwards
# no COLORTERM.
#
# The FORCE_COLOR value is derived:
#   COLORTERM=truecolor or 24bit                  → FORCE_COLOR=3
#   TERM matches *256color* or *truecolor*        → FORCE_COLOR=2
#   neither                                       → FORCE_COLOR=1
#
# COLORTERM is only included in the output object when set on the host.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Preconditions ──────────────────────────────────────────────────────────

a_truecolor_terminal() {
    export TERM=xterm-256color
    export COLORTERM=truecolor
}

a_24bit_colorterm_terminal() {
    export TERM=xterm
    export COLORTERM=24bit
}

a_256_color_terminal_without_a_colorterm_env_var() {
    export TERM=xterm-256color
    unset COLORTERM
}

a_basic_terminal_without_a_colorterm_env_var() {
    export TERM=xterm
    unset COLORTERM
}

a_terminal_environment_with_neither_term_nor_colorterm_set() {
    unset TERM
    unset COLORTERM
}

# ── Stimuli ────────────────────────────────────────────────────────────────

the_forwarded_env_object_is_built() {
    fwd_env_output=$(_build_fwd_env_obj)
}

# ── Assertions ─────────────────────────────────────────────────────────────

force_color_to_be() {
    _expected="$1"
    _actual=$(printf '%s' "$fwd_env_output" | yq -p=json '.FORCE_COLOR')
    expect_equal "$_expected" "$_actual"
}

term_to_be() {
    _expected="$1"
    _actual=$(printf '%s' "$fwd_env_output" | yq -p=json '.TERM')
    expect_equal "$_expected" "$_actual"
}

colorterm_to_be() {
    _expected="$1"
    _actual=$(printf '%s' "$fwd_env_output" | yq -p=json '.COLORTERM')
    expect_equal "$_expected" "$_actual"
}

colorterm_to_be_absent() {
    _actual=$(printf '%s' "$fwd_env_output" | yq -p=json -o=json '.COLORTERM // null')
    expect_equal "null" "$_actual"
}

# ── Test cases ─────────────────────────────────────────────────────────────

build_fwd_env_obj_sets_force_color_to_3_when_colorterm_is_truecolor_test_case() {
    given a_truecolor_terminal
    when the_forwarded_env_object_is_built
    expect force_color_to_be "3"
}

build_fwd_env_obj_sets_force_color_to_3_when_colorterm_is_24bit_test_case() {
    given a_24bit_colorterm_terminal
    when the_forwarded_env_object_is_built
    expect force_color_to_be "3"
}

build_fwd_env_obj_sets_force_color_to_2_for_a_256_color_term_without_colorterm_test_case() {
    given a_256_color_terminal_without_a_colorterm_env_var
    when the_forwarded_env_object_is_built
    expect force_color_to_be "2"
}

build_fwd_env_obj_sets_force_color_to_1_for_a_basic_term_without_colorterm_test_case() {
    given a_basic_terminal_without_a_colorterm_env_var
    when the_forwarded_env_object_is_built
    expect force_color_to_be "1"
}

build_fwd_env_obj_includes_colorterm_in_the_output_when_set_test_case() {
    given a_truecolor_terminal
    when the_forwarded_env_object_is_built
    expect colorterm_to_be "truecolor"
}

build_fwd_env_obj_omits_colorterm_from_the_output_when_unset_test_case() {
    given a_basic_terminal_without_a_colorterm_env_var
    when the_forwarded_env_object_is_built
    expect colorterm_to_be_absent
}

build_fwd_env_obj_defaults_term_to_xterm_256color_when_unset_on_the_host_test_case() {
    given a_terminal_environment_with_neither_term_nor_colorterm_set
    when the_forwarded_env_object_is_built
    expect term_to_be "xterm-256color"
}
