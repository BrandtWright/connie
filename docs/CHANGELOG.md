# Changelog

All notable changes to connie will be documented here.

Format follows [Keep a Changelog][keep-a-changelog].
Versioning follows [Semantic Versioning][semver].

---

## [Unreleased]

### Added

- **`connie remove [dir]`** — symmetric inverse of `connie init`.
  Removes five connie-owned assets in dependency order (Docker
  image → Docker network → state dir → config dir → registry
  entry) so a partial failure leaves the registry pointing at
  recoverable state. The project directory under `/workspace` is
  never touched. Closes the long-standing gap where
  `connie init` scaffolded state but nothing removed it once the
  project no longer wanted to be managed.

  Flags:
  - `--yes` skips the y/N confirmation. Required in non-TTY
    contexts (CI, scripts, piped stdin) — connie dies with a
    clear hint rather than hang waiting for input that won't
    come, matching `rm -i` semantics.
  - `--keep-state` preserves the per-project state dir (OAuth
    tokens + conversation history). Removes everything else.
    Useful for the "log out but I might come back" case;
    re-running `connie init` against the same path lands the
    user with their Claude Code session intact.
  - `--keep-image` skips the Docker image + network step.
  - `--dry-run` prints what would be removed without touching
    anything. Same output format as the confirmation prompt so
    users see the same picture in both code paths.

  `connie clean` is unchanged — it still removes only the
  per-project image, leaving state and config in place. The split
  is deliberate: `clean` is "free disk space, rebuild fresh";
  `remove` is "I'm done with this project."

  Implementation: new `_confirm` and `_unregister_project`
  helpers (the latter is the inverse of `_register_project`).
  13 new tests across `tests/integration/` and `tests/cli/`
  covering each flag combination, the non-TTY refusal, the
  sentinel-survival guarantee for the project directory, and
  the graceful no-op against unregistered paths.

- **`connie list`** — prints the project workspaces connie knows
  about, one absolute path per line to stdout, sorted, reading the
  registry (`projects.yml`) that `connie init`/`run` populate and
  `connie remove` prunes. Output goes to stdout so it pipes cleanly
  (e.g. `connie list | while read d; …`); an empty or absent registry
  is not an error — stdout stays an empty list and the "nothing
  registered yet" note goes to stderr. Takes no `[dir]` argument.
  6 new CLI tests in `tests/cli/list_test_cases.sh`.

### Changed

