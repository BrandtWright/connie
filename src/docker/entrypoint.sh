#!/bin/sh
# connie container entrypoint
# Sets up the runtime environment then hands off to the container command.
# Uses exec so the command replaces this shell and runs as PID 1.
set -eu

# Guard against Docker auto-creating ~/.claude.json as a directory.
# This happens when the file does not exist on the host before bind-mounting.
# connie run pre-creates it with 'printf' but check defensively anyway.
if [ -d "$HOME/.claude.json" ]; then
    printf 'error: %s/.claude.json is a directory (expected a file)\n' "$HOME" >&2
    printf 'Run: printf "{}" > ~/.claude.json on the host and try again.\n' >&2
    exit 1
fi

# Redirect all XDG user directories to writable locations.
# With a read-only root filesystem, the default locations under ~ are not
# writable. Claude Code's interactive mode writes to several of these at
# startup and hangs silently if the writes fail.
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-/tmp/.cache}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-/tmp/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-/tmp/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-/tmp/.local/state}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime}"

# Pre-create the directories so tools don't fail on first write.
mkdir -p "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" \
    "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR"

# Redirect git global config to /tmp — the root filesystem is read-only.
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/tmp/.gitconfig}"

# Configure git identity from environment variables if provided.
[ -n "${GIT_USER_NAME:-}" ] && git config --global user.name "$GIT_USER_NAME"
[ -n "${GIT_USER_EMAIL:-}" ] && git config --global user.email "$GIT_USER_EMAIL"

# Mark /workspace as safe so git doesn't refuse to operate on it.
# Bind-mounted directories are owned by the host user, not the container
# user, which triggers git's dubious ownership check.
git config --global --add safe.directory /workspace 2>/dev/null || true

# Show what command is about to run — helps diagnose startup issues.
printf 'connie entrypoint: exec %s\n' "$*" >&2

exec "$@"
