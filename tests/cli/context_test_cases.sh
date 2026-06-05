# tests/cli/context_test_cases.sh
#
# CLI-level tests for `connie context` against an initialized project.
# Complements the error-path test (context_rejects_an_uninitialized_project)
# in tests/cli/usage_test_cases.sh.
#
# `connie context` prints — to stdout — exactly the payload connie appends to
# Claude's system prompt at launch (--append-system-prompt): the generated
# application scope, plus the machine/user/project context.md scopes that
# exist. A one-line diagnostic header goes to stderr, so the stdout is a
# clean, redirectable copy of the payload. The project's own CLAUDE.md is
# loaded by Claude separately and is NOT read or shown here.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Preconditions ──────────────────────────────────────────────────────────

an_initialized_project_in_the_workspace() {
    project_path="$WORKSPACE/project"
    mkdir -p "$project_path"
    exercise_connie init "$project_path" >/dev/null 2>&1
}

# A user-scope context.md beside the user config.
an_initialized_project_with_a_user_context() {
    an_initialized_project_in_the_workspace
    mkdir -p "$CONFIG_DIR"
    printf '%s\n' "User marker: prefers-terse-answers" >"$USER_CONTEXT"
}

# connie's own per-project context (under the config dir — NOT in the repo).
an_initialized_project_with_a_connie_project_context() {
    an_initialized_project_in_the_workspace
    _proj_ctx="$CONFIG_DIR/projects/$(_project_slug "$project_path")/context.md"
    mkdir -p "$(dirname "$_proj_ctx")"
    printf '%s\n' "Project marker: deploy-on-fridays" >"$_proj_ctx"
}

# A CLAUDE.md checked into the project itself. connie must NOT read it.
an_initialized_project_with_a_repo_claude_md() {
    an_initialized_project_in_the_workspace
    printf '%s\n' "Repo marker: this-is-in-source-control" >"$project_path/CLAUDE.md"
}

# ── Stimuli ────────────────────────────────────────────────────────────────

the_user_runs_connie_context() {
    exercise_connie context "$project_path"
}

# ── Assertions ─────────────────────────────────────────────────────────────

the_stdout_does_not_contain() {
    if grep -E -q -- "$1" "$TEST_STDOUT"; then
        _assertion_failure "stdout to NOT contain" "$1" \
            "stdout was" "$(cat "$TEST_STDOUT")"
        return 1
    fi
}

# ── Test cases ─────────────────────────────────────────────────────────────

connie_context_succeeds_against_an_initialized_project_test_case() {
    given an_initialized_project_in_the_workspace
    when the_user_runs_connie_context
    expect it_succeeds
}

connie_context_prints_the_application_scope_to_stdout_test_case() {
    given an_initialized_project_in_the_workspace
    when the_user_runs_connie_context
    expect stdout_to_contain "# Connie Container Environment"
}

connie_context_writes_its_diagnostic_header_to_stderr_not_stdout_test_case() {
    given an_initialized_project_in_the_workspace
    when the_user_runs_connie_context
    # The label goes to stderr so `connie context > out.md` captures only the
    # payload Claude receives.
    expect stderr_to_contain "append-system-prompt"
    expect the_stdout_does_not_contain "append-system-prompt"
}

connie_context_includes_the_user_scope_when_present_test_case() {
    given an_initialized_project_with_a_user_context
    when the_user_runs_connie_context
    expect stdout_to_contain "## User Context"
    expect stdout_to_contain "prefers-terse-answers"
}

connie_context_includes_the_connie_project_scope_when_present_test_case() {
    given an_initialized_project_with_a_connie_project_context
    when the_user_runs_connie_context
    expect stdout_to_contain "## Project Context"
    expect stdout_to_contain "deploy-on-fridays"
}

connie_context_does_not_read_the_projects_own_claude_md_test_case() {
    given an_initialized_project_with_a_repo_claude_md
    when the_user_runs_connie_context
    # The invariant: connie never reads or shows the repo's CLAUDE.md. Claude
    # loads it natively; connie's context rides alongside via the system prompt.
    expect the_stdout_does_not_contain "this-is-in-source-control"
}