- **The test harness now fails a test when a `given`/`when` step exits
  non-zero**, not just on a failed `expect`. Because the test subshell
  runs with `set -e` disabled (it's the left operand of `||`), a broken
  precondition or stimulus previously continued silently and later
  assertions could pass against stale state — a false green. Steps are
  now status-checked exactly like assertions.
- **README documents `connie doctor` and the `-q`/`-v` verbosity flags**
  (with their `CONNIE_QUIET`/`CONNIE_VERBOSE` env equivalents), which
  had shipped without user-facing docs. The canonical test count now
  lives only in `docs/DESIGN.md`; drift-prone figures were removed from
  `CONTRIBUTING.md` and the PR template.
- **All shell scripts are now shfmt-formatted and the format is enforced
  in CI.** `make format-check` (which already specified the style) runs
  as a blocking step with shfmt installed, so formatting drift can no
  longer land. The one-time reformat was whitespace-only.
- **Expanded the Docker-free test suite** with direct coverage of
  `_prepare`, `_run_compose`, `_confirm`, the `_require_yq` v4 sniff, and
  verbosity flag/env precedence — orchestration paths previously reachable
  only through the Docker-gated layer.
- **`scripts/pre-commit` is now shellchecked and format-checked.** It was a
  POSIX shell script matched by neither lint set; the file selection is now
  factored into one Make variable so `lint-sh` and `format-check` cover the
  same files by construction.

### Fixed

- **The generated Compose override now YAML-encodes every
  user-controlled value** — `EXTRA_PACKAGES`, `BUILD_COMMANDS`,
  `command`, `volumes`, and `ports`. Previously these were spliced in
  with hand-written quoting, so a value containing a double quote (e.g.
  `--cmd 'sh -c "…"'`) broke out of the YAML string and a value with a
  space-then-`#` was silently truncated as a comment. Each is now
  emitted through `yq`, which always produces a valid, fully-escaped
  scalar. The remaining bare-scalar slices flagged in re-audit are now
  covered too: `BASE_IMAGE` is JSON-encoded, and the resource limits
  (`mem_limit`/`memswap_limit`, `cpus`, `pids_limit`) are validated against
  a strict character allowlist so a config/`CONNIE_*`-env value cannot
  inject a sibling compose key.

### Security

- **`connie` refuses to mount the Docker socket** through a project
  config's `volumes:` list. A `docker.sock` bind mount lets an
  in-container process drive the host daemon and launch a privileged
  container, escaping every other hardening measure; the entry is now
  rejected with an actionable error before the container is built. The
  guard also rejects the bypasses found in re-audit: mounting the socket's
  *directory* (`/var/run`, `/run`) or host root, any host directory that
  contains a `docker.sock`, and Compose long-syntax (mapping) volume
  entries (which are unsupported and were previously mangled into mounts
  that evaded the check).
- **Package names that look like apk flags are rejected.** A `packages:`
  or `--package` token starting with `-` (e.g. `--allow-untrusted`) would
  have been parsed as a flag by the unquoted `apk add` in the build;
  connie now rejects such tokens and the Dockerfile passes `--` as a
  backstop.
- **Config `env:` keys can no longer inject Compose keys.** Only env
  *values* were YAML-encoded; a key containing a newline could inject a
  sibling key such as `privileged: true` onto the workspace service — a
  full host escape. Both key and value are now `@json`-encoded, and env
  keys containing a control character (from `.env` or `--env`) are
  rejected outright.
- **Volume and env guards now abort the run, not just warn.** These
  validators run inside a command substitution, so their error previously
  exited only the sub-shell — connie carried on and emitted an override
  missing the rejected block (the socket guard never actually *stopped* a
  run). The failure is now propagated, so a rejected value aborts `connie
  config`/`build`/`run` with a non-zero status and no override emitted.

---

## [0.4.1] — 2026-05-31

### Added

- **markdownlint `MD054` rule enabled** to mechanically enforce
  reference-style links over inline. Configured with `inline: false`
  and `url_inline: false` (the two banned variants); autolinks
  (`<https://…>`) and the three reference variants (full, collapsed,
  shortcut) stay allowed. CONTRIBUTING.md "Code Style" gained a
  "Markdown links" subsection documenting the convention and the
  rationale (line-wrap awkwardness, scattered URL maintenance).
  Pre-commit hook catches any future inline `[text](url)` at commit
  time.

### Changed

- **Switched from `markdownlint-cli` to `markdownlint-cli2`** for the
  `make lint-md` target and the CI install step. Cli2 is by David
  Anson (the author of the underlying `markdownlint` library itself);
  cli (by Igor Shubovych) is in maintenance mode. The author-
  maintained variant tracks library changes first, supports native
  glob patterns (the Makefile target dropped its `find … | xargs …`
  scaffolding for a direct `markdownlint-cli2 "**/*.md" "#.git"
  "#node_modules"`), and adds SARIF output for future GitHub CI
  annotations. Existing `.markdownlint.yaml` config is consumed
  unchanged by both. Contributors should `npm install -g
  markdownlint-cli2` in place of `markdownlint-cli`; the project's
  own `config.yml` example in README + `src/config/project.yml`
  template comments updated accordingly.
- **All inline markdown links converted to reference style.** 16
  inline `[text](url)` links across AGENTS.md, CODE_OF_CONDUCT.md,
  CONTRIBUTING.md, README.md, docs/CHANGELOG.md, and docs/DESIGN.md
  rewritten as `[text][slug]` with definitions grouped at the bottom
  of each file in the order they appear in the body. No content
  change; readability + maintenance improvement only. Locked in by
  the MD054 rule above.
- **AGENTS.md H1 changed** from the bare-filename `# AGENTS.md` to
  the descriptive `# connie — guidance for AI coding assistants`.
  The bare-filename convention came from the CLAUDE.md heritage (a
  Claude-Code-specific norm); a descriptive title matches the
  pattern README / CONTRIBUTING / SECURITY already use.
- **`CLAUDE.md` renamed to `AGENTS.md`** at the repo root. The file's
  content was 80% tool-agnostic engineering documentation
  (architecture, conventions, hard constraints, file responsibilities)
  with only a small "session-specific guidance" section bound to
  Claude Code specifically. The new name follows the
  [AGENTS.md spec][agents-md] — a tool-agnostic convention
  that lets Claude Code, Cursor, Aider, Copilot, and any other
  assistant adopting it read the same project context without
  per-tool duplication. Claude Code looks for `CLAUDE.md` by default;
  contributors who prefer the old name can add a `CLAUDE.md` symlink
  pointing at `AGENTS.md` (kept out of source control via personal
  preference). Note: nothing in `src/`, `tests/`, or runtime-generated
  paths changed — the many references to `/etc/claude-code/CLAUDE.md`,
  `~/.claude/CLAUDE.md`, `/workspace/CLAUDE.md`, and similar are
  Claude Code's own runtime file paths and stay named as Claude Code
  expects them.

---

## [0.4.0] — 2026-05-30

### Added

- **`connie doctor`** — new diagnostic subcommand. Runs a series of
  checks across required tools (docker on PATH, daemon reachable, yq
  on PATH, yq is v4), connie installation (lib dir + every Dockerfile
  / compose file / config template), the base image (built or not),
  and — optionally, when a path is given — per-project state (config
  present and parseable, state-dir mode 0700). Each check reports
  `ok` / `warn` / `fail` with an actionable hint on non-ok results.
  Exits 0 if no failures, 1 if any. This is the command a user runs
  FIRST when something isn't working right — surfaces misconfiguration
  directly instead of letting a later `connie run` discover it
  through a less-friendly error path. `connie doctor && connie run`
  is a safe gating pattern.
- **`-q` / `--quiet` and `-v` / `--verbose` flags** (with matching
  `CONNIE_QUIET=1` / `CONNIE_VERBOSE=1` env vars). Three verbosity
  levels: quiet (only errors), normal (info + detail, default),
  verbose (also `[debug]` lines). Suppresses `==> Initializing` and
  similar progress output for scripts that wrap connie; enables
  internal tracing (currently the exact `docker compose` invocation)
  for debugging.
- **`_debug` log helper** — visible only at verbose level. Used by
  `_run_compose` to trace the full `docker compose -p … -f … -f …`
  call so a user can see exactly what connie is about to run when
  diagnosing why something hangs or fails.
- **SIGINT / SIGTERM signal handlers** in `cmd_run` and `cmd_build` —
  print `Interrupted. Cleaning up.` / `Terminated. Cleaning up.` and
  exit with the conventional 130 / 143 codes. The existing EXIT
  trap still handles temp-file cleanup; the new handlers just make
  Ctrl+C exit deliberately rather than silently.
- **`make watch`** — wraps `tests/watch.sh` for re-run-on-change
  development. Extra args pass through to `tests/run.sh` after `--`:
  `make watch -- --pretty -f slug`.
- **`make format` / `make format-check`** — wrap `shfmt` with the
  project's POSIX-dialect, 4-space-indent, simplify options. The
  `-check` variant is safe in CI / pre-commit (exits 0 if shfmt
  isn't installed, so it can land before shfmt is provisioned
  everywhere).
- **Sectioned + ANSI-coloured `make help`** — Install / Lint and
  format / Test / PREFIX sections with bold headers and dimmed
  sub-text. Colors disable cleanly in non-TTY contexts.
- **`.vscode/settings.json` + `.vscode/extensions.json`** — workspace
  editor settings shipping shellcheck dialect (`-s sh`), shellscript
  association for the bare `connie` script, 80-char rulers for
  shell/markdown, LF EOLs, final newlines. `extensions.json`
  recommends the four linter extensions matching `make lint`.
- **OSS hygiene quartet**:
  - `CODE_OF_CONDUCT.md` — adopts Contributor Covenant 2.1 by
    reference (avoids in-repo drift from the canonical source)
  - `.github/ISSUE_TEMPLATE/bug_report.md` — what happened / what
    you expected / reproduction / environment / output
  - `.github/ISSUE_TEMPLATE/feature_request.md` — problem / proposed
    shape / alternatives / scope check against DESIGN.md principles
  - `.github/PULL_REQUEST_TEMPLATE.md` — pre-commit checklist
    (check / lint / test / test-docker / CHANGELOG / DESIGN if
    security-relevant) plus summary / test plan / notes
  - `.github/dependabot.yml` — weekly auto-PRs to bump
    `actions/checkout@v4` and similar
- **Function-index ToC at the top of `src/connie`** — 25-line table
  of contents grouped by the existing section markers. Names only
  (line numbers drift); doubles as a navigation roadmap matching
  the order of definitions in the file.
- **`docs/DESIGN.md` "Test Architecture" section** — documents the
  four-layer split (unit / integration / cli / docker), the
  given/when/expect DSL with one-claim-per-test convention, per-test
  subshell isolation with redirected HOME/XDG_*, Docker-layer
  per-subshell tag + network cleanup, the test-hook env overrides
  (CONNIE_BASE_IMAGE, CONNIE_ETC_CLAUDE_MD, CONNIE_LIB_DIR,
  CONNIE_NO_DISPATCH), and the cmd_run auto-TTY detection.
- **`docs/TODO.md` "Release-Integration Punch List"** — captures
  items deferred until the project has a real Git remote: GPG-signed
  release tags, README badges, SBOM generation in CI, FUNDING.yml,
  GitHub repo metadata.
- **24 new tests** under `tests/cli/`: 8 verbosity, 8 doctor, 8
  failure-path / error-message-shape. Total 207/207 (was 183).

### Changed

- **`_die` now accepts an optional second argument as a hint line**,
  printed indented under the primary message. Every actionable error
  path now ships a hint pointing at the next concrete recovery step:
  `_require` failures point at `connie doctor`; `_require_yq` points
  at the install URL; "no project config" points at both `connie init`
  and `connie doctor`; "unknown flag / command / argument" all point
  at `connie help`. Pre-existing one-arg `_die` callers continue to
  work unchanged. The `--package requires an argument`-style
  arg-validation errors deliberately stay hint-less.
- **`_info` and `_detail` now gate on `$_VERBOSITY`** — silent under
  `-q`, visible at default and `-v`. `_debug` is new at the same gate
  boundary, visible only at `-v`. The "==> Next steps:" heredoc and
  the "NOTE: Base image not found" leading newline in `cmd_init` are
  also gated, so `connie -q init <dir>` produces truly empty stderr
  on success.
- **`docs/DESIGN.md` Build Process section** refreshed to describe
  the SHA-pinned installer with the update procedure, reference the
  new Alpine digest pin, and explain the supply-chain rationale.

### Fixed

- **Doctor failure-mode tests are now hermetic.** The original
  formulation assumed docker would be absent at test time (true in
  the dev container, false on real developer hosts) — two tests
  failed when run on a host with docker installed. Fix: force a
  deterministic failure by pointing `CONNIE_LIB_DIR` at a missing
  path, so the install-presence checks always fail and the test
  doesn't depend on the host's tool inventory.

### Security

- **Alpine base pinned by content digest**, not just tag. Docker
  Hub does not guarantee tag immutability — a re-push to
  `alpine:3.20` (whether legitimate or compromised) would silently
  change what every fresh connie base image starts from. Now uses
  `alpine:3.20@sha256:d9e853e87e55…` so a rebuild reproduces
  exactly the same Alpine layers, or fails loudly if the registry
  no longer serves that digest. Update procedure documented in a
  comment block in `base.Dockerfile`. Same pattern as the
  SHA-pinned Claude Code installer landed in v0.3.0.

---

## [0.3.0] — 2026-05-30

### Added

- **Docker-gated test layer** — 31 end-to-end tests under `tests/docker/`
  exercising the subcommands that build real images and start
  containers. Covers `connie build-base` (image creation, claude-user
  uid 1000, `DISABLE_AUTOUPDATER` baked in, entrypoint path, Claude
  Code binary location, idempotence), `connie build` (per-project
  image creation, the `_generate_override` → `extend.Dockerfile` →
  `docker build` chain, the `CONNIE_CONTEXT` build arg reaching
  `/etc/claude-code/CLAUDE.md`, idempotence, auto-build-base
  branch), `connie clean` (`docker compose down --rmi local` semantics
  — workspace image removed, base image retained), `connie run`
  lifecycle (claude-user uid, `/workspace` bind mount, writable
  `/tmp`, read-only root, no `CONNIE_NO_DISPATCH` env leak),
  cgroup-v2 resource-limit enforcement (`memory.max`, `pids.max`,
  `cpu.max`), host↔container context parity (a fingerprint env var
  staged in the project config appears in both the in-container
  `/etc/claude-code/CLAUDE.md` and the host's `connie context`
  preview), and the `.connie/` → XDG auto-migration trigger.
  Run via `make test-docker`; the runner exits 0 with a skip message
  when docker is absent so it is safe to call from any CI. Tests stage
  images to a per-subshell `connie-test/base:harness-<test>-<pid>`
  tag and `docker network rm` the per-project network in the cleanup
  trap so neither the user's production `connie/base:latest` nor the
  Docker IPAM pool ever accumulate state across runs.
- **GitHub Actions CI workflow** (`.github/workflows/ci.yml`) — runs
  `make check`, `make lint`, `make test` (default shell), `dash
  tests/run.sh` (POSIX-sh portability check), and `make test-docker`
  on every push and PR to `main`. The Docker job is parallel and
  non-blocking for the lint half.
- **`make lint`** — chains shellcheck (POSIX sh enforcement),
  markdownlint, hadolint, and `yq` parse-checks across every file
  of the matching type. Sub-targets `lint-sh`, `lint-md`,
  `lint-docker`, `lint-yaml` are independently runnable.
- **`make install-dev`** — convenience target for contributors that
  chains `install PREFIX=~/.local` with `install-hooks`.
- **`make install-hooks`** — installs `scripts/pre-commit` as a
  symlink (or copy) into `.git/hooks/`. The hook runs `make lint`
  on every commit. Bypass once with `git commit --no-verify`.
- **Auto-TTY detection in `cmd_run`** — `connie run` now passes `-T`
  to `docker compose run` when stdout is not a terminal (`[ -t 1 ]`).
  The compose file's `tty: true` is the right default for interactive
  Claude Code use, but the same setting makes `docker compose run`
  refuse to start when invoked from CI, the test harness, or any
  output-redirected context. Detection lets the same `cmd_run` work
  in both contexts without a flag.
- **`LICENSE`** — MIT, applied retroactively to all existing code.
- **`SECURITY.md`** — vulnerability-reporting process, threat model,
  containment guarantees, known limitations, supply-chain notes.
- **`CONNIE_BASE_IMAGE` env var** — overrides the default
  `connie/base:latest` tag. Used by the Docker test layer to stage
  to a per-subshell `connie-test/base:harness-*` tag without
  touching the production image. Also useful outside testing — e.g.
  building a `connie-arm/base:latest` on an arm host alongside the
  x86_64 tag.
- **`CONNIE_ETC_CLAUDE_MD` env var** — overrides the system-wide
  Claude Code policy path (`/etc/claude-code/CLAUDE.md` by default).
  Used by the test harness to redirect to a fixture file so tests
  pass on hosts where `/etc/` is not the connie-container layout.
- **POSIX shell test suite** — roll-your-own test harness under `tests/`
  with no external dependencies, designed around a `given`/`when`/`expect`
  DSL where each step is a named function the framework executes and
  records. Inspired by slipbox's test architecture but with TAP output
  by default and the "one logical claim per test" rule treated as a
  documented convention rather than a structural constraint.
  Provides per-test subshell isolation, per-test fake-home workspaces
  (`HOME` and `XDG_*` redirected to a `mktemp -d` so connie's path-
  derived globals point at a sandbox), per-test `$TEST_STDOUT` /
  `$TEST_STDERR` files for capture-based assertions, primitive
  assertions (`expect_equal`, `expect_match`, `expect_file_to_exist`,
  etc.), process-level assertions (`it_succeeds`, `it_fails`,
  `it_logs_to_stderr`), and an `exercise_connie` stimulus helper.
  TAP version 13 by default with YAML diagnostic blocks and a
  failed-test summary; pretty mode with ANSI colour via `--pretty`;
  verbose mode preserving artifact directories via `-v`; substring
  test selection via `-f`; entr-based watch mode via `tests/watch.sh`.
  `src/connie`'s argument parser and dispatch are wrapped in a `_main`
  function called by an entry-point line at the bottom of the script;
  tests source the script with `CONNIE_NO_DISPATCH=1` to get the
  function definitions without firing the CLI. 152 non-Docker tests
  across `tests/{unit,integration,cli}/` cover the pure functions,
  filesystem-touching helpers, and the CLI surface. `tests/README.md`
  documents the conventions.
- **Zero project footprint** — `connie` no longer writes anything to the
  project directory. All state (config, Claude Code auth, session history)
  now lives in standard XDG directories on the developer's machine:
  - `~/.config/connie/projects/<slug>/config.yml` — developer-owned project config
  - `~/.local/state/connie/<slug>/` — Claude Code state and auth
  - `~/.local/share/connie/projects.yml` — project registry (path → slug)
  No `.gitignore` entry needed; the project does not need to know connie exists.
- **Claude Code context generation** at two of Claude Code's four
  documented context scopes. Connie owns the two that describe the
  container environment; the project and local scopes are untouched.
  - **Managed-policy scope** (`/etc/claude-code/CLAUDE.md`) — connie reads
    the merged config and generates a description of the container
    environment (installed packages, build commands, additional mounts,
    exposed ports, environment variables, resource limits, security
    constraints) and bakes it into the image at build time via a Docker
    build arg. Because it lives in the image, the user cannot exclude it.
  - **User-level scope** (`~/.claude/CLAUDE.md`) — connie assembles the
    host's `/etc/claude-code/CLAUDE.md` and `~/.claude/CLAUDE.md` (if
    present) into a single file in the per-project state directory, which
    is bind-mounted to `~/.claude/` inside the container. Each source
    contribution is preceded by a block-level HTML comment identifying
    its origin; Claude Code strips block-level HTML comments before
    context injection, so the markers cost no tokens but remain visible
    to humans previewing the file. Forwards the user's personal Claude
    Code preferences without per-project copies.
  Claude Code's default loading behaviour also picks up
  `/workspace/CLAUDE.md` and `/workspace/CLAUDE.local.md` from the project
  — connie never touches those, so projects that already use them work
  unchanged.
