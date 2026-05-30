# tests/cli/doctor_test_cases.sh
#
# Behavior specifications for `connie doctor` — the diagnostic
# subcommand that checks required tools, connie installation, base
# image presence, and per-project state, then exits 0 (all pass), or
# 1 (any failed; warnings don't fail).
#
# The harness runs inside this connie container with docker NOT on
# PATH. That means every test here exercises a known-failure path for
# the docker checks — the doctor's job is to report them clearly with
# actionable hints, which is exactly what we assert. The connie-
# installation checks all pass because CONNIE_LIB_DIR points at the
# in-repo src/.
#
# Output goes entirely to stderr (so it doesn't interfere with a
# pipeline that's capturing some other connie subcommand's stdout),
# which means the assertions all target $TEST_STDERR.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Preconditions ──────────────────────────────────────────────────────────

a_fresh_initialized_project() {
    project_path="$WORKSPACE/initialized"
    mkdir -p "$project_path"
    exercise_connie init "$project_path" >/dev/null 2>&1
}

a_target_path_that_is_not_initialized() {
    project_path="$WORKSPACE/uninitialized"
    mkdir -p "$project_path"
}

# ── Stimuli ────────────────────────────────────────────────────────────────

the_user_runs_connie_doctor() {
    exercise_connie doctor
}

the_user_runs_connie_doctor_against_the_project() {
    exercise_connie doctor "$project_path"
}

# Force at least one check to fail in a way that's deterministic
# regardless of the host environment (docker present or not, yq
# present or not). Point CONNIE_LIB_DIR at a path that doesn't
# exist — the install-presence checks (lib dir, defaults.yml,
# Dockerfiles, …) then all fail with their reinstall hints.
#
# Bypasses exercise_connie because that helper hardcodes
# CONNIE_LIB_DIR; we need the override to stick.
the_user_runs_connie_doctor_with_a_broken_install() {
    CONNIE_LIB_DIR="$WORKSPACE/does-not-exist/connie/lib" \
        "$_HARNESS_REPO_ROOT/src/connie" doctor \
        >"$TEST_STDOUT" 2>"$TEST_STDERR"
    # Read by `expect it_fails` and `exit_status_to_be` in assertions
    # downstream — shellcheck can't see across the call boundary.
    # shellcheck disable=SC2034
    actual_exit_status=$?
}

# ── Test cases ─────────────────────────────────────────────────────────────

doctor_emits_a_summary_line_at_the_end_test_case() {
    when the_user_runs_connie_doctor
    # The summary is the last line of doctor output. Its exact wording
    # depends on which checks pass/fail in this environment (docker is
    # absent in the test container so a fail count is guaranteed), but
    # the "Diagnostics:" prefix is invariant.
    expect stderr_to_contain "^Diagnostics:"
}

doctor_reports_section_headers_for_each_check_group_test_case() {
    when the_user_runs_connie_doctor
    # Inseparable claim: each group has a header. If any header
    # disappears, the report becomes a flat list and is much harder
    # to scan.
    expect stderr_to_contain "Required tools:"
    expect stderr_to_contain "Connie installation:"
    expect stderr_to_contain "Base image:"
}

doctor_reports_connie_installation_checks_as_passing_in_a_valid_checkout_test_case() {
    when the_user_runs_connie_doctor
    # The harness sets CONNIE_LIB_DIR to the in-repo src/, so all the
    # install-presence checks should pass. If any of these starts
    # failing, the install path resolution is broken.
    expect stderr_to_contain "ok    lib dir present"
    expect stderr_to_contain "ok    defaults.yml present"
    expect stderr_to_contain "ok    base.Dockerfile present"
    expect stderr_to_contain "ok    docker-compose.yml present"
}

doctor_exits_non_zero_when_a_check_fails_test_case() {
    # The exit-code contract: if any check fails (any of "fail" — not
    # just "warn"), the process exits 1. This is what makes
    # `connie doctor && connie run` a safe gating pattern.
    #
    # Forced via a broken-install fixture rather than depending on the
    # host lacking docker — the previous formulation passed in this
    # container's CI environment but failed against a developer host
    # that has docker installed.
    when the_user_runs_connie_doctor_with_a_broken_install
    expect it_fails
    expect stderr_to_contain "^  fail"
}

doctor_emits_an_actionable_hint_when_a_check_fails_test_case() {
    # Every fail line is followed by an indented hint line pointing
    # at the next concrete action. The hint pattern is what
    # differentiates connie's diagnostics from a flat pass/fail list;
    # this test locks it in. Hint text varies by check, but the
    # broken-install case always produces the "Reinstall" hint.
    when the_user_runs_connie_doctor_with_a_broken_install
    expect stderr_to_contain "^        Reinstall"
}

doctor_includes_a_project_section_when_a_path_is_given_test_case() {
    given a_target_path_that_is_not_initialized
    when the_user_runs_connie_doctor_against_the_project
    # The header includes the resolved absolute path, and an
    # un-initialised project is reported as a warning (not a failure)
    # with an actionable "run connie init" hint. The literal `(` `)`
    # in the section header would be grep -E metacharacters, so match
    # against the leading `Project ` literal instead.
    expect stderr_to_contain "^Project "
    expect stderr_to_contain "warn  no project config yet"
    expect stderr_to_contain "Run 'connie init"
}

doctor_marks_an_initialized_project_config_as_passing_test_case() {
    given a_fresh_initialized_project
    when the_user_runs_connie_doctor_against_the_project
    expect stderr_to_contain "ok    config present"
    expect stderr_to_contain "ok    config parses as YAML"
}

doctor_marks_state_dir_as_passing_when_permissions_are_0700_test_case() {
    # `connie init` creates the state dir with 0700 (defense-in-depth
    # on the OAuth bearer token). The doctor should recognise that
    # and pass — if this test starts failing, either init stopped
    # setting 0700 or the doctor's perm check broke.
    given a_fresh_initialized_project
    when the_user_runs_connie_doctor_against_the_project
    expect stderr_to_contain "ok    state dir mode 700"
}
