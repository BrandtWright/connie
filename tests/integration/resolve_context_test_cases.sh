# tests/integration/resolve_context_test_cases.sh
#
# Behavior specifications for _resolve_context — the function that assembles
# the context payload connie appends to Claude's system prompt (via
# --append-system-prompt). It concatenates, in order:
#
#   1. the generated application scope (always present)
#   2. machine context  ($SYSTEM_CONTEXT)             if the file exists
#   3. user context     ($USER_CONTEXT)               if the file exists
#   4. project context  (<config>/projects/<slug>/…)  if the file exists
#
# Each optional scope appears under a "## … Context" heading and only when
# its source file exists and is non-empty. The harness points the XDG dirs
# at the per-test sandbox, so $SYSTEM_CONTEXT/$USER_CONTEXT and the project
# path resolve under $WORKSPACE.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Preconditions ──────────────────────────────────────────────────────────

a_project_and_merged_config() {
    project_path="$WORKSPACE/project"
    mkdir -p "$project_path"
    merged_file="$WORKSPACE/merged.yml"
    cp "$_HARNESS_REPO_ROOT/src/config/defaults.yml" "$merged_file"
    # Start from a clean slate so a prior fixture can't leak a scope in.
    project_context_file="$CONFIG_DIR/projects/$(_project_slug "$project_path")/context.md"
    rm -f "$SYSTEM_CONTEXT" "$USER_CONTEXT" "$project_context_file"
}

a_machine_context_file() {
    mkdir -p "$(dirname "$SYSTEM_CONTEXT")"
    machine_context_content="Machine marker: gpu-box"
    printf '%s\n' "$machine_context_content" >"$SYSTEM_CONTEXT"
}

a_user_context_file() {
    mkdir -p "$(dirname "$USER_CONTEXT")"
    user_context_content="User marker: be-terse"
    printf '%s\n' "$user_context_content" >"$USER_CONTEXT"
}

a_project_context_file() {
    mkdir -p "$(dirname "$project_context_file")"
    project_context_content="Project marker: ship-it"
    printf '%s\n' "$project_context_content" >"$project_context_file"
}

an_empty_user_context_file() {
    mkdir -p "$(dirname "$USER_CONTEXT")"
    : >"$USER_CONTEXT"
}

# ── Stimuli ────────────────────────────────────────────────────────────────

the_context_is_resolved() {
    resolved=$(_resolve_context "$project_path" "$merged_file")
}

# ── Assertions ─────────────────────────────────────────────────────────────

the_resolved_context_contains() {
    expect_contains "$resolved" "$1"
}

the_resolved_context_does_not_contain() {
    case "$resolved" in
        *"$1"*)
            _assertion_failure "absence of" "$1" \
                "actual" "the payload contained it"
            return 1
            ;;
    esac
}

the_scopes_appear_in_application_machine_user_project_order() {
    _app=$(printf '%s\n' "$resolved" | grep -n "Connie Container Environment" | head -1 | cut -d: -f1)
    _mac=$(printf '%s\n' "$resolved" | grep -n "## Machine Context" | head -1 | cut -d: -f1)
    _usr=$(printf '%s\n' "$resolved" | grep -n "## User Context" | head -1 | cut -d: -f1)
    _prj=$(printf '%s\n' "$resolved" | grep -n "## Project Context" | head -1 | cut -d: -f1)
    if [ -z "$_app" ] || [ -z "$_mac" ] || [ -z "$_usr" ] || [ -z "$_prj" ]; then
        _assertion_failure "all four scopes present" "app/machine/user/project" \
            "actual lines" "app=$_app machine=$_mac user=$_usr project=$_prj"
        return 1
    fi
    if [ "$_app" -lt "$_mac" ] && [ "$_mac" -lt "$_usr" ] && [ "$_usr" -lt "$_prj" ]; then
        return 0
    fi
    _assertion_failure "scope order app<machine<user<project" "ascending" \
        "actual lines" "app@$_app machine@$_mac user@$_usr project@$_prj"
    return 1
}

# ── Test cases ─────────────────────────────────────────────────────────────

resolve_context_always_includes_the_application_scope_test_case() {
    given a_project_and_merged_config
    when the_context_is_resolved
    expect the_resolved_context_contains "# Connie Container Environment"
}

resolve_context_omits_optional_scopes_when_their_files_are_absent_test_case() {
    given a_project_and_merged_config
    when the_context_is_resolved
    # Only the application scope is present; no optional headings.
    expect the_resolved_context_does_not_contain "## Machine Context"
    expect the_resolved_context_does_not_contain "## User Context"
    expect the_resolved_context_does_not_contain "## Project Context"
}

resolve_context_includes_the_machine_scope_when_present_test_case() {
    given a_project_and_merged_config
    given a_machine_context_file
    when the_context_is_resolved
    expect the_resolved_context_contains "## Machine Context"
    expect the_resolved_context_contains "Machine marker: gpu-box"
}

resolve_context_includes_the_user_scope_when_present_test_case() {
    given a_project_and_merged_config
    given a_user_context_file
    when the_context_is_resolved
    expect the_resolved_context_contains "## User Context"
    expect the_resolved_context_contains "User marker: be-terse"
}

resolve_context_includes_the_project_scope_when_present_test_case() {
    given a_project_and_merged_config
    given a_project_context_file
    when the_context_is_resolved
    expect the_resolved_context_contains "## Project Context"
    expect the_resolved_context_contains "Project marker: ship-it"
}

resolve_context_orders_the_scopes_application_machine_user_project_test_case() {
    given a_project_and_merged_config
    given a_machine_context_file
    given a_user_context_file
    given a_project_context_file
    when the_context_is_resolved
    expect the_scopes_appear_in_application_machine_user_project_order
}

resolve_context_omits_an_empty_optional_context_file_test_case() {
    given a_project_and_merged_config
    given an_empty_user_context_file
    when the_context_is_resolved
    # An existing-but-empty file contributes nothing — no heading.
    expect the_resolved_context_does_not_contain "## User Context"
}