- `connie context [dir]` — new subcommand that prints all four Claude Code
  context scopes (managed policy, user-level, project, local) without
  starting the container. Pure read operation — no on-disk state is
  modified. Requires no Docker. The project and local scopes are read
  from the project directory on the host so the preview reflects exactly
  what Claude Code will load on the next `connie run`, including project
  context (`./CLAUDE.md`, `./.claude/CLAUDE.md`) and local context
  (`./CLAUDE.local.md`) that connie itself never writes.
- `connie config [dir]` subcommand — prints the config file path, state
  directory path, and the effective Compose override for a project. Useful
  for diagnosing what `connie run` will do.
- Auto-migration from old `.connie/` project-directory layout to XDG directories.
  Triggered automatically on the first `connie run`/`connie build` for a project
  that still has a `.connie/` directory. Moves `config.yml`, `.claude/`, and
  `.claude.json`; removes `.connie/` if empty afterward.
- `build_commands:` config key — a list of arbitrary shell commands run at
  image build time as `claude-user`, after apk packages are installed. Enables
  npm, pip, gem, cargo, and other package managers not covered by the `packages:`
  apk mechanism. Commands are joined with `&&` and fail fast. Example:
  `build_commands: [npm install -g markdownlint-cli]`.
- `connie run` and `connie build` now automatically build the base image
  (`connie/base:latest`) if it does not exist, rather than dying with an
  error. A fresh install requires only `connie init` and `connie run` — no
  separate `connie build-base` step. `connie build-base` remains available
  to explicitly rebuild the base image (e.g. to pick up a new Claude Code
  version).

