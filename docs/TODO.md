# TODO

Ideas and planned features for future development. Items here are under
consideration — not committed to any release.

---

## Release-Integration Punch List

The remote, the GitHub repository, and tag-triggered release automation
(`.github/workflows/release.yml`) now exist, and 0.5.0 has shipped as a
pre-release — so the original "can't land until a remote exists" blocker
is gone. What remains are the release-maturity tasks below.

### API stabilization for 1.0

connie is deliberately pre-1.0, and the config/context surface is still
settling — the context subsystem recently took a breaking change (config
keys → `--append-system-prompt` injection). Before cutting 1.0, give the
config schema and the `connie` command set a stability pass so the 1.0
"this is stable" promise holds, and document whatever surface is meant to
be stable.

### Supply-chain hardening (1.0 prep)

Targeted at 1.0, where the claim being made is "this is a stable,
trustworthy release." The image — not the single-file script — is the
real attack surface, so these harden what actually ships in the
container.

- **SBOM generation in CI (`syft`).** Add a release step that runs
  `syft` against the freshly built base image and attaches the SPDX
  (or CycloneDX) output as a release asset, so anyone downloading a
  release can verify exactly which apk + npm packages shipped. Optionally
  gate the release on a `grype`/Trivy scan of that SBOM, failing on
  high-severity CVEs. Most on-brand remaining item for a security-first
  container tool.
- **Build provenance + artifact attestation.** Emit signed SLSA build
  provenance for release artifacts (e.g. GitHub's
  `actions/attest-build-provenance`), and optionally sign the base
  image and the SBOM with `cosign`/Sigstore. Lets a consumer verify a
  release was built by this repo's CI from this source and not
  tampered with afterwards — the complement to the SBOM (*what*
  shipped) and signed tags (*who* tagged it).
- **GPG-signed release tags.** Switch from `git tag -a` to
  `git tag -s` (0.5.0 used an unsigned annotated tag). Requires a
  maintainer GPG key with a verified email matching the GitHub
  account; the public half goes into GitHub settings so signatures
  show as "verified" on the tag page. A CI job can verify it.
- **Pin the CI toolchain.** The shipped artifact is reproducibly pinned
  (Alpine by digest, the Claude installer by SHA256), but `ci.yml` still
  fetches `yq`, `hadolint`, and `markdownlint-cli2` from `/latest` (only
  `shfmt` is version-pinned). Pin all four so a verifier upgrade can't
  silently flip a lint or test verdict between otherwise-identical runs.

### Repo presentation (anytime)

- **`.github/FUNDING.yml`.** Lists funding platforms (GitHub
  Sponsors, Ko-fi, etc.) used by the maintainer. GitHub renders a
  "Sponsor" button on the repo page when present.
- **GitHub repo metadata** — description, topics, the "About"
  sidebar's website/homepage field. Not files, but worth checking
  off so the project's GitHub page isn't blank.
- **OpenSSF Scorecard + Best Practices badges.** Add the
  `ossf/scorecard-action` workflow and (optionally) pursue the OpenSSF
  Best Practices badge (formerly CII). On current evidence connie scores
  well; the badges make the existing rigor legible to anyone evaluating
  the project from the outside.

### Governance & contribution health (anytime)

- **`CODEOWNERS`.** Even for a small maintainer set it documents who owns
  what and can drive automatic review requests.
- **Fuller code of conduct.** `CODE_OF_CONDUCT.md` is currently a short
  stub; adopt the full Contributor Covenant so the enforcement and
  contact process is explicit.
- **Document and enable branch protection.** Require the `ci` checks and
  at least one review on `main`, and record the policy in CONTRIBUTING so
  the bar is visible. (These are GitHub settings that live outside the
  repo, so they can't be verified from a checkout — worth noting they're
  on.)

---

## Features

### SSH Agent Forwarding

Forward the host's `SSH_AUTH_SOCK` into the container so Claude Code can
perform authenticated git operations (clone, push, fetch) without embedding
credentials in the image.

Planned approach: a `ssh:` config key in `config.yml` that opts in to the
mount. The socket path is taken from `$SSH_AUTH_SOCK` on the host.

### `connie init --update`

Refresh `config.yml` from the current installed template, merging in any
new keys with their defaults while preserving the user's existing values.

Useful after a `connie` upgrade that adds new config options.

### Richer `connie list` Output

