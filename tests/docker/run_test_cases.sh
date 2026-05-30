# tests/docker/run_test_cases.sh
#
# Behavior specifications for `connie run` — the subcommand that builds
# (if needed) and starts the per-project workspace container. This is
# where the security model documented in DESIGN.md actually materialises
# at runtime: non-root user, read-only root filesystem, /workspace
# bind-mounted from the project directory, /tmp as tmpfs, env vars
# forwarded, and so on.
#
# Tests use `--cmd <one-shot>` to override the default `claude` command
# with something that exits cleanly and produces verifiable output. The
# auto-TTY detection added to cmd_run lets these tests run in the
# harness's non-interactive subshell without falling over on docker
# compose's "input device is not a TTY" check.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Test cases ─────────────────────────────────────────────────────────────

run_succeeds_when_the_one_shot_command_exits_zero_test_case() {
    given a_unique_test_base_image_tag_and_an_initialized_project
    when the_user_runs_connie_run_with_command "/bin/true"
    expect it_succeeds
}

run_executes_as_claude_user_test_case() {
    given a_unique_test_base_image_tag_and_an_initialized_project
    when the_user_runs_connie_run_with_command "id -un"
    expect stdout_to_contain "^claude-user$"
}

run_executes_with_uid_1000_test_case() {
    given a_unique_test_base_image_tag_and_an_initialized_project
    when the_user_runs_connie_run_with_command "id -u"
    expect stdout_to_contain "^1000$"
}

run_mounts_the_project_directory_at_workspace_test_case() {
    # Drop a sentinel file into the project, then ask the container
    # to read it. If the bind mount works correctly, /workspace
    # inside the container surfaces the file.
    given a_unique_test_base_image_tag_and_an_initialized_project
    given a_sentinel_file_in_the_workspace
    when the_user_runs_connie_run_with_command "cat /workspace/SENTINEL"
    expect stdout_to_contain "sentinel-content"
}

run_provides_a_writable_tmpfs_at_slash_tmp_test_case() {
    given a_unique_test_base_image_tag_and_an_initialized_project
    # If /tmp is writable, the redirect succeeds. If the rest of the
    # filesystem is read-only as expected, the read of the freshly-
    # written file from the same container instance should succeed too.
    when the_user_runs_connie_run_with_command "sh -c 'echo ok > /tmp/probe && cat /tmp/probe'"
    expect stdout_to_contain "ok"
}

run_enforces_a_read_only_root_filesystem_test_case() {
    given a_unique_test_base_image_tag_and_an_initialized_project
    # Writing to /etc/ should fail because the root filesystem is
    # read-only. Use `sh -c '... || echo READ_ONLY'` so a successful
    # write yields no marker but a failure to write yields the marker
    # — easier to assert via stdout_to_contain.
    when the_user_runs_connie_run_with_command "sh -c 'touch /etc/probe 2>/dev/null || echo READ_ONLY'"
    expect stdout_to_contain "READ_ONLY"
}

run_loads_the_connie_managed_policy_context_into_etc_claude_code_test_case() {
    given a_unique_test_base_image_tag_and_an_initialized_project
    when the_user_runs_connie_run_with_command "cat /etc/claude-code/CLAUDE.md"
    expect stdout_to_contain "# Connie Container Environment"
}

run_does_not_leak_connie_no_dispatch_into_the_container_environment_test_case() {
    # Regression test for the POSIX-special-builtin bug:
    # `CONNIE_NO_DISPATCH=1 . connie` in the test harness used to
    # persist+export the variable in the harness's subshell, which
    # then propagated to the connie subprocess and skipped `_main`.
    # The harness now sets+unsets explicitly. As a belt-and-braces
    # check, this test verifies the variable doesn't reach the
    # container's environment via any path.
    given a_unique_test_base_image_tag_and_an_initialized_project
    when the_user_runs_connie_run_with_command "sh -c 'echo dispatch=\${CONNIE_NO_DISPATCH:-UNSET}'"
    expect stdout_to_contain "dispatch=UNSET"
}