### Changed

- **Generated `/etc/claude-code/CLAUDE.md` is now markdownlint-clean.**
  The "Build-time setup commands" list is emitted with a leading
  blank line and zero-indent bullets (MD007/MD032); the "Base image:"
  sentence is wrapped to fit under 80 chars (MD013). Renders
  identically in any markdown engine; previews via `connie context`
  no longer carry preexisting lint debt.
- **Snapshot test helper** writes and compares with `printf '%s\n'`
  instead of `printf '%s'`, so the trailing newline that `$(...)`
  capture strips is restored on both paths. Fixes the MD047
  violation that every snapshot would otherwise inherit.
- `config/defaults.yml` is now load-bearing: all config keys are guaranteed
  to be present in the merged config after it is loaded, so the `// fallback`
  values that were duplicated in the script's yq expressions have been removed.
  `_merge_configs` now checks for the file at startup and exits with a clear
  error if it is missing rather than silently producing null values.

### Fixed

- **Per-test Docker network cleanup.** `docker compose run --rm`
  removes the container but not the network it created. Each Docker
  test left a `connie-<slug>_default` /16 subnet allocated; after
  one or two `make test-docker` runs the default IPAM pool would
  exhaust and every subsequent `connie run` failed with "all
  predefined address pools have been fully subnetted." The fixture
  cleanup trap now removes the network alongside the images.
