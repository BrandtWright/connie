# =============================================================================
# connie base image
#
# Adapted from Dockerfile.agent — same structure and user setup, minus SSH
# and project-specific tooling (Ansible, Python, github-cli). Those can be
# added per-project via .devbox/.containerrc packages.
#
# Runs as non-root from the start. All hardening (cap-drop, read-only root,
# resource limits) is applied at runtime via docker-compose.yml.
#
# To rebuild after an upgrade:
#   connie build-base
# =============================================================================

FROM alpine:3.20

RUN apk add --no-cache \
    # Shell and core utilities
    bash \
    coreutils \
    grep \
    sed \
    gawk \
    findutils \
    # Version control
    git \
    # Networking
    curl \
    wget \
    # Search and file tools
    ripgrep \
    fd \
    jq \
    tree \
    file \
    # Terminal capability database — lets forwarded TERM values (xterm-256color,
    # screen-256color, etc.) resolve so TUI tools render correctly in-container
    ncurses-terminfo-base \
    # Archive tools
    tar \
    gzip \
    unzip \
    # Build tools (required for native npm packages)
    build-base \
    # Process and system
    lsof \
    # Required by Node.js native modules and nvm on Alpine
    libgcc \
    libstdc++ \
    linux-headers

RUN addgroup -g 1000 claude-user \
    && adduser -D -u 1000 -G claude-user -s /bin/bash -h /home/claude-user claude-user

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
USER claude-user
RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH="/home/claude-user/.local/bin:${PATH}"
ENV DISABLE_AUTOUPDATER=1

USER root
RUN mkdir -p /workspace && chown claude-user:claude-user /workspace \
    && find / -perm /6000 -type f -exec chmod a-s {} + 2>/dev/null || true

COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

USER claude-user
WORKDIR /workspace
ENV HOME=/home/claude-user
ENV GIT_TERMINAL_PROMPT=0

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["claude"]
