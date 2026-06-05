# TODO

Ideas and planned features for future development. Items here are under
consideration — not committed to any release.

---

## Release-Integration Punch List

The remote, the GitHub repository, and tag-triggered release automation
(`.github/workflows/release.yml`) now exist, and 0.5.0 has shipped as a
pre-release — so the original "can't land until a remote exists" blocker
is gone. What remains are the release-maturity tasks below.

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

### Repo presentation (anytime)

- **`.github/FUNDING.yml`.** Lists funding platforms (GitHub
  Sponsors, Ko-fi, etc.) used by the maintainer. GitHub renders a
  "Sponsor" button on the repo page when present.
- **GitHub repo metadata** — description, topics, the "About"
  sidebar's website/homepage field. Not files, but worth checking
  off so the project's GitHub page isn't blank.

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

---

## Quality / Internals

### `connie update` Command

A command that rebuilds the base image and pulls the latest `connie` release in
one step, analogous to `brew upgrade`.

---

## Documentation

### Screencast / Quickstart GIF

A short terminal recording showing `connie init` + `connie run` from scratch
would lower the barrier for new users evaluating the tool.