- **Test harness POSIX-special-builtin bug** under `bash --posix`.
  `CONNIE_NO_DISPATCH=1 . src/connie` persisted and exported
  `CONNIE_NO_DISPATCH` in the harness's subshell because of POSIX's
  special-builtin variable-assignment semantics, causing every
  subsequent `exercise_connie` invocation to silently skip `_main`.
  The harness now sets and unsets explicitly.
- **CONTRIBUTING.md stale paths.** Every reference to `bin/connie` and
  `lib/connie/...` predated the rename to `src/connie`, `src/docker/`,
  and `src/config/`. New contributors following the doc would have
  hit "no such directory" errors.
- **Placeholder GitHub URLs** in README and CONTRIBUTING
  (`github.com/yourorg/connie`) — removed; install path reworded as
  "from a local checkout" until a real repo URL exists.
- Typo'd subcommand names (e.g. `connie buld` for `build`) now produce a
  clear error rather than silently falling through to the help text.
  Previously the parser's positional-argument case captured the typo into
  `_TARGET_DIR` while `_SUBCOMMAND` stayed empty, and the dispatch defaulted
  to `help` with no indication anything was wrong. A guard in the `help)`
  dispatch branch now dies with `Unknown command: <X>. Run 'connie help'
  for usage.` whenever a positional argument is present without a valid
  subcommand. Valid invocations (including bare `connie`, `connie help`,
  and flag-only forms) are unchanged.
