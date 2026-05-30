# tests/integration/write_user_context_test_cases.sh
#
# Behavior specifications for _write_user_context — the function that
# installs the assembled user-level Claude Code context (the
# concatenation of /etc/claude-code/CLAUDE.md and ~/.claude/CLAUDE.md
# from the host, with source-attribution markers) into the per-project
# state directory at <state-dir>/.claude/CLAUDE.md. The state directory
# is bind-mounted to ~/.claude/ inside the container, so the file ends
# up at the path Claude Code expects for user-level context.
#
# The function:
#   - Computes destination as <state-dir>/.claude/CLAUDE.md
#   - Removes any pre-existing destination first (so stale content from
#     a prior run can't leak into the new run)
#   - Writes _emit_user_context's output to the destination
#   - Removes the destination if it ended up empty, so the override
#     never leaves a 0-byte file behind when neither host source exists
#
# Testing caveat: this test container has /etc/claude-code/CLAUDE.md
# baked in (connie's own managed-policy context), so _emit_user_context
# always produces non-empty output here. The "remove when both sources
# absent" branch is therefore not directly exercisable in this env;
# the tests below cover what's observable.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Preconditions ──────────────────────────────────────────────────────────

a_project_with_a_pre_created_state_directory() {
    project_path="$WORKSPACE/project"
    mkdir -p "$project_path"
    # _prepare creates this in real connie flow before _write_user_context
    # is called. The redirect inside _write_user_context would fail if
    # this directory doesn't exist.
    state_claude_dir="$(_project_state_dir "$project_path")/.claude"
    mkdir -p "$state_claude_dir"
    destination="$state_claude_dir/CLAUDE.md"
}

a_user_level_claude_md_with_distinctive_content() {
    mkdir -p "$HOME/.claude"
    user_md_content="# This is the user file

Distinctive marker: $$"
    printf '%s' "$user_md_content" > "$HOME/.claude/CLAUDE.md"
}

a_pre_existing_destination_file_with_stale_content() {
    a_project_with_a_pre_created_state_directory
    stale_content="# stale leftover from a previous run"
    printf '%s' "$stale_content" > "$destination"
}

# ── Stimuli ────────────────────────────────────────────────────────────────

the_user_context_is_written() {
    _write_user_context "$project_path"
}

# ── Assertions ─────────────────────────────────────────────────────────────

the_destination_file_was_created() {
    expect_file_to_exist "$destination"
}

the_destination_includes_the_system_wide_source_marker() {
    expect_contains "$(cat "$destination")" "<!-- source: /etc/claude-code/CLAUDE.md on host (system-wide) -->"
}

the_destination_includes_the_user_source_marker() {
    expect_contains "$(cat "$destination")" "<!-- source: ~/.claude/CLAUDE.md on host (user) -->"
}

the_destination_includes_the_user_claude_md_content() {
    expect_contains "$(cat "$destination")" "$user_md_content"
}

the_destination_no_longer_contains_the_stale_content() {
    case "$(cat "$destination")" in
        *"stale leftover"*)
            _assertion_failure "stale content removed" "no '$stale_content'" \
                               "actual" "destination still contained stale text"
            return 1
            ;;
    esac
}

# ── Test cases ─────────────────────────────────────────────────────────────

write_user_context_creates_a_file_at_the_state_directory_claude_md_path_test_case() {
    given a_project_with_a_pre_created_state_directory
    when the_user_context_is_written
    expect the_destination_file_was_created
}

write_user_context_includes_the_system_wide_source_marker_in_the_destination_test_case() {
    given a_project_with_a_pre_created_state_directory
    when the_user_context_is_written
    expect the_destination_includes_the_system_wide_source_marker
}

write_user_context_includes_the_user_source_marker_when_the_user_file_is_present_test_case() {
    given a_project_with_a_pre_created_state_directory
    given a_user_level_claude_md_with_distinctive_content
    when the_user_context_is_written
    expect the_destination_includes_the_user_source_marker
}

write_user_context_includes_the_user_claude_md_content_when_present_test_case() {
    given a_project_with_a_pre_created_state_directory
    given a_user_level_claude_md_with_distinctive_content
    when the_user_context_is_written
    expect the_destination_includes_the_user_claude_md_content
}

write_user_context_overwrites_a_pre_existing_destination_rather_than_appending_test_case() {
    given a_pre_existing_destination_file_with_stale_content
    when the_user_context_is_written
    expect the_destination_no_longer_contains_the_stale_content
}
