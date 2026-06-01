# tests/integration/confirm_test_cases.sh
#
# Behavior specifications for _confirm — the interactive y/N prompt used by
# `connie remove`. Returns 0 only for an affirmative answer (y/Y/yes/YES);
# anything else, including an empty line or EOF, returns non-zero so the
# default is the safe "no". The prompt goes to stderr; the answer is read
# from stdin. Previously only the non-TTY refusal path (in cmd_remove) was
# covered; these exercise _confirm's accept/reject branches directly.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Stimuli ────────────────────────────────────────────────────────────────

# Feed $1 as the typed answer. _confirm is the last command in the pipe, so
# $? after the pipe is _confirm's own return value.
the_user_answers() {
    printf '%s\n' "$1" | _confirm "Proceed?" >/dev/null 2>&1
    confirm_status=$?
}

# No input at all (Ctrl-D / closed stdin): read fails and the answer is empty.
the_user_sends_eof() {
    _confirm "Proceed?" </dev/null >/dev/null 2>&1
    confirm_status=$?
}

# ── Assertions ─────────────────────────────────────────────────────────────

it_accepts() {
    expect_equal "0" "$confirm_status"
}

it_rejects() {
    expect_not_equal "0" "$confirm_status"
}

# ── Test cases ─────────────────────────────────────────────────────────────

confirm_accepts_a_lowercase_y_test_case() {
    when the_user_answers "y"
    expect it_accepts
}

confirm_accepts_an_uppercase_y_test_case() {
    when the_user_answers "Y"
    expect it_accepts
}

confirm_accepts_the_word_yes_test_case() {
    when the_user_answers "yes"
    expect it_accepts
}

confirm_rejects_a_lowercase_n_test_case() {
    when the_user_answers "n"
    expect it_rejects
}

confirm_rejects_an_empty_answer_test_case() {
    when the_user_answers ""
    expect it_rejects
}

confirm_rejects_an_arbitrary_word_test_case() {
    when the_user_answers "maybe"
    expect it_rejects
}

confirm_rejects_eof_test_case() {
    when the_user_sends_eof
    expect it_rejects
}