`connie list` currently prints one absolute project path per line — minimal
and pipe-friendly by design. A future `--long`/`-l` (or `--format`) mode could
add columns drawn from data connie already has: the slug, a `(stale)` marker
when the registered path no longer exists on disk, a `(current)` marker for the
workspace containing `$PWD`, and — at the cost of a `docker image inspect` per
entry — whether the per-project image is built. Kept out of the default to
preserve clean, scriptable output.

### Multiple Containers Per Project

Allow `config.yml` to define a `services:` key describing a multi-container
stack (e.g. app + database). The current config structure was designed to
accommodate this without breaking changes.

### Registry Publishing

Support pushing the base image to a private registry so teams can share a
single built base rather than each developer building it locally.

---

### Config-merge narration under `-v`

`-v`/`--verbose` already exists (it emits `[debug]` lines tracing the
`docker compose` invocations). The remaining idea is to have it also narrate
the config-merge process — which config files were found and loaded, which
packages are being installed, what command will run. Distinct from
`connie config`, which shows the generated artifact; this would describe the
process that produced it.

### Rules-Directory Previewing in `connie context` — superseded

An earlier idea: `connie context` previewed all four Claude Code scopes, and
this item proposed also surfacing `~/.claude/rules/*.md` and
`<project>/.claude/rules/*.md`. The context redesign (`docs/context.md`) makes
it moot — connie no longer mirrors Claude's memory model in the preview.
`connie context` now prints only the context connie itself appends to the
system prompt; the project's `CLAUDE.md`/`CLAUDE.local.md` and any rules
directories load on Claude's side, outside connie's concern.

### Shell completions (bash + zsh)

Ship `completions/connie.{bash,zsh}` completing subcommands, per-subcommand
flags, and `[dir]` arguments, installed by the Makefile to the standard
bash-completion / zsh fpath locations. Deferred from the CLI-polish work
because it is the largest net-new surface and adds a standing coupling: the
completion scripts must track every change to the subcommand and flag set,
so it wants either a generation step or a drift check (assert every
dispatched subcommand appears in the completion) to stay honest.

---

## Quality / Internals

### `connie update` Command

A command that rebuilds the base image and pulls the latest `connie` release in
one step, analogous to `brew upgrade`.

### Test-coverage measurement

The suite is large (~3:1 test:source LOC, 330 cases), but coverage is
unquantified. Wrap `kcov` around `tests/run.sh` to produce a line/branch
coverage figure for `src/connie`, surface it in CI, and optionally fail
below a threshold — turning "lots of tests" into a defensible number that
also flags untested branches.

### Doc-drift guard

Docs run ~1.35:1 against source and many cite `src/connie` function and
flag names, so code changes routinely need a matching doc sweep. A
lightweight CI check — assert that the names cited in DESIGN/README/AGENTS
still exist in `src/connie`, or snapshot `connie help` — would catch drift
mechanically instead of by review.

### Modularize the source behind single-file distribution

`src/connie` is a single ~1900-line script — idiomatic for a copy-one-file
CLI and navigable via its function-index ToC, but near the size where one
file gets unwieldy. If it keeps growing, split the source into
`src/connie.d/*.sh` modules and add a Makefile build step that concatenates
them into the single `connie` installed to `bin`. That keeps one-file
distribution and the `CONNIE_LIB_DIR` story intact while letting the source
be modular. Only worth doing once the single file genuinely hurts — today
the ToC carries it.

### Skip the per-project image when there's nothing to add

With the project template now inert, the default project has no `packages`
and no `build_commands`, so `extend.Dockerfile` reduces to `FROM base` plus an
`ENV` and two no-op `RUN`s — yet connie still builds and tags a whole
per-project image (`connie-<slug>-workspace`) that is essentially the base
image plus one env var. When both `packages` and `build_commands` are empty,
connie could skip the per-project build and run the base image directly,
passing `NPM_CONFIG_PREFIX` via the Compose `environment:` block (it is
generic, so it could just move to `base.Dockerfile`). Saves a build step,
disk, and an image to clean, at the cost of a "maybe no per-project image"
branch in `clean`/`remove` and the loss of a uniform per-project-image model.
Pure build/runtime plumbing — no bearing on the security posture, which lives
in `docker-compose.yml`, not the image.

---

## Documentation

### Screencast / Quickstart GIF

A short terminal recording showing `connie init` + `connie run` from scratch
would lower the barrier for new users evaluating the tool.
