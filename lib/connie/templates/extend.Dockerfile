# .devbox/extend.Dockerfile
# Managed by connie — do not edit directly.
# To install packages into the container, add them to
# .devbox/.containerrc under the 'packages' key.
#
# The base image is the locally built connie base image, which includes
# Alpine Linux, core utilities, git, Node.js, and Claude Code.
#
# EXTRA_PACKAGES is injected at build time from .containerrc by connie.
# If packages have not changed since the last build, Docker's layer cache
# means this step completes instantly.

FROM connie/base:latest

ARG EXTRA_PACKAGES
USER root
RUN if [ -n "$EXTRA_PACKAGES" ]; then \
        apk add --no-cache $EXTRA_PACKAGES; \
    fi
USER claude-user
