# tests/integration/emit_user_context_test_cases.sh
#
# Behavior specifications for _emit_user_context — the function that
# concatenates the host's /etc/claude-code/CLAUDE.md (system-wide) and
# ~/.claude/CLAUDE.md (user-specific) into the user-level Claude Code
# context, with block-level HTML source-attribution markers between the
# two contributions.
#
# The system-wide path is redirected to a sandbox file (via
# $CONNIE_ETC_CLAUDE_MD, set by the harness) so the tests run
# identically inside a connie container (where /etc/claude-code/CLAUDE.md
# is baked in) and on a developer host (where it typically isn't).
# Tests stage the system-wide and user files independently to exercise
# all four combinations.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Preconditions ──────────────────────────────────────────────────────────

neither_host_source_present() {
    # The harness already arranges for $CONNIE_ETC_CLAUDE_MD to point at
    # a sandbox path that doesn't exist; ensure $HOME/.claude/CLAUDE.md
    # is also absent.
    rm -f "$HOME/.claude/CLAUDE.md"
}

only_the_system_wide_source_present() {
    system_md_content="# System-wide Claude Code policy

Distinctive marker: org-wide-rules"
    printf '%s' "$system_md_content" >"$CONNIE_ETC_CLAUDE_MD"
    rm -f "$HOME/.claude/CLAUDE.md"
}

only_the_user_source_present() {
    rm -f "$CONNIE_ETC_CLAUDE_MD"
    mkdir -p "$HOME/.claude"
    user_md_content="# Personal Claude Code preferences

Distinctive marker: my-own-rules"
    printf '%s' "$user_md_content" >"$HOME/.claude/CLAUDE.md"
}

both_host_sources_present() {
    system_md_content="# System-wide policy"
    user_md_content="# Personal preferences"
    printf '%s' "$system_md_content" >"$CONNIE_ETC_CLAUDE_MD"
    mkdir -p "$HOME/.claude"
    printf '%s' "$user_md_content" >"$HOME/.claude/CLAUDE.md"
}

# ── Stimuli ────────────────────────────────────────────────────────────────

the_user_context_is_emitted() {
    emitted=$(_emit_user_context)
}

# ── Assertions ─────────────────────────────────────────────────────────────

the_output_is_empty() {
    expect_empty "$emitted"
}

the_output_contains_the_system_wide_source_marker() {
    expect_contains "$emitted" "<!-- source: /etc/claude-code/CLAUDE.md on host (system-wide) -->"
}

the_output_contains_the_user_source_marker() {
    expect_contains "$emitted" "<!-- source: ~/.claude/CLAUDE.md on host (user) -->"
}

the_output_does_not_contain_the_system_wide_source_marker() {
    case "$emitted" in
        *"<!-- source: /etc/claude-code/CLAUDE.md"*)
            _assertion_failure "system-wide marker absence" "no system-wide marker" \
                "actual" "output contained the system-wide marker"
            return 1
            ;;
    esac
}

the_output_does_not_contain_the_user_source_marker() {
    case "$emitted" in
        *"<!-- source: ~/.claude/CLAUDE.md"*)
            _assertion_failure "user marker absence" "no user-source marker" \
                "actual" "output contained the user marker"
            return 1
            ;;
    esac
}

the_output_contains_the_system_wide_content() {
    expect_contains "$emitted" "$system_md_content"
}

the_output_contains_the_user_content() {
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

emit_user_context_emits_nothing_when_neither_host_source_exists_test_case() {
    given neither_host_source_present
    when the_user_context_is_emitted
    expect the_output_is_empty
}

emit_user_context_includes_the_system_wide_marker_and_content_when_only_etc_exists_test_case() {
    given only_the_system_wide_source_present
    when the_user_context_is_emitted
    expect the_output_contains_the_system_wide_source_marker
    expect the_output_contains_the_system_wide_content
    expect the_output_does_not_contain_the_user_source_marker
}

emit_user_context_includes_the_user_marker_and_content_when_only_user_exists_test_case() {
    given only_the_user_source_present
    when the_user_context_is_emitted
    expect the_output_contains_the_user_source_marker
    expect the_output_contains_the_user_content
    expect the_output_does_not_contain_the_system_wide_source_marker
}

emit_user_context_includes_both_sections_when_both_host_sources_exist_test_case() {
    given both_host_sources_present
    when the_user_context_is_emitted
    expect the_output_contains_the_system_wide_source_marker
    expect the_output_contains_the_user_source_marker
    expect the_output_contains_the_system_wide_content
    expect the_output_contains_the_user_content
}

emit_user_context_emits_the_system_wide_section_before_the_user_section_test_case() {
    given both_host_sources_present
    when the_user_context_is_emitted
    expect the_system_wide_marker_precedes_the_user_marker
}
