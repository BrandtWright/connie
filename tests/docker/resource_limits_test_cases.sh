# tests/docker/resource_limits_test_cases.sh
#
# Verify that mem_limit, cpus, and pids_limit from the merged config
# actually constrain the running container — not just that they reach
# the generated override file. The override-side checks live in
# tests/unit/generate_override_test_cases.sh; what this file adds is
# the end-to-end claim that Docker is honoring those values at runtime.
#
# All three limits surface as files under /sys/fs/cgroup inside the
# container (cgroup v2 unified hierarchy, which is what Docker uses on
# modern Alpine/Linux hosts). The defaults from src/config/defaults.yml
# are 4g memory, 2.0 cpus, 512 pids:
#
#   /sys/fs/cgroup/memory.max  → "4294967296\n"      (4 * 1024^3 bytes)
#   /sys/fs/cgroup/cpu.max     → "200000 100000\n"   (quota period)
#   /sys/fs/cgroup/pids.max    → "512\n"
#
# Note on the CPU value: with Docker's default scheduling period of
# 100000us, `cpus: 2.0` becomes a quota of 200000us per period. The
# format is "<quota> <period>" — we only assert the quota since the
# period is a Docker implementation detail, not connie's contract.
#
# If a future host runs cgroup v1, these tests will fail with empty
# stdout (the v1 paths are different); when that happens we'll add a
# v1/v2 sniff to the assertion. For now we follow what the standard
# modern Linux + Docker stack produces.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Test cases ─────────────────────────────────────────────────────────────

resource_limits_memory_max_equals_the_merged_config_value_test_case() {
    given a_unique_test_base_image_tag_and_an_initialized_project
    # 4g = 4 * 1024^3 = 4294967296 bytes. The cgroup file may contain
    # additional whitespace, so we substring-match rather than equal-match.
    when the_user_runs_connie_run_with_command "cat /sys/fs/cgroup/memory.max"
    expect stdout_to_contain "4294967296"
}

resource_limits_pids_max_equals_the_merged_config_value_test_case() {
    given a_unique_test_base_image_tag_and_an_initialized_project
    when the_user_runs_connie_run_with_command "cat /sys/fs/cgroup/pids.max"
    expect stdout_to_contain "512"
}

resource_limits_cpu_quota_reflects_the_merged_config_value_test_case() {
    given a_unique_test_base_image_tag_and_an_initialized_project
    when the_user_runs_connie_run_with_command "cat /sys/fs/cgroup/cpu.max"
    # cpus: 2.0 → quota 200000 (period 100000). We assert only the
    # quota number — the period is a Docker default, not a connie
    # guarantee, and would brittle the test if it ever changed.
    expect stdout_to_contain "200000"
}
