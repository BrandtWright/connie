# tests/cli/verbosity_test_cases.sh
#
# Behavior specifications for the -q / --quiet and -v / --verbose
# flags (and their CONNIE_QUIET / CONNIE_VERBOSE env-var equivalents).
#
# What's tested:
#
#   - Default verbosity (no flag, no env): _info messages reach stderr;
#     _detail messages reach stderr; _debug messages stay silent.
#   - -q / --quiet: _info, _detail, and _debug all suppressed; only
#     errors (_die) survive.
#   - -v / --verbose: _info, _detail show as in default; _debug also
#     emitted (currently used to trace docker compose invocations).
#   - The env-var forms (CONNIE_QUIET=1, CONNIE_VERBOSE=1) produce the
#     same behaviour as the matching CLI flags. CLI wins when both are
#     set in opposing directions.
#   - Errors (_die) bypass _VERBOSITY entirely — they reach stderr at
#     every level, including quiet, because suppressing error output
#     would silently break scripts that gate on connie's exit code.
#
# The test subject is `connie init <fresh-dir>` because (a) it doesn't
# need docker, (b) it produces a known set of _info / _detail messages,
# and (c) the fake-home harness wiring means it's safe to run in
# isolation per test.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Preconditions ──────────────────────────────────────────────────────────

a_fresh_target_directory() {
    target_path="$WORKSPACE/project"
    mkdir -p "$target_path"
}

# ── Stimuli ────────────────────────────────────────────────────────────────

the_user_runs_connie_init_default() {
    exercise_connie init "$target_path"
}

the_user_runs_connie_init_with_q_flag() {
    exercise_connie -q init "$target_path"
}

the_user_runs_connie_init_with_quiet_long_flag() {
    exercise_connie --quiet init "$target_path"
}

the_user_runs_connie_init_with_v_flag() {
    exercise_connie -v init "$target_path"
}

the_user_runs_connie_init_with_connie_quiet_env() {
    CONNIE_QUIET=1 exercise_connie init "$target_path"
}

the_user_runs_connie_init_with_connie_verbose_env() {
    CONNIE_VERBOSE=1 exercise_connie init "$target_path"
}

# Conflicting signals: env says quiet, CLI flag says verbose. The flag is
# parsed after the env seed in _main, so the CLI must win.
the_user_runs_connie_init_v_flag_overriding_connie_quiet_env() {
    CONNIE_QUIET=1 exercise_connie -v init "$target_path"
}

# The mirror image: env says verbose, CLI flag says quiet — flag wins.
the_user_runs_connie_init_q_flag_overriding_connie_verbose_env() {
    CONNIE_VERBOSE=1 exercise_connie -q init "$target_path"
}

# Force a _die by pointing at a directory that doesn't exist. The
# verbosity setting should NOT suppress the error message — gating
# scripts on exit code is fine, but silent failures are not.
the_user_runs_connie_init_against_a_missing_dir_quietly() {
    exercise_connie -q init "$WORKSPACE/does/not/exist"
}

# ── Assertions ─────────────────────────────────────────────────────────────

stderr_to_be_empty() {
    if [ ! -s "$TEST_STDERR" ]; then
        return 0
    fi
    _assertion_failure "stderr to be empty" "(nothing)" \
        "stderr was" "$(cat "$TEST_STDERR")"
}

# ── Test cases ─────────────────────────────────────────────────────────────

verbosity_default_emits_info_messages_to_stderr_test_case() {
    given a_fresh_target_directory
    when the_user_runs_connie_init_default
    expect stderr_to_contain "==> Initializing"
}

verbosity_default_emits_detail_messages_to_stderr_test_case() {
    given a_fresh_target_directory
    when the_user_runs_connie_init_default
    # _detail messages are prefixed with four spaces ("    "). Use a
    # distinctive substring from a known _detail line in cmd_init.
    expect stderr_to_contain "    created"
}

verbosity_q_flag_suppresses_info_messages_test_case() {
    given a_fresh_target_directory
    when the_user_runs_connie_init_with_q_flag
    # Nothing emitted via _info should survive. Combined with the
    # "no detail" claim below this proves the _VERBOSITY=0 gate works
    # at the logging-helper level. The error-bypass claim has its own
    # test (verbosity_q_does_not_suppress_errors).
    expect it_succeeds
    expect stderr_to_be_empty
}

verbosity_quiet_long_flag_behaves_like_q_test_case() {
    given a_fresh_target_directory
    when the_user_runs_connie_init_with_quiet_long_flag
    # Inseparable claim: --quiet is just the long-form alias for -q.
    expect it_succeeds
    expect stderr_to_be_empty
}

verbosity_q_does_not_suppress_errors_test_case() {
    # _die ignores _VERBOSITY entirely. Suppressing the error message
    # would break any script that relies on connie's stderr for
    # diagnosis when the exit code is non-zero — exit code alone is
    # too coarse a signal to skip output for.
    given a_fresh_target_directory
    when the_user_runs_connie_init_against_a_missing_dir_quietly
    expect it_fails
    expect stderr_to_contain "error:"
}

verbosity_v_flag_keeps_info_and_detail_visible_test_case() {
    given a_fresh_target_directory
    when the_user_runs_connie_init_with_v_flag
    # _info and _detail remain visible at verbose level (they're
    # visible at every level >= 1). The verbose level's additional
    # contribution is enabling _debug — but cmd_init has no _debug
    # calls, so we only check that the existing output still shows.
    expect stderr_to_contain "==> Initializing"
    expect stderr_to_contain "    created"
}

verbosity_connie_quiet_env_var_matches_q_flag_test_case() {
    given a_fresh_target_directory
    when the_user_runs_connie_init_with_connie_quiet_env
    expect it_succeeds
    expect stderr_to_be_empty
}

verbosity_connie_verbose_env_var_matches_v_flag_test_case() {
    given a_fresh_target_directory
    when the_user_runs_connie_init_with_connie_verbose_env
    expect stderr_to_contain "==> Initializing"
    expect stderr_to_contain "    created"
}

verbosity_cli_v_flag_overrides_connie_quiet_env_test_case() {
    given a_fresh_target_directory
    when the_user_runs_connie_init_v_flag_overriding_connie_quiet_env
    # CLI flag is parsed after the env seed, so -v wins: info still shows.
    expect stderr_to_contain "==> Initializing"
}

verbosity_cli_q_flag_overrides_connie_verbose_env_test_case() {
    given a_fresh_target_directory
    when the_user_runs_connie_init_q_flag_overriding_connie_verbose_env
    expect it_succeeds
    expect stderr_to_be_empty
}
