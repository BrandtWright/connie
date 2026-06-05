# src/docker/extend.Dockerfile
# Per-project build template — shared across all projects, not per-project.
# To install packages into the container, add them to
# ~/.config/connie/projects/<slug>/config.yml under the 'packages' or 'build_commands' keys.
#
# The base image is the locally built connie base image, which includes
# Alpine Linux, core utilities, git, Node.js, and Claude Code.
#
# Build args injected by connie from the merged config:
#   BASE_IMAGE       the locally-tagged base to FROM (defaults to the
#                    production tag; tests override via $CONNIE_BASE_IMAGE
#                    so the per-project image can be built atop an isolated
#                    base without touching the user's real production tag)
#   EXTRA_PACKAGES   apk packages to install
#   BUILD_COMMANDS   arbitrary shell commands run as claude-user
# If a build arg has not changed since the last build, Docker's layer cache
# means the corresponding step completes instantly.
#
# connie's own context is no longer baked into the image; it is appended to
# Claude's system prompt at run time via `claude --append-system-prompt` (the
# launch command in the generated Compose override). See docs/context.md.

# BASE_IMAGE is a "global" ARG — it must appear before the first FROM
# so it can be referenced in the FROM line. ARGs declared after FROM
# are scoped to a build stage.
ARG BASE_IMAGE=connie/base:latest
FROM ${BASE_IMAGE}

ARG EXTRA_PACKAGES
ARG BUILD_COMMANDS

USER root
# `--` stops apk option parsing so a package token cannot inject an apk flag
# (e.g. --allow-untrusted); connie also rejects leading-dash package names
# before this runs. $EXTRA_PACKAGES stays unquoted to word-split the list.
#
# Re-strip SUID/SGID bits AFTER installing user packages. base.Dockerfile
# strips them, but that runs before this layer, so a user-added apk package
# shipping a setuid binary (su, mount, sudo, …) would otherwise keep its bit
# in the per-project image — contradicting the "every file is stripped"
# guarantee in SECURITY.md/DESIGN.md and the managed-policy context. The
# `&&` keeps an apk failure fatal; the strip's own `|| true` mirrors base.
RUN if [ -n "$EXTRA_PACKAGES" ]; then \
        apk add --no-cache -- $EXTRA_PACKAGES \
        && { find / -perm /6000 -type f -exec chmod a-s {} + 2>/dev/null || true; }; \
    fi

# Set npm global prefix to a user-writable location already on PATH.
# Without this, 'npm install -g' fails because the apk-installed npm
# defaults to a root-owned system prefix that claude-user cannot write to.
USER claude-user
ENV NPM_CONFIG_PREFIX=/home/claude-user/.local
RUN if [ -n "$BUILD_COMMANDS" ]; then \
        sh -c "$BUILD_COMMANDS"; \
    fi
