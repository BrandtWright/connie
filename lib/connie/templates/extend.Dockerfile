# .devbox/extend.Dockerfile
# Managed by connie — do not edit directly.
# To install packages into the container, add them to
# .devbox/.containerrc under the 'packages' or 'build_commands' keys.
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

USER claude-user
RUN if [ -n "$BUILD_COMMANDS" ]; then \
        sh -c "$BUILD_COMMANDS"; \
    fi
