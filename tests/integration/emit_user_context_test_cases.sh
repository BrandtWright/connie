# tests/integration/emit_user_context_test_cases.sh
#
# Behavior specifications for _emit_user_context — the function that
# concatenates the host's /etc/claude-code/CLAUDE.md (system-wide) and
# ~/.claude/CLAUDE.md (user-specific) into the user-level Claude Code
# context, with block-level HTML source-attribution markers between the
# two contributions. Emits nothing if neither host file exists.
#
# Testing caveat: the test environment runs inside a connie container
# that has /etc/claude-code/CLAUDE.md baked in (connie's own
# managed-policy context). We can't remove or rewrite that file inside
# the sandbox, so we can't fully exercise the "etc absent" branch from
# here. The tests below verify what's observable: the etc marker is
# always present, the user marker and content are emitted when ~/.claude/
# CLAUDE.md exists, and the user marker and content are absent when
# ~/.claude/CLAUDE.md does not.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Preconditions ──────────────────────────────────────────────────────────

a_user_level_claude_md_with_custom_content() {
    mkdir -p "$HOME/.claude"
    user_md_content="# My personal Claude Code preferences

- Prefer 2-space indentation.
- Always run \`make check\` before committing."
    printf '%s' "$user_md_content" > "$HOME/.claude/CLAUDE.md"
}

no_user_level_claude_md() {
    rm -f "$HOME/.claude/CLAUDE.md"
}

# ── Stimuli ────────────────────────────────────────────────────────────────

the_user_context_is_emitted() {
    emitted=$(_emit_user_context)
}

# ── Assertions ─────────────────────────────────────────────────────────────

the_output_contains_the_system_wide_source_marker() {
    expect_contains "$emitted" "<!-- source: /etc/claude-code/CLAUDE.md on host (system-wide) -->"
}

the_output_contains_the_user_source_marker() {
    expect_contains "$emitted" "<!-- source: ~/.claude/CLAUDE.md on host (user) -->"
}

the_output_does_not_contain_the_user_source_marker() {
    case "$emitted" in
        *"<!-- source: ~/.claude/CLAUDE.md"*)
            _assertion_failure "user marker absence" "no user-source HTML comment" \
                               "actual" "output contained the user marker"
            return 1
            ;;
    esac
}

the_output_contains_the_user_claude_md_content() {
    expect_contains "$emitted" "$user_md_content"
}

the_system_wide_marker_precedes_the_user_marker() {
    _etc_pos=$(printf '%s' "$emitted" | grep -n "system-wide" | head -1 | cut -d: -f1)
    _user_pos=$(printf '%s' "$emitted" | grep -n "(user)" | head -1 | cut -d: -f1)
    if [ -z "$_etc_pos" ] || [ -z "$_user_pos" ]; then
        _assertion_failure "both markers present" "etc and user markers found" \
                           "actual" "etc=$_etc_pos user=$_user_pos"
        return 1
    fi
    if [ "$_etc_pos" -ge "$_user_pos" ]; then
        _assertion_failure "ordering" "etc marker before user marker" \
                           "actual" "etc at line $_etc_pos, user at line $_user_pos"
        return 1
    fi
}

# ── Test cases ─────────────────────────────────────────────────────────────

user_context_includes_the_system_wide_marker_for_etc_claude_code_md_test_case() {
    when the_user_context_is_emitted
    expect the_output_contains_the_system_wide_source_marker
}

user_context_includes_the_user_marker_when_the_user_claude_md_exists_test_case() {
    given a_user_level_claude_md_with_custom_content
    when the_user_context_is_emitted
    expect the_output_contains_the_user_source_marker
}

user_context_includes_the_user_claude_md_content_when_present_test_case() {
    given a_user_level_claude_md_with_custom_content
    when the_user_context_is_emitted
    expect the_output_contains_the_user_claude_md_content
}

user_context_omits_the_user_marker_when_the_user_claude_md_does_not_exist_test_case() {
    given no_user_level_claude_md
    when the_user_context_is_emitted
    expect the_output_does_not_contain_the_user_source_marker
}

user_context_emits_the_system_wide_section_before_the_user_section_test_case() {
    given a_user_level_claude_md_with_custom_content
    when the_user_context_is_emitted
    expect the_system_wide_marker_precedes_the_user_marker
}
