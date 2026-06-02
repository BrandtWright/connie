# tests/integration/emit_project_context_test_cases.sh
#
# Behavior specifications for _emit_project_context — the function that
# reads the project-scope Claude Code context from the project root.
# Per the Claude Code memory docs, project context can live at either
# ./CLAUDE.md or ./.claude/CLAUDE.md, and both can coexist (the docs say
# both load into context). The function emits whichever files exist,
# each preceded by a block-level HTML source-attribution marker, and
# emits nothing when neither exists.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Preconditions ──────────────────────────────────────────────────────────

an_empty_project_directory_in_the_workspace() {
    project_path="$WORKSPACE/project"
    mkdir -p "$project_path"
}

a_project_with_a_top_level_claude_md() {
    an_empty_project_directory_in_the_workspace
    main_md_content="# Project instructions

This project uses 4-space indentation."
    printf '%s' "$main_md_content" >"$project_path/CLAUDE.md"
}

a_project_with_a_dot_claude_directory_claude_md() {
    an_empty_project_directory_in_the_workspace
    mkdir -p "$project_path/.claude"
    alt_md_content="# Project instructions (alternate location)

This came from .claude/CLAUDE.md."
    printf '%s' "$alt_md_content" >"$project_path/.claude/CLAUDE.md"
}

a_project_with_both_claude_md_locations() {
    a_project_with_a_top_level_claude_md
    mkdir -p "$project_path/.claude"
    alt_md_content="# Alternate-location notes"
    printf '%s' "$alt_md_content" >"$project_path/.claude/CLAUDE.md"
}

# ── Stimuli ────────────────────────────────────────────────────────────────

the_project_context_is_emitted() {
    emitted=$(_emit_project_context "$project_path")
}

# ── Assertions ─────────────────────────────────────────────────────────────

the_output_is_empty() {
    expect_empty "$emitted"
}

the_output_contains_the_workspace_claude_md_marker() {
    expect_contains "$emitted" "<!-- source: /workspace/CLAUDE.md -->"
}

the_output_contains_the_dot_claude_marker() {
    expect_contains "$emitted" "<!-- source: /workspace/.claude/CLAUDE.md -->"
}

the_output_does_not_contain_the_workspace_claude_md_marker() {
    case "$emitted" in
        *"<!-- source: /workspace/CLAUDE.md -->"*)
            _assertion_failure "workspace marker absence" "no /workspace/CLAUDE.md marker" \
                "actual" "marker present"
            return 1
            ;;
    esac
}

the_output_does_not_contain_the_dot_claude_marker() {
    case "$emitted" in
        *"<!-- source: /workspace/.claude/CLAUDE.md -->"*)
            _assertion_failure "dot-claude marker absence" "no /workspace/.claude/CLAUDE.md marker" \
                "actual" "marker present"
            return 1
            ;;
    esac
}

the_output_contains_the_main_claude_md_content() {
    expect_contains "$emitted" "$main_md_content"
}

the_output_contains_the_alternate_claude_md_content() {
    expect_contains "$emitted" "$alt_md_content"
}

the_main_marker_precedes_the_alt_marker() {
    _main_pos=$(printf '%s' "$emitted" | grep -n "source: /workspace/CLAUDE.md" | head -1 | cut -d: -f1)
    _alt_pos=$(printf '%s' "$emitted" | grep -n "source: /workspace/.claude" | head -1 | cut -d: -f1)
    if [ -z "$_main_pos" ] || [ -z "$_alt_pos" ]; then
        _assertion_failure "both markers present" "main and alt markers found" \
            "actual" "main=$_main_pos alt=$_alt_pos"
        return 1
    fi
    if [ "$_main_pos" -ge "$_alt_pos" ]; then
        _assertion_failure "marker ordering" "main marker before alt marker" \
            "actual" "main at line $_main_pos, alt at line $_alt_pos"
        return 1
    fi
}

# ── Test cases ─────────────────────────────────────────────────────────────

project_context_emits_nothing_when_neither_claude_md_location_exists_test_case() {
    given an_empty_project_directory_in_the_workspace
    when the_project_context_is_emitted
    expect the_output_is_empty
}

project_context_emits_the_top_level_claude_md_when_only_it_exists_test_case() {
    given a_project_with_a_top_level_claude_md
    when the_project_context_is_emitted
    expect the_output_contains_the_workspace_claude_md_marker
    expect the_output_contains_the_main_claude_md_content
    expect the_output_does_not_contain_the_dot_claude_marker
}

project_context_emits_the_dot_claude_claude_md_when_only_it_exists_test_case() {
    given a_project_with_a_dot_claude_directory_claude_md
    when the_project_context_is_emitted
    expect the_output_contains_the_dot_claude_marker
    expect the_output_contains_the_alternate_claude_md_content
    expect the_output_does_not_contain_the_workspace_claude_md_marker
}

project_context_emits_both_files_when_both_locations_exist_test_case() {
    given a_project_with_both_claude_md_locations
    when the_project_context_is_emitted
    expect the_output_contains_the_workspace_claude_md_marker
    expect the_output_contains_the_dot_claude_marker
    expect the_main_marker_precedes_the_alt_marker
}