- `connie clean` now surfaces docker errors instead of silently swallowing
  them. Previously `2>/dev/null || true` caused a failed clean (e.g. Docker
  daemon not running) to print "Done." and exit 0 with nothing removed.
- `command:` value in the generated `override.yml` is now quoted, preventing
  malformed YAML when `start_cmd` contains spaces or special characters.
- `_info` and `_detail` helpers now write to stderr instead of stdout.
  Previously, calling either function inside `_prepare` (which is invoked
  via command substitution to capture a temp-file path) would corrupt the
  captured path. stderr is the correct channel for progress messages;
  `_die` already used it.
- Port mappings configured in `config.yml` `ports:` were silently dropped
  and never forwarded to the container. The `ports` block was computed in
  `_generate_override` but missing from the YAML output.

### Security

- **Claude Code installer pinned by SHA256** in `base.Dockerfile`.
  The previous `curl -fsSL … | bash` was a textbook supply-chain
  hole: a brief compromise of `claude.ai` would have shipped
  arbitrary code into every fresh base image build. The pin is
  declared as a Dockerfile ARG so the current value appears in the
  build log on every rebuild and so a maintainer can test a candidate
  update via `--build-arg CLAUDE_INSTALLER_SHA256=<new>` without
  editing the file. Update procedure documented in a comment block
  above the ARG.
