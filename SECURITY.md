# Security Policy

`connie` is a hardening wrapper that runs Claude Code inside a
constrained Docker container. Its purpose is to bound what an AI agent
can read, write, or execute on a developer's host. Security issues in
the wrapper that weaken those bounds are taken seriously.

This document describes what is in scope, what is not, how to report a
vulnerability, and what guarantees the project does and does not make.

---

## Supported Versions

The project is pre-1.0. The most recent release on the `main` branch is
the only supported version — there is no LTS line and no backports to
older versions.

| Version        | Status      |
| -------------- | ----------- |
| latest `main`  | supported   |
| anything older | unsupported |

The `VERSION` constant at the top of `src/connie` reflects the current
release line. See `docs/CHANGELOG.md` for the per-release notes.

---

## Reporting a Vulnerability

For sensitive issues that should not be disclosed publicly, please
email the maintainer at <wright.brandt@gmail.com> with:

- A description of the issue and its security impact
- A reproduction (commands, config, expected vs observed behavior)
- Any suggested mitigation, if you have one in mind

Expected response time: a first acknowledgement within 7 days. Patch
timeline depends on severity and complexity; for issues that break the
container's containment guarantees, the patch is the next release.

For non-sensitive issues (where public discussion does not create
risk), open a GitHub issue with the `security` label instead.

---

## Threat Model and Containment Guarantees

The container is designed under the assumption that **Claude Code, or
any tool it spawns, may execute arbitrary code within the container's
permissions**. The hardening posture limits the blast radius of that
execution.

In scope:

- The container runs as `claude-user` (uid 1000), not root.
- All Linux capabilities are dropped (`cap_drop: ALL`).
- `no-new-privileges` is set; setuid binaries cannot elevate.
- The root filesystem is mounted read-only. Writable paths are:
  - `/workspace` — the project directory (bind mount from the host)
  - `/home/claude-user/.claude/` — per-project Claude Code state
  - `/home/claude-user/.claude.json` — per-project Claude Code config
  - `/tmp` — RAM-backed tmpfs (lost on container exit)
- SUID/SGID bits are stripped from every file in the base image at
  build time.
- The per-project state directory on the host is created with mode
  `0700` so OAuth credentials are not readable by other local users.
- The container has access to the host network stack (default Docker
  bridge networking), but no host ports are exposed unless the user's
  config lists them under `ports:`.

Out of scope:

- The host kernel. A kernel-level container escape (via an unpatched
  CVE in cgroups, namespaces, etc.) bypasses every guarantee here.
- The Docker daemon. A user with daemon access can override every
  hardening setting; `connie` cannot defend against an attacker who
  already has `docker` group membership on the host.
- The contents of `/workspace`. Anything the container can write
  there persists to the host's project directory — that is by design,
  since the point of the workspace is to let Claude Code modify
  project files.
- Network destinations. Outbound traffic from the container is not
  filtered by `connie`. If a hardened egress posture matters for your
  threat model, run `connie` inside a network namespace that enforces
  it externally.

---

## Known Limitations

These are accepted risks documented for transparency, not bugs:

- **Unpinned package versions.** `src/config/defaults.yml` packages
  are installed via `apk add --no-cache <name>` without a version
  pin. A rebuild months later may pick up newer Alpine packages.
  Pinning would improve reproducibility at the cost of staleness.
- **Build-time setup commands.** Anything a user puts in their
  project config's `build_commands` runs as `claude-user` during
  image build with full network access. The user is responsible for
  trusting what they install.
- **Host-mounted Claude Code state.** OAuth credentials and
  conversation history sit on the host filesystem at
  `$XDG_STATE_HOME/connie/<slug>/`. Host-level compromise (a
  malicious browser extension, another user with `sudo`) can read
  them. The 0700 perm reduces but does not eliminate the exposure.

---

## Supply Chain

- The Claude Code installer is downloaded from `https://claude.ai/install.sh`
  during base image build and **its SHA256 is verified** against a
  pinned value in `src/docker/base.Dockerfile`. If Anthropic ships a
  new installer the build will fail loudly until the pin is updated;
  see the comment in `base.Dockerfile` for the update procedure.
- Alpine base image: pinned by content-addressed digest (not just the
  `alpine:3.20` tag) in `src/docker/base.Dockerfile`. Docker Hub does
  not guarantee tag immutability, so the digest is what keeps a rebuild
  reproducible — a re-push to `alpine:3.20` cannot silently change what
  the base image starts from. See the update procedure in
  `base.Dockerfile` for bumping it.
- All other tooling (yq, hadolint, markdownlint, shellcheck) is
  installed by the contributor outside the container — not part of
  the runtime supply chain.
