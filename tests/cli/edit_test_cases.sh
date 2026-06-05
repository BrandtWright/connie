# tests/cli/edit_test_cases.sh
#
# CLI-level tests for `connie edit-config` and `connie edit-context`, which
# open a file in the user's $EDITOR. Each has two scopes, mirroring the show
# commands (config/context) and the [dir] grammar:
#   connie edit-config  [dir] / --user   a config file (YAML, validated)
#   connie edit-context [dir] / --user   a context file (markdown, no validation)
# edit-config requires an initialized project (or scaffolds the user config);
# edit-context opens an empty file when absent and drops it again if left empty.
# The harness redirects HOME/XDG_* into a per-test sandbox, so preconditions
# can init projects and seed files, and the real binary acts on the isolated
# paths via exercise_connie. No Docker required.
#
# Fake $EDITOR note: the container's $TMPDIR is mounted noexec, so an editor
# stub cannot rely on its exec bit. Each stub is therefore invoked as
# `sh <script>` (which reads the file instead of execve'ing it). connie
# word-splits $EDITOR, so "sh <path>" arrives as two argv entries, and the
# stub's $1 is the file path connie passes it.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Preconditions: projects ────────────────────────────────────────────────

an_initialized_project() {
    project_path="$WORKSPACE/project"
    mkdir -p "$project_path"
    exercise_connie init "$project_path" >/dev/null 2>&1
}

an_uninitialized_project() {
    uninitialized_path="$WORKSPACE/blank"
    mkdir -p "$uninitialized_path"
}

a_user_config_with_a_sentinel() {
    # A pre-existing, valid user config to prove --user never clobbers it.
    mkdir -p "$CONFIG_DIR"
    printf 'env:\n  SENTINEL: marker\n' >"$USER_CONFIG"
}

# ── Preconditions: fake editors ────────────────────────────────────────────

# Write a fake $EDITOR that saves the given content to the file connie passes
# it. $1 is a printf format whose \n escapes become newlines, written verbatim
# ('' yields an empty file). The stub is invoked as `sh <stub>` (see the noexec
# note above); its own $1 is the path, and printf's `--` keeps leading-dash
# content (a YAML sequence) treated as data.
_install_editor_stub() {
    _stub="$WORKSPACE/fake-editor.sh"
    printf "printf -- '%s' > \"\$1\"\n" "$1" >"$_stub"
    EDITOR="sh $_stub"
    export EDITOR
}

a_noop_editor() {
    # `true` leaves the file untouched and exits 0.
    EDITOR=true
    export EDITOR
}

a_failing_editor() {
    EDITOR=false
    export EDITOR
}

an_editor_that_saves_a_valid_config() {
    _install_editor_stub 'resources:\n  memory: 2g\n'
}

an_editor_that_saves_an_empty_config() {
    _install_editor_stub ''
}

an_editor_that_saves_an_unknown_key() {
    _install_editor_stub 'resorces:\n  memory: 2g\n'
}

an_editor_that_saves_a_top_level_scalar() {
    _install_editor_stub 'just-a-string\n'
}

an_editor_that_saves_a_top_level_sequence() {
    _install_editor_stub '- a\n- b\n'
}

an_editor_that_saves_context_text() {
    _install_editor_stub 'Be terse. Prefer POSIX sh.\n'
}

an_editor_whose_visual_saves_and_editor_fails() {
    # VISUAL writes a valid config; EDITOR would fail. Success proves connie
    # consulted VISUAL first.
    an_editor_that_saves_a_valid_config
    VISUAL="$EDITOR"
    EDITOR=false
    export VISUAL EDITOR
}

# ── Stimuli ────────────────────────────────────────────────────────────────

the_user_edits_the_project_config_by_path() {
    exercise_connie edit-config "$project_path"
}

the_user_edits_the_current_project_config() {
    cd "$project_path" || return 1
    exercise_connie edit-config
}

the_user_edits_an_uninitialized_project_config() {
    exercise_connie edit-config "$uninitialized_path"
}

the_user_edits_the_user_config() {
    exercise_connie edit-config --user
}

the_user_edits_the_user_config_with_a_stray_directory() {
    exercise_connie edit-config --user "$WORKSPACE/somewhere"
}

the_user_edits_the_project_context_by_path() {
    exercise_connie edit-context "$project_path"
}

the_user_edits_an_uninitialized_project_context() {
    exercise_connie edit-context "$uninitialized_path"
}

the_user_edits_the_user_context() {
    exercise_connie edit-context --user
}

the_user_edits_the_user_context_with_a_stray_directory() {
    exercise_connie edit-context --user "$WORKSPACE/somewhere"
}

# ── Assertions ─────────────────────────────────────────────────────────────

no_warning_on_stderr() {
    grep -qi 'warning' "$TEST_STDERR" || return 0
    _assertion_failure "stderr to contain" "no warning" \
        "stderr was" "$(cat "$TEST_STDERR")"
}

the_user_config_to_keep_the_sentinel() {
    grep -q 'SENTINEL' "$USER_CONFIG" 2>/dev/null && return 0
    _assertion_failure "user config to retain" "SENTINEL" \
        "config was" "$(cat "$USER_CONFIG" 2>/dev/null)"
}

_project_context_path() {
    printf '%s/projects/%s/context.md' "$CONFIG_DIR" "$(_project_slug "$project_path")"
}

the_project_context_to_contain() {
    _ctx=$(_project_context_path)
    grep -q "$1" "$_ctx" 2>/dev/null && return 0
    _assertion_failure "project context to contain" "$1" \
        "context was" "$(cat "$_ctx" 2>/dev/null || printf '(absent)')"
}

