# tests/cli/context_test_cases.sh
#
# CLI-level tests for `connie context` against an initialized project.
# Complements the existing error-path test (context_rejects_an_uninitialized
# _project) in tests/cli/usage_test_cases.sh.
#
# `connie context` prints the four Claude Code scope sections in load
# order to stdout: connie (managed-policy) → user → project → local.
# Each is wrapped in block-level HTML scope-header comments that Claude
# Code strips on context injection but humans can read for orientation.
# Diagnostic info (project path) goes to stderr above the content.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Preconditions ──────────────────────────────────────────────────────────

an_initialized_project_in_the_workspace() {
    project_path="$WORKSPACE/project"
    mkdir -p "$project_path"
    exercise_connie init "$project_path" >/dev/null 2>&1
}

an_initialized_project_with_a_workspace_claude_md() {
    an_initialized_project_in_the_workspace
    project_claude_md_content="# Project-scope guidance

This project uses POSIX shell. No bashisms."
    printf '%s' "$project_claude_md_content" >"$project_path/CLAUDE.md"
}

an_initialized_project_with_a_claude_local_md() {
    an_initialized_project_in_the_workspace
    local_claude_md_content="# Personal notes

Sandbox URL: http://localhost:8080"
    printf '%s' "$local_claude_md_content" >"$project_path/CLAUDE.local.md"
}

# ── Stimuli ────────────────────────────────────────────────────────────────

the_user_runs_connie_context() {
    exercise_connie context "$project_path"
}

# ── Assertions ─────────────────────────────────────────────────────────────

the_stdout_contains_the_connie_scope_header() {
    stdout_to_contain "Scope 1/4: Managed-policy"
}

the_stdout_contains_the_user_scope_header() {
    stdout_to_contain "Scope 2/4: User-level"
}

the_stdout_contains_the_project_scope_header() {
    stdout_to_contain "Scope 3/4: Project"
}

the_stdout_contains_the_local_scope_header() {
    stdout_to_contain "Scope 4/4: Local"
}

the_stdout_contains_the_connie_context_body() {
    stdout_to_contain "# Connie Container Environment"
}

the_stdout_contains_the_workspace_claude_md_content() {
    stdout_to_contain "POSIX shell"
}

the_stdout_contains_the_local_claude_md_content() {
    stdout_to_contain "Sandbox URL"
}

the_stdout_contains_the_preview_footer() {
    stdout_to_contain "End of context preview"
}

the_stdout_mentions_the_project_root() {
    # cmd_context writes the project root inside the preview-header HTML
    # comment block on stdout (not stderr) — the header is part of the
    # contextual document so it can travel with a redirected preview.
    stdout_to_contain "Project root: $project_path"
}

the_scope_headers_appear_in_load_order() {
    _h1=$(grep -n "Scope 1/4" "$TEST_STDOUT" | head -1 | cut -d: -f1)
    _h2=$(grep -n "Scope 2/4" "$TEST_STDOUT" | head -1 | cut -d: -f1)
    _h3=$(grep -n "Scope 3/4" "$TEST_STDOUT" | head -1 | cut -d: -f1)
    _h4=$(grep -n "Scope 4/4" "$TEST_STDOUT" | head -1 | cut -d: -f1)
    if [ -z "$_h1" ] || [ -z "$_h2" ] || [ -z "$_h3" ] || [ -z "$_h4" ]; then
        _assertion_failure "all four scope headers present" "lines 1<2<3<4" \
            "actual" "h1=$_h1 h2=$_h2 h3=$_h3 h4=$_h4"
        return 1
    fi
    if [ "$_h1" -lt "$_h2" ] && [ "$_h2" -lt "$_h3" ] && [ "$_h3" -lt "$_h4" ]; then
        return 0
    fi
    _assertion_failure "scope ordering" "1<2<3<4" \
        "actual lines" "1@$_h1 2@$_h2 3@$_h3 4@$_h4"
    return 1
}

# ── Test cases ─────────────────────────────────────────────────────────────

connie_context_succeeds_against_an_initialized_project_test_case() {
    given an_initialized_project_in_the_workspace
    when the_user_runs_connie_context
    expect it_succeeds
}

connie_context_emits_the_managed_policy_scope_header_test_case() {
    given an_initialized_project_in_the_workspace
    when the_user_runs_connie_context
    expect the_stdout_contains_the_connie_scope_header
}

connie_context_emits_the_user_level_scope_header_test_case() {
    given an_initialized_project_in_the_workspace
    when the_user_runs_connie_context
    expect the_stdout_contains_the_user_scope_header
}

connie_context_emits_the_project_scope_header_test_case() {
    given an_initialized_project_in_the_workspace
    when the_user_runs_connie_context
    expect the_stdout_contains_the_project_scope_header
}

connie_context_emits_the_local_scope_header_test_case() {
    given an_initialized_project_in_the_workspace
    when the_user_runs_connie_context
    expect the_stdout_contains_the_local_scope_header
}

connie_context_emits_the_connie_managed_policy_content_under_scope_1_test_case() {
    given an_initialized_project_in_the_workspace
    when the_user_runs_connie_context
    expect the_stdout_contains_the_connie_context_body
}

connie_context_includes_the_workspace_claude_md_content_when_present_test_case() {
    given an_initialized_project_with_a_workspace_claude_md
    when the_user_runs_connie_context
    expect the_stdout_contains_the_workspace_claude_md_content
}

connie_context_includes_the_claude_local_md_content_when_present_test_case() {
    given an_initialized_project_with_a_claude_local_md
    when the_user_runs_connie_context
    expect the_stdout_contains_the_local_claude_md_content
}

connie_context_emits_a_closing_preview_footer_test_case() {
    given an_initialized_project_in_the_workspace
    when the_user_runs_connie_context
    expect the_stdout_contains_the_preview_footer
}

connie_context_emits_scope_headers_in_documented_load_order_test_case() {
    given an_initialized_project_in_the_workspace
    when the_user_runs_connie_context
    expect the_scope_headers_appear_in_load_order
}

connie_context_includes_the_project_root_in_the_preview_header_test_case() {
    given an_initialized_project_in_the_workspace
    when the_user_runs_connie_context
    expect the_stdout_mentions_the_project_root
}