- Per-project state directories (`~/.local/state/connie/<slug>/`) and their
  `.claude/` subdirectories are now created — or normalised if already present
  — with mode `0700` at `connie init`, `connie run`, and during auto-migration.
  This protects the OAuth bearer token that Claude Code persists at
  `<slug>/.claude/.credentials.json` from other local users on the same machine,
  even if Claude Code itself does not set restrictive permissions on the
  credential file. Defense-in-depth, applied at the directory layer.

---

## [0.2.0]

### Added

- Forward the host's `TERM`, `COLORTERM`, and a derived `FORCE_COLOR` into the
  container so Claude Code renders with the same color depth in-container as on
  the host. Previously Docker's `-t` hardcoded `TERM=xterm` with no `COLORTERM`,
  downgrading Claude Code to basic 16-color output. `FORCE_COLOR` is derived from
  the host's declared capabilities (`COLORTERM=truecolor` → `3`, `*256color*`
  term → `2`, otherwise `1`) and bypasses Node.js/chalk's Docker PTY probe, which
  otherwise underestimates color support regardless of `TERM`/`COLORTERM`.
  All forwarded values are the lowest-precedence env entries — anything in
  `config.yml` `env:` or `--env` overrides them. `TERM` defaults to
  `xterm-256color` when unset on the host.