the_project_context_to_be_absent() {
    _ctx=$(_project_context_path)
    [ ! -f "$_ctx" ] && return 0
    _assertion_failure "project context to be absent" "(no file)" \
        "but it existed with" "$(cat "$_ctx")"
}

the_user_context_to_contain() {
    grep -q "$1" "$USER_CONTEXT" 2>/dev/null && return 0
    _assertion_failure "user context to contain" "$1" \
        "context was" "$(cat "$USER_CONTEXT" 2>/dev/null || printf '(absent)')"
}

# ── Test cases: edit-config, project scope ─────────────────────────────────

connie_edit_config_rejects_an_uninitialized_project_with_an_init_hint_test_case() {
    given an_uninitialized_project
    when the_user_edits_an_uninitialized_project_config
    expect it_fails
    expect stderr_to_contain "connie init"
}

connie_edit_config_opens_an_initialized_project_by_path_test_case() {
    given an_initialized_project
    given a_noop_editor
    when the_user_edits_the_project_config_by_path
    expect it_succeeds
}

connie_edit_config_opens_the_current_project_directory_test_case() {
    given an_initialized_project
    given a_noop_editor
    when the_user_edits_the_current_project_config
    expect it_succeeds
}

# ── Test cases: edit-config, user scope ────────────────────────────────────

connie_edit_config_user_creates_the_user_config_when_absent_test_case() {
    given a_noop_editor
    when the_user_edits_the_user_config
    expect it_succeeds
    expect expect_directory_to_exist "$CONFIG_DIR"
    expect expect_file_to_exist "$USER_CONFIG"
}

connie_edit_config_user_does_not_clobber_an_existing_config_test_case() {
    given a_user_config_with_a_sentinel
    given a_noop_editor
    when the_user_edits_the_user_config
    expect it_succeeds
    expect the_user_config_to_keep_the_sentinel
}

connie_edit_config_user_rejects_a_stray_directory_argument_test_case() {
    given a_noop_editor
    when the_user_edits_the_user_config_with_a_stray_directory
    expect it_fails
    expect stderr_to_contain "takes no directory"
}

# ── Test cases: edit-config, editor resolution ─────────────────────────────

connie_edit_config_prefers_visual_over_editor_test_case() {
    given an_initialized_project
    given an_editor_whose_visual_saves_and_editor_fails
    when the_user_edits_the_project_config_by_path
    expect it_succeeds
}

connie_edit_config_propagates_a_failing_editor_test_case() {
    given an_initialized_project
    given a_failing_editor
    when the_user_edits_the_project_config_by_path
    expect it_fails
}

# ── Test cases: edit-config, post-save validation ──────────────────────────

connie_edit_config_accepts_a_valid_config_without_warnings_test_case() {
    given an_initialized_project
    given an_editor_that_saves_a_valid_config
    when the_user_edits_the_project_config_by_path
    expect it_succeeds
    expect no_warning_on_stderr
}

connie_edit_config_accepts_an_empty_config_test_case() {
    given an_initialized_project
    given an_editor_that_saves_an_empty_config
    when the_user_edits_the_project_config_by_path
    expect it_succeeds
}

connie_edit_config_warns_about_an_unknown_config_key_test_case() {
    given an_initialized_project
    given an_editor_that_saves_an_unknown_key
    when the_user_edits_the_project_config_by_path
    expect it_succeeds
    expect stderr_to_contain "unknown config key"
}

connie_edit_config_rejects_a_top_level_scalar_test_case() {
    given an_initialized_project
    given an_editor_that_saves_a_top_level_scalar
    when the_user_edits_the_project_config_by_path
    expect it_fails
}

connie_edit_config_rejects_a_top_level_sequence_test_case() {
    given an_initialized_project
    given an_editor_that_saves_a_top_level_sequence
    when the_user_edits_the_project_config_by_path
    expect it_fails
}

# ── Test cases: edit-context ───────────────────────────────────────────────

connie_edit_context_rejects_an_uninitialized_project_with_an_init_hint_test_case() {
    given an_uninitialized_project
    when the_user_edits_an_uninitialized_project_context
    expect it_fails
    expect stderr_to_contain "connie init"
}

connie_edit_context_saves_project_context_text_test_case() {
    given an_initialized_project
    given an_editor_that_saves_context_text
    when the_user_edits_the_project_context_by_path
    expect it_succeeds
    expect the_project_context_to_contain "Be terse"
}

connie_edit_context_drops_an_empty_project_context_test_case() {
    given an_initialized_project
    given a_noop_editor
    when the_user_edits_the_project_context_by_path
    # An untouched (empty) context contributes nothing, so connie drops the
    # 0-byte file rather than leave clutter.
    expect it_succeeds
    expect the_project_context_to_be_absent
}

connie_edit_context_does_not_validate_markdown_test_case() {
    given an_initialized_project
    given an_editor_that_saves_a_top_level_scalar
    # The same content edit-config rejects as a top-level scalar is fine here:
    # context is freeform markdown, not validated.
    when the_user_edits_the_project_context_by_path
    expect it_succeeds
    expect the_project_context_to_contain "just-a-string"
}

connie_edit_context_user_saves_the_user_context_test_case() {
    given an_editor_that_saves_context_text
    when the_user_edits_the_user_context
    expect it_succeeds
    expect the_user_context_to_contain "Be terse"
}

connie_edit_context_user_rejects_a_stray_directory_argument_test_case() {
    given a_noop_editor
    when the_user_edits_the_user_context_with_a_stray_directory
    expect it_fails
    expect stderr_to_contain "takes no directory"
}
