# Test suite

A roll-your-own POSIX shell test harness for connie. ~400 lines of pure
POSIX `sh`, no external dependencies, designed to make tests read as
behaviour specifications.

## Running

```sh
make test                            # run everything except docker (TAP output)
sh tests/run.sh                      # same
sh tests/run.sh --pretty             # ANSI-coloured human-readable output
sh tests/run.sh -v                   # verbose: breadcrumbs on every test,
                                     # artifact directories preserved
sh tests/run.sh -f slug              # filter: only tests whose name
                                     # contains "slug"
sh tests/run.sh tests/unit/...sh     # run a specific file
sh tests/watch.sh                    # re-run on file change (needs `entr`)

make test-docker                     # run the docker-gated layer
sh tests/run-docker.sh               # same; same flags as run.sh
                                     # Skips with exit 0 if `docker` is not
                                     # on PATH or the daemon is unreachable
```

## Architecture at a glance

```text
tests/
├── harness.sh                  # the framework — discovery, isolation, DSL,
│                               # output (TAP and pretty), summary
├── run.sh                      # the runner — flag parsing, file discovery
├── watch.sh                    # entr-based file watcher
├── helpers/
│   └── preconditions.sh        # shared assertion primitives, exercise_connie
├── snapshots/                  # expected outputs for snapshot assertions
├── unit/                       # pure-function tests, no I/O
├── integration/                # filesystem I/O, no Docker
├── cli/                        # full CLI invocations, no Docker
└── docker/                     # gated; run from a Docker-capable host only
```

`tests/run.sh` runs `tests/{unit,integration,cli}/*.sh` by default.
Docker-gated tests live separately under `tests/docker/` and are run by
`tests/run-docker.sh`, which exits 0 with a message if `docker` is not
available — so it's safe to call from CI that may or may not have a
daemon. Tests set `CONNIE_BASE_IMAGE` to a unique `connie-test/base:*`
tag and `docker image rm` it on subshell exit so a developer's
production `connie/base:latest` is never touched.

## How a test is structured

```sh
# tests/unit/project_slug_test_cases.sh

# ── Preconditions ──
a_project_path_with_uppercase_characters() {
    project_path="/home/user/repos/MyProject"
}

# ── Stimuli ──
the_slug_is_computed() {
    slug=$(_project_slug "$project_path")
}

# ── Assertions ──
it_starts_with_a_lowercased_basename() {
    expect_starts_with "$slug" "myproject-"
}

# ── Test cases ──
slug_lowercases_uppercase_characters_in_the_basename_test_case() {
    given a_project_path_with_uppercase_characters
    when the_slug_is_computed
    expect it_starts_with_a_lowercased_basename
}
```

The framework discovers `*_test_case` functions and runs each in an
isolated subshell. `given`, `when`, and `expect` are functions that
*call* the named functions; the function names are the documentation.

## Conventions

### File naming

`<feature>_test_cases.sh` — e.g. `project_slug_test_cases.sh`,
`merge_configs_test_cases.sh`, `init_test_cases.sh`. The filename names
what the file tests; the `_test_cases.sh` suffix is the standard.

### Function naming

| Kind | Pattern | Example |
| --- | --- | --- |
| Precondition (fixture) | `a_*`, `an_*` | `an_existing_project_config` |
| Stimulus (action) | `the_user_*`, `the_*_is_*` | `the_user_runs_connie_init`, `the_slug_is_computed` |
| Assertion (named) | `it_*` | `it_logs_to_stderr`, `it_starts_with_a_lowercased_basename` |
| Assertion primitive | `expect_*` | `expect_equal`, `expect_match`, `expect_file_to_exist` |
| Test case | `*_test_case` | `slug_lowercases_uppercase_test_case` |

Function names are converted to readable descriptions by replacing
underscores with spaces and dropping the trailing `_test_case`. Choose
names that read naturally with that conversion: `slug_lowercases_uppercase_basename_test_case`
becomes "slug lowercases uppercase basename".

### One logical claim per test

Each test asserts **one behaviour**, not several. Multiple `expect` lines
are allowed when they describe inseparable aspects of the same claim
(e.g. "the file exists AND has the expected contents" is *one* claim
about the file). The harness does not exit on the first failed assertion
— all failures in a test are reported together.

If you find yourself making two unrelated claims in the same test, split
it. The test name should describe one thing; if the name has to be vague
to encompass everything, it's two tests.

### Where to put fixtures and stimuli

- **Reusable across multiple test files** → `tests/helpers/preconditions.sh`
- **Specific to one file** → at the top of that file, before the test cases

The harness sources all of `tests/helpers/*.sh` before each test, then
sources the test file itself. Test-file-local fixtures override or
extend the shared ones.

### Test isolation

Every test runs in a subshell with:

- A fresh `mktemp -d` workspace
- `HOME`, `XDG_CONFIG_HOME`, `XDG_STATE_HOME`, `XDG_DATA_HOME`,
  `XDG_CONFIG_DIRS` redirected into the workspace — so connie's path-
  derived globals all resolve into the sandbox
- `TEST_STDOUT` and `TEST_STDERR` exported as paths to per-test capture
  files; `exercise_connie` writes into them and assertions read from them
- `TEST_DETAIL` exported as the path to the per-test breadcrumb file that
  the harness reads on failure (or with `-v`)

Variables, working directory, and `set -e` failures cannot leak between
tests. Cleanup is automatic at subshell exit; `-v` preserves the artifact
directories under the harness's tmpdir so you can inspect what a test
actually created.

## Exercising connie from a test

Use the `exercise_connie` stimulus helper:

```sh
the_user_runs_connie_with_no_arguments() {
    exercise_connie
}

connie_prints_usage_when_invoked_with_no_arguments_test_case() {
    when the_user_runs_connie_with_no_arguments
    expect stdout_to_contain "Runs Claude Code"
}
```

`exercise_connie` invokes `src/connie` with the workspace's
`CONNIE_LIB_DIR` set, captures stdout and stderr to `$TEST_STDOUT` and
`$TEST_STDERR`, and sets `actual_exit_status` for `it_succeeds` /
`it_fails` to read.

## Adding a new assertion

If the assertion is generic (useful across many tests): add it to
`tests/helpers/preconditions.sh`. If it's specific to one feature: put
it in the same test file. Each assertion is a function that:

1. Returns 0 on pass.
2. Calls `_assertion_failure` with `expected_label`, `expected_value`,
   `actual_label`, `actual_value` on failure, then returns 1.

```sh
it_to_be_a_well_formed_uuid() {
    if printf '%s\n' "$slug" | grep -E -q '^[0-9a-f]{8}-...$'; then
        return 0
    fi
    _assertion_failure "value to be a UUID" "<uuid>" "value was" "$slug"
}
```

## Snapshot assertions (planned)

For commands that produce large blocks of output (`connie context`,
`connie config`) we'll use snapshot assertions: compare against a saved
file under `tests/snapshots/`, regenerate with `UPDATE_SNAPSHOTS=1 make test`.
Not implemented yet — coming with the first integration test that needs it.

## Output formats

**TAP** (default): TAP version 13 with YAML diagnostic blocks. Greppable
(`grep '^not ok'`), parseable by any TAP consumer. Failure summary at
the end lists failed test names.

**Pretty** (`--pretty`): ANSI-coloured human-readable output with `✓`
and `✗` marks, indented diagnostics, end-of-run summary listing failures
in red.

Both modes show the given/when/expect breadcrumbs from a failing test
so you can see what the test was trying to verify before the assertion
fired. With `-v`, breadcrumbs are shown for passing tests too.
