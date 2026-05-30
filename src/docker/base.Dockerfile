# =============================================================================
# connie base image
#
# Alpine 3.20 + core tools + non-root claude-user (uid 1000) + Claude Code.
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

# Install Claude Code. The installer is downloaded from the public URL
# and its SHA256 is verified BEFORE execution — this closes the
# `curl | bash` supply-chain hole. If Anthropic ships a new installer,
# the build fails loudly here until the pin is refreshed.
#
# Updating the pin (when an Anthropic release breaks the build):
#   1. Confirm the new installer is genuinely from Anthropic
#      (compare the URL response on multiple networks, or fetch via
#      the published Anthropic docs link, not from this Dockerfile).
#   2. Compute the new SHA:  curl -fsSL https://claude.ai/install.sh | sha256sum
#   3. Replace the value below.
#   4. Note the change in docs/CHANGELOG.md under the next release.
ARG CLAUDE_INSTALLER_SHA256=005ec1a937f32dfbb74f9e810287bcb12cba2d5cae4c9277aa8c6364adbf1787
RUN curl -fsSL https://claude.ai/install.sh -o /tmp/install-claude.sh \
    && echo "${CLAUDE_INSTALLER_SHA256}  /tmp/install-claude.sh" | sha256sum -c - \
    && bash /tmp/install-claude.sh \
    && rm /tmp/install-claude.sh

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
