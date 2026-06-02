# tests/integration/emit_local_context_test_cases.sh
#
# Behavior specifications for _emit_local_context — the function that
# emits the local-scope Claude Code context (./CLAUDE.local.md) from the
# project root. The local scope is intended for personal, gitignored
# project notes per the Claude Code memory docs. Unlike the user and
# project scopes, _emit_local_context does not add source-attribution
# markers — there is only one possible source file, so a marker would
# add no information. It emits nothing when the file is absent.
#
# The function uses `if [ -f ]; then cat; fi` rather than
# `[ -f ] && cat` specifically because the latter returns non-zero when
# the file is absent and the harness's command-substitution capture
# would abort under set -eu. There's a regression test for the
# empty-case return status below.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Preconditions ──────────────────────────────────────────────────────────

an_empty_project_directory_in_the_workspace() {
    project_path="$WORKSPACE/project"
    mkdir -p "$project_path"
}

a_project_with_a_claude_local_md() {
    an_empty_project_directory_in_the_workspace
    local_md_content="# Personal local-scope notes

Sandbox URL: http://localhost:8080
Test data live in fixtures/."
    printf '%s' "$local_md_content" >"$project_path/CLAUDE.local.md"
}

# ── Stimuli ────────────────────────────────────────────────────────────────

the_local_context_is_emitted() {
    emitted=$(_emit_local_context "$project_path")
    emit_exit_status=$?
}

# ── Assertions ─────────────────────────────────────────────────────────────

the_output_is_empty() {
    expect_empty "$emitted"
}

the_output_equals_the_local_claude_md_content() {
    expect_equal "$local_md_content" "$emitted"
}

the_emit_returned_zero() {
    expect_equal "0" "$emit_exit_status"
}

# ── Test cases ─────────────────────────────────────────────────────────────

local_context_emits_nothing_when_claude_local_md_does_not_exist_test_case() {
    given an_empty_project_directory_in_the_workspace
    when the_local_context_is_emitted
    expect the_output_is_empty
}

local_context_returns_zero_when_claude_local_md_does_not_exist_test_case() {
    # Regression check for the set -eu fix: this is the failure mode
    # that broke `connie context` before the function was switched from
    # `[ -f ] && cat` to `if [ -f ]; then cat; fi`.
    given an_empty_project_directory_in_the_workspace
    when the_local_context_is_emitted
    expect the_emit_returned_zero
}

local_context_emits_the_file_contents_verbatim_when_present_test_case() {
    given a_project_with_a_claude_local_md
    when the_local_context_is_emitted
    expect the_output_equals_the_local_claude_md_content
}
