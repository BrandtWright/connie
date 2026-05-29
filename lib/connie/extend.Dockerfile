# lib/connie/extend.Dockerfile
# Per-project build template — shared across all projects, not per-project.
# To install packages into the container, add them to
# .connie/.containerrc under the 'packages' or 'build_commands' keys.
#
# The base image is the locally built connie base image, which includes
# Alpine Linux, core utilities, git, Node.js, and Claude Code.
#
# EXTRA_PACKAGES is injected at build time from .containerrc by connie.
# BUILD_COMMANDS runs arbitrary shell commands after package installation.
# If neither has changed since the last build, Docker's layer cache
# means both steps complete instantly.

FROM connie/base:latest

ARG EXTRA_PACKAGES
ARG BUILD_COMMANDS

USER root
RUN if [ -n "$EXTRA_PACKAGES" ]; then \
        apk add --no-cache $EXTRA_PACKAGES; \
    fi

# Set npm global prefix to a user-writable location already on PATH.
# Without this, 'npm install -g' fails because the apk-installed npm
# defaults to a root-owned system prefix that claude-user cannot write to.
USER claude-user
ENV NPM_CONFIG_PREFIX=/home/claude-user/.local
RUN if [ -n "$BUILD_COMMANDS" ]; then \
        sh -c "$BUILD_COMMANDS"; \
    fi
