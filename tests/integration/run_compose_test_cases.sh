# tests/integration/run_compose_test_cases.sh
#
# Behavior specifications for _run_compose — the thin wrapper that invokes
# `docker compose` with the project-scoped name and the two -f files (the
# static hardened base compose file plus the generated override), forwarding
# any trailing arguments. Covered here without a real Docker daemon by
# putting a stub `docker` on PATH that records its argv to a file.

# shellcheck disable=SC2148 # sourced by harness; no shebang needed

# ── Preconditions ──────────────────────────────────────────────────────────

# Shadow docker with a shell function that records each argument it
# receives, one per line, to $DOCKER_ARGS_FILE. A function (resolved before
# PATH) is used rather than a stub script on PATH because the harness
# sandbox lives under a noexec tmpdir, so a script there cannot be exec'd;
# a function needs no exec and works on every host.
a_recording_stub_docker() {
    DOCKER_ARGS_FILE="$WORKSPACE/docker-args"
    # shellcheck disable=SC2317 # invoked indirectly by _run_compose via PATH shadowing
    docker() {
        : >"$DOCKER_ARGS_FILE"
        for _a in "$@"; do
            printf '%s\n' "$_a" >>"$DOCKER_ARGS_FILE"
        done
    }

    project_path="$WORKSPACE/project"
    mkdir -p "$project_path"
    override_file="$WORKSPACE/override.yml"
    : >"$override_file"
}

# ── Stimuli ────────────────────────────────────────────────────────────────

the_compose_run_subcommand_is_invoked() {
    _run_compose "$project_path" "$override_file" run --rm workspace \
        >/dev/null 2>&1
}

# ── Assertions ─────────────────────────────────────────────────────────────

the_recorded_args_include_line() {
    if grep -qxF -- "$1" "$DOCKER_ARGS_FILE"; then
        return 0
    fi
    _assertion_failure "recorded docker arg" "$1" \
        "recorded args were" "$(cat "$DOCKER_ARGS_FILE")"
}

# ── Test cases ─────────────────────────────────────────────────────────────

run_compose_invokes_the_docker_compose_subcommand_test_case() {
    given a_recording_stub_docker
    when the_compose_run_subcommand_is_invoked
    expect the_recorded_args_include_line "compose"
}

run_compose_scopes_the_project_name_to_the_slug_test_case() {
    given a_recording_stub_docker
    when the_compose_run_subcommand_is_invoked
    # Inseparable claim: the -p flag is present AND carries the
    # connie-<slug> project name so projects don't share a namespace.
    expect the_recorded_args_include_line "-p"
    expect the_recorded_args_include_line "$(_compose_project_name "$project_path")"
}

run_compose_passes_both_the_base_and_override_compose_files_test_case() {
    given a_recording_stub_docker
    when the_compose_run_subcommand_is_invoked
    expect the_recorded_args_include_line "$LIB_DIR/docker/docker-compose.yml"
    expect the_recorded_args_include_line "$override_file"
}

run_compose_forwards_its_trailing_arguments_verbatim_test_case() {
    given a_recording_stub_docker
    when the_compose_run_subcommand_is_invoked
    expect the_recorded_args_include_line "run"
    expect the_recorded_args_include_line "--rm"
    expect the_recorded_args_include_line "workspace"
}
