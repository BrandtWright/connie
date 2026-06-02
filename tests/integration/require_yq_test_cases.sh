# tests/integration/require_yq_test_cases.sh
#
# Behavior specifications for _require_yq — the prerequisite check that
# insists on yq v4 (mikefarah). v3 and the Python yq fork lack `eval-all`
# and would fail cryptically deep inside the config-merge pipeline, so
# _require_yq sniffs for eval-all support up front and dies with an
# install hint if it's missing. This is logic that has bitten real users
# (the two incompatible "yq" tools), so it's worth a direct test.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Preconditions ──────────────────────────────────────────────────────────

# Shadow yq with a function that exists (so `command -v yq` passes) but
# fails the eval-all sniff, mimicking a v3 / Python-fork yq. A function is
# used rather than a PATH stub because the sandbox tmpdir is noexec.
a_yq_without_eval_all_support() {
    # shellcheck disable=SC2317 # invoked indirectly by _require_yq via PATH shadowing
    yq() {
        case "$1" in
            eval-all) return 1 ;;
            *) return 0 ;;
        esac
    }
}

# ── Stimuli ────────────────────────────────────────────────────────────────

# _require_yq calls _die (which exits) when the sniff fails. Run it in a
# subshell so the exit is captured as a status, and merge stderr to assert
# the message.
require_yq_is_checked() {
    rq_stderr=$({ _require_yq >/dev/null; } 2>&1)
    rq_status=$?
}

# ── Test cases ─────────────────────────────────────────────────────────────

require_yq_rejects_a_yq_that_lacks_eval_all_test_case() {
    given a_yq_without_eval_all_support
    when require_yq_is_checked
    # Inseparable claim: it fails AND points the user at yq v4.
    expect expect_not_equal "0" "$rq_status"
    expect expect_contains "$rq_stderr" "v4"
}

require_yq_passes_with_the_real_v4_yq_test_case() {
    # No shadow: the mikefarah v4 yq the suite already depends on supports
    # eval-all, so the check should pass cleanly.
    when require_yq_is_checked
    expect expect_equal "0" "$rq_status"
}