- Base image now installs `ncurses-terminfo-base` so forwarded `TERM` values
  (e.g. `screen-256color`) resolve against the terminfo database for
  in-container TUI tools such as `less`.

### Fixed

- `--env KEY=VALUE` now emits valid YAML. It previously appended bare
  `KEY=VALUE` lines into the `environment:` map, producing an unparseable
  override whenever any other env var was set. CLI `--env` values now merge as
  the highest-precedence env source.

---

## [0.1.0] — Initial release

### Added

- `connie build-base` — build the local base image
- `connie init [dir]` — scaffold `.connie/` inside a project directory
- `connie run [dir]` — build (if needed) and start Claude Code
- `connie build [dir]` — build the project container image without starting it
- `connie clean [dir]` — remove the locally built project container image

### Base image

- Alpine 3.20 with bash, coreutils, curl, wget, git, ripgrep, fd, jq, tree,
  file, tar, gzip, unzip, lsof, build-base, libgcc, libstdc++, linux-headers
- Non-root user `claude-user` (uid/gid 1000) — Claude Code runs as this user
- Claude Code installed via the official `install.sh` script as `claude-user`,
  placing the binary in `/home/claude-user/.local/bin/`
- `DISABLE_AUTOUPDATER=1` baked in — required for read-only filesystem
- `GIT_TERMINAL_PROMPT=0` baked in — prevents git from hanging on credentials
- `entrypoint.sh` redirects all XDG user directories to `/tmp` at startup,
  making the read-only filesystem transparent to tools that write to `~`

### Container security

- Read-only root filesystem
- All Linux capabilities dropped (`cap_drop: ALL`)
- `no-new-privileges: true`
- All suid/sgid bits removed from the base image at build time
- `/tmp` as `tmpfs` (RAM-backed, ephemeral)
- `init: true` for correct signal handling and zombie reaping
- Resource limits: 4GB RAM, 2 CPUs, 512 PIDs, 4096/8192 file descriptors

### Per-project Claude Code state

- `.connie/.claude/` and `.connie/.claude.json` are per-project, stored in
  `.connie/` alongside other container config
- Claude Code auth and memory are fully isolated between projects
- `connie init` pre-creates both on the host so Docker has valid mount points

### Config hierarchy

- Compiled-in defaults → system → user → project → CLI flags
- `config.yml` format: `packages`, `env`, `volumes`, `ports`,
  `start_cmd`, `resources`
- `--package`, `--env`, and `--cmd` CLI flags for per-invocation overrides

### Other

- Auto-detection of project root by walking up the directory tree
- POSIX-compliant shell script — works with sh, bash, dash, zsh
- `CONNIE_LIB_DIR` environment variable for local development without reinstalling

[keep-a-changelog]: https://keepachangelog.com/en/1.0.0/
[semver]: https://semver.org/spec/v2.0.0.html
[agents-md]: https://agents.md/
