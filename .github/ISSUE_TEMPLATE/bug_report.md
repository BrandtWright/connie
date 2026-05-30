---
name: Bug report
about: Something connie does that contradicts its documented behaviour
title: ''
labels: bug
---

## What happened

<!-- Describe the actual behaviour you observed. -->

## What you expected

<!-- Describe the behaviour you expected, ideally with a pointer to where
     in the docs it's described. -->

## Reproduction

```sh
# Exact commands you ran, starting from a known state.
# Prefer a minimal scratch project if possible.
```

## Environment

- connie version: <!-- `connie --version` or VERSION in src/connie -->
- Docker: <!-- `docker --version` -->
- Docker Compose: <!-- `docker compose version` -->
- OS / kernel: <!-- `uname -srv` -->
- Shell: <!-- `echo $0` and `$($SHELL --version | head -1)` -->

## Output

<!-- Paste relevant output. For docker-related failures, include
     stderr — most connie errors put the actionable info there. -->

```text

```

## Already tried

<!-- Optional: things you ruled out (e.g. `docker info` works,
     `connie clean && connie run` doesn't help, etc.). -->
