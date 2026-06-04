# tests/cli/edit_test_cases.sh
#
# CLI-level tests for `connie edit`, which opens a config file in the user's
# $EDITOR and validates what they save. Two scopes:
#   connie edit [dir]   a project's config (must be initialized first)
#   connie edit --user  the user-global config (created from a template if
#                       absent)
# The harness redirects HOME/XDG_* into a per-test sandbox, so preconditions
# can init projects and seed the user config, and the real binary acts on the
# isolated paths via exercise_connie. No Docker required.
#
# Fake $EDITOR note: the container's $TMPDIR is mounted noexec, so an editor
# stub cannot rely on its exec bit. Each stub is therefore invoked as
# `sh <script>` (which reads the file instead of execve'ing it). connie
# word-splits $EDITOR, so "sh <path>" arrives as two argv entries, and the
# stub's $1 is the config path connie passes it.

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

# Write a fake $EDITOR that saves the given YAML to the file connie passes it.
# $1 is a printf format whose \n escapes become newlines, written verbatim as
# the new config ('' yields an empty → null config). The stub is invoked as
# `sh <stub>` (see the noexec note above); its own $1 is the config path, and
# printf's `--` keeps leading-dash content (a YAML sequence) treated as data.
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

an_editor_whose_visual_saves_and_editor_fails() {
    # VISUAL writes a valid config; EDITOR would fail. Success proves connie
    # consulted VISUAL first.
    an_editor_that_saves_a_valid_config
    VISUAL="$EDITOR"
    EDITOR=false
    export VISUAL EDITOR
}

# ── Stimuli ────────────────────────────────────────────────────────────────

the_user_edits_the_project_by_path() {
    exercise_connie edit "$project_path"
}

the_user_edits_the_current_directory() {
    cd "$project_path" || return 1
    exercise_connie edit
}

the_user_edits_an_uninitialized_project() {
    exercise_connie edit "$uninitialized_path"
}

the_user_edits_the_user_config() {
    exercise_connie edit --user
}

the_user_edits_the_user_config_with_a_stray_directory() {
    exercise_connie edit --user "$WORKSPACE/somewhere"
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

# ── Test cases: project scope ──────────────────────────────────────────────

connie_edit_rejects_an_uninitialized_project_with_an_init_hint_test_case() {
    given an_uninitialized_project
    when the_user_edits_an_uninitialized_project
    expect it_fails
    expect stderr_to_contain "connie init"
}

connie_edit_opens_an_initialized_project_by_path_test_case() {
    given an_initialized_project
    given a_noop_editor
    when the_user_edits_the_project_by_path
    expect it_succeeds
}

connie_edit_opens_the_current_project_directory_test_case() {
    given an_initialized_project
    given a_noop_editor
    when the_user_edits_the_current_directory
    expect it_succeeds
}

# ── Test cases: user scope ─────────────────────────────────────────────────

connie_edit_user_creates_the_user_config_when_absent_test_case() {
    given a_noop_editor
    when the_user_edits_the_user_config
    expect it_succeeds
    expect expect_directory_to_exist "$CONFIG_DIR"
    expect expect_file_to_exist "$USER_CONFIG"
}

connie_edit_user_does_not_clobber_an_existing_config_test_case() {
    given a_user_config_with_a_sentinel
    given a_noop_editor
    when the_user_edits_the_user_config
    expect it_succeeds
    expect the_user_config_to_keep_the_sentinel
}

connie_edit_user_rejects_a_stray_directory_argument_test_case() {
    given a_noop_editor
    when the_user_edits_the_user_config_with_a_stray_directory
    expect it_fails
    expect stderr_to_contain "takes no directory"
}

# ── Test cases: editor resolution ──────────────────────────────────────────

connie_edit_prefers_visual_over_editor_test_case() {
    given an_initialized_project
    given an_editor_whose_visual_saves_and_editor_fails
    when the_user_edits_the_project_by_path
    expect it_succeeds
}

connie_edit_propagates_a_failing_editor_test_case() {
    given an_initialized_project
    given a_failing_editor
    when the_user_edits_the_project_by_path
    expect it_fails
}

# ── Test cases: post-save validation ───────────────────────────────────────

connie_edit_accepts_a_valid_config_without_warnings_test_case() {
    given an_initialized_project
    given an_editor_that_saves_a_valid_config
    when the_user_edits_the_project_by_path
    expect it_succeeds
    expect no_warning_on_stderr
}

connie_edit_accepts_an_empty_config_test_case() {
    given an_initialized_project
    given an_editor_that_saves_an_empty_config
    when the_user_edits_the_project_by_path
    expect it_succeeds
}

connie_edit_warns_about_an_unknown_config_key_test_case() {
    given an_initialized_project
    given an_editor_that_saves_an_unknown_key
    when the_user_edits_the_project_by_path
    expect it_succeeds
    expect stderr_to_contain "unknown config key"
}

connie_edit_rejects_a_top_level_scalar_test_case() {
    given an_initialized_project
    given an_editor_that_saves_a_top_level_scalar
    when the_user_edits_the_project_by_path
    expect it_fails
}

connie_edit_rejects_a_top_level_sequence_test_case() {
    given an_initialized_project
    given an_editor_that_saves_a_top_level_sequence
    when the_user_edits_the_project_by_path
    expect it_fails
}
