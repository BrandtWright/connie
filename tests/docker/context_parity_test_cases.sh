# tests/docker/context_parity_test_cases.sh
#
# Verify that the managed-policy context Claude Code sees inside a
# running container matches what `connie context` previews on the host.
# Both sides are produced by _generate_connie_context, so the parity
# claim reduces to "the same merged config produces the same text on
# both paths" — but each path has very different plumbing around it:
#
#   Container side: _generate_connie_context → embedded as the
#     CONNIE_CONTEXT YAML-string build arg → docker build → RUN
#     command in extend.Dockerfile writes it to
#     /etc/claude-code/CLAUDE.md inside the image. Multi-line, special-
#     character round-trip through ARG handling is the historical
#     failure mode here.
#
#   Host side: _generate_connie_context → printed by cmd_context after
#     a "Managed-policy" scope header. No quoting, no build arg layer.
#
# To prove parity, both tests use the same fingerprint: an env var
# `PARITY_CHECK = fp-deadbeef-2026` set in the project config. That
# value flows through _generate_connie_context's `env | to_entries`
# pipeline into the "## Environment Variables" section, producing the
# substring "PARITY_CHECK: fp-deadbeef-2026" in BOTH outputs if (and
# only if) the config-to-text chain is intact on both paths.
#
# This is a substring-match parity check, not a byte-for-byte one. A
# byte-for-byte version would have to extract the managed-policy
# section from the multi-scope preview output, which is fragile against
# header-format changes. The fingerprint approach catches the
# regressions that would actually matter to a user — a stale or
# differently-quoted version of the context reaching the container.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Test cases ─────────────────────────────────────────────────────────────

context_parity_container_managed_policy_reflects_project_config_test_case() {
    given a_unique_test_base_image_tag_and_an_initialized_project_with_a_parity_fingerprint
    when the_user_runs_connie_run_with_command "cat /etc/claude-code/CLAUDE.md"
    expect stdout_to_contain "PARITY_CHECK: fp-deadbeef-2026"
}

context_parity_host_preview_reflects_project_config_test_case() {
    given a_unique_test_base_image_tag_and_an_initialized_project_with_a_parity_fingerprint
    when the_user_runs_connie_context_against_the_project
    expect stdout_to_contain "PARITY_CHECK: fp-deadbeef-2026"
}
