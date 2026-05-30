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

doctor_exits_non_zero_when_docker_is_absent_test_case() {
    # Inside the test harness's connie container, docker isn't
    # installed. This SHOULD be a failure (not a warning) — without
    # docker, `connie run` cannot work at all, and reporting it as
    # "fine, just a warning" would mislead.
    when the_user_runs_connie_doctor
    expect it_fails
    expect stderr_to_contain "fail  docker on PATH"
}

doctor_includes_an_actionable_hint_under_each_failure_test_case() {
    # The hint isn't decoration — it's the difference between a user
    # knowing how to fix the problem and falling back to a search
    # engine. The docker fail must point at the install docs.
    when the_user_runs_connie_doctor
    expect stderr_to_contain "Install Docker Engine"
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
