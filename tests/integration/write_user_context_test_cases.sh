# tests/integration/write_user_context_test_cases.sh
#
# Behavior specifications for _write_user_context — the function that
# installs the assembled user-level Claude Code context into the
# per-project state directory at <state-dir>/.claude/CLAUDE.md. The
# state directory is bind-mounted to ~/.claude/ inside the container, so
# the file ends up where Claude Code expects the user-level context to
# live.
#
# The function:
#   - Computes destination as <state-dir>/.claude/CLAUDE.md
#   - Removes any pre-existing destination first (so stale content from
#     a prior run can't leak into the new run)
#   - Writes _emit_user_context's output to the destination
#   - Removes the destination if it ended up empty, so the override
#     never leaves a 0-byte file behind when neither host source exists
#
# The system-wide source path used by _emit_user_context is redirected
# to a sandbox file (via $CONNIE_ETC_CLAUDE_MD, set by the harness) so
# tests can stage both possible host sources independently and exercise
# the empty-then-remove branch without needing root access to /etc/.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Preconditions ──────────────────────────────────────────────────────────

a_project_with_a_pre_created_state_directory() {
    project_path="$WORKSPACE/project"
    mkdir -p "$project_path"
    # In production flow this is created by _prepare before
    # _write_user_context is called. The redirect inside the function
    # would fail if the parent didn't exist.
    state_claude_dir="$(_project_state_dir "$project_path")/.claude"
    mkdir -p "$state_claude_dir"
    destination="$state_claude_dir/CLAUDE.md"
    # Default: neither host source exists.
    rm -f "$CONNIE_ETC_CLAUDE_MD" "$HOME/.claude/CLAUDE.md"
}

a_system_wide_claude_md_with_distinctive_content() {
    system_md_content="# System-wide: org-wide marker"
    printf '%s' "$system_md_content" > "$CONNIE_ETC_CLAUDE_MD"
}

a_user_level_claude_md_with_distinctive_content() {
    mkdir -p "$HOME/.claude"
    user_md_content="# User-level: my marker"
    printf '%s' "$user_md_content" > "$HOME/.claude/CLAUDE.md"
}

a_pre_existing_destination_file_with_stale_content() {
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

the_destination_file_was_not_created() {
    if [ ! -e "$destination" ]; then
        return 0
    fi
    _assertion_failure "destination absent" "no file at $destination" \
                       "actual" "file present, $(wc -c < "$destination") bytes"
    return 1
}

the_destination_contains_the_system_wide_marker() {
    expect_contains "$(cat "$destination")" "<!-- source: /etc/claude-code/CLAUDE.md on host (system-wide) -->"
}

the_destination_contains_the_user_marker() {
    expect_contains "$(cat "$destination")" "<!-- source: ~/.claude/CLAUDE.md on host (user) -->"
}

the_destination_contains_the_system_wide_content() {
    expect_contains "$(cat "$destination")" "$system_md_content"
}

the_destination_contains_the_user_content() {
    expect_contains "$(cat "$destination")" "$user_md_content"
}

the_destination_no_longer_contains_the_stale_content() {
    if [ ! -e "$destination" ]; then
        # Treated as absence of stale content too — file removed.
        return 0
    fi
    case "$(cat "$destination")" in
        *"stale leftover"*)
            _assertion_failure "stale content gone" "no stale fragments" \
                               "actual" "stale fragment present in $destination"
            return 1
            ;;
    esac
}

# ── Test cases ─────────────────────────────────────────────────────────────

write_user_context_does_not_create_a_file_when_neither_host_source_exists_test_case() {
    given a_project_with_a_pre_created_state_directory
    when the_user_context_is_written
    expect the_destination_file_was_not_created
}

write_user_context_creates_a_file_with_the_system_wide_content_when_only_etc_exists_test_case() {
    given a_project_with_a_pre_created_state_directory
    given a_system_wide_claude_md_with_distinctive_content
    when the_user_context_is_written
    expect the_destination_file_was_created
    expect the_destination_contains_the_system_wide_marker
    expect the_destination_contains_the_system_wide_content
}

write_user_context_creates_a_file_with_the_user_content_when_only_the_user_file_exists_test_case() {
    given a_project_with_a_pre_created_state_directory
    given a_user_level_claude_md_with_distinctive_content
    when the_user_context_is_written
    expect the_destination_file_was_created
    expect the_destination_contains_the_user_marker
    expect the_destination_contains_the_user_content
}

write_user_context_combines_both_sources_in_the_destination_when_both_exist_test_case() {
    given a_project_with_a_pre_created_state_directory
    given a_system_wide_claude_md_with_distinctive_content
    given a_user_level_claude_md_with_distinctive_content
    when the_user_context_is_written
    expect the_destination_contains_the_system_wide_content
    expect the_destination_contains_the_user_content
}

write_user_context_removes_a_stale_destination_when_no_sources_currently_exist_test_case() {
    # The interesting case: the project HAD a user-context file from a
    # prior run, but neither host source exists now. The function should
    # remove the stale file rather than leaving inconsistent content
    # behind.
    given a_project_with_a_pre_created_state_directory
    given a_pre_existing_destination_file_with_stale_content
    when the_user_context_is_written
    expect the_destination_file_was_not_created
}

write_user_context_overwrites_a_pre_existing_destination_rather_than_appending_test_case() {
    given a_project_with_a_pre_created_state_directory
    given a_pre_existing_destination_file_with_stale_content
    given a_user_level_claude_md_with_distinctive_content
    when the_user_context_is_written
    expect the_destination_no_longer_contains_the_stale_content
    expect the_destination_contains_the_user_content
}
