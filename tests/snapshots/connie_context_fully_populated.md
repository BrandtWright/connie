# Connie Container Environment

You are running inside a connie container. Connie is a CLI that runs Claude
Code in a hardened, reproducible Docker environment scoped to a single
project directory. This file describes the container you are in; the
project itself is described by /workspace/CLAUDE.md (if present).

## Filesystem

- `/workspace` — the project directory, bind-mounted from the host (read/write)
- `/tmp` — ephemeral RAM-backed scratch space (lost on container exit)
- All other paths are read-only at runtime; no process can modify image layers

## Available Tools

Base image: bash, git, curl, wget, ripgrep, fd, jq, tree, file, tar,
gzip, unzip, lsof, and standard Unix utilities.

Project packages (apk): python3, py3-pip

Build-time setup commands:

- pip install black

## Additional Mounts

- /data:/data:ro

## Exposed Ports

- 8080:8080

## Environment Variables

APP_ENV: test

## Resource Limits

Memory: 8g  |  CPUs: 4.0  |  Max PIDs: 1024

## Security Constraints

The container runs as a non-root user (claude-user, uid 1000). All Linux
capabilities are dropped, no-new-privileges is set, the root filesystem is
read-only, and SUID/SGID bits have been stripped at build time. Network
access is available but no ports are exposed to the host unless listed
under Exposed Ports.
