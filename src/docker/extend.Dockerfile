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
#   CONNIE_CONTEXT   managed-policy Claude Code context, written to
#                    /etc/claude-code/CLAUDE.md inside the image so Claude
#                    Code loads it on every session as the highest-priority,
#                    immutable scope describing the container environment.
# If a build arg has not changed since the last build, Docker's layer cache
# means the corresponding step completes instantly.

# BASE_IMAGE is a "global" ARG — it must appear before the first FROM
# so it can be referenced in the FROM line. ARGs declared after FROM
# are scoped to a build stage.
ARG BASE_IMAGE=connie/base:latest
FROM ${BASE_IMAGE}

ARG EXTRA_PACKAGES
ARG BUILD_COMMANDS
ARG CONNIE_CONTEXT

USER root
# `--` stops apk option parsing so a package token cannot inject an apk flag
# (e.g. --allow-untrusted); connie also rejects leading-dash package names
# before this runs. $EXTRA_PACKAGES stays unquoted to word-split the list.
RUN if [ -n "$EXTRA_PACKAGES" ]; then \
        apk add --no-cache -- $EXTRA_PACKAGES; \
    fi

RUN if [ -n "$CONNIE_CONTEXT" ]; then \
        mkdir -p /etc/claude-code && \
        printf '%s' "$CONNIE_CONTEXT" > /etc/claude-code/CLAUDE.md; \
    fi

# Set npm global prefix to a user-writable location already on PATH.
# Without this, 'npm install -g' fails because the apk-installed npm
# defaults to a root-owned system prefix that claude-user cannot write to.
USER claude-user
ENV NPM_CONFIG_PREFIX=/home/claude-user/.local
RUN if [ -n "$BUILD_COMMANDS" ]; then \
        sh -c "$BUILD_COMMANDS"; \
    fi
