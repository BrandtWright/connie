# connie Makefile

PREFIX   ?= /usr/local
BINDIR   := $(PREFIX)/bin
LIBDIR   := $(PREFIX)/lib/connie

INSTALL  := install

# ── Phony targets ─────────────────────────────────────────────────────────────

# ANSI escapes for help text. Bare $$ resolves to a literal $ in a recipe
# (Make consumes one round) which printf then sees. Wrapped in $(shell ...)
# so non-TTY callers (CI, piped output) get plain text.
BOLD := $(shell printf '\033[1m')
DIM  := $(shell printf '\033[2m')
RST  := $(shell printf '\033[0m')

.PHONY: all install install-dev install-hooks uninstall check lint \
        lint-sh lint-md lint-docker lint-yaml format format-check \
        test test-docker watch help

all: help

help:
	@printf '$(BOLD)connie$(RST) — Claude Code in a constrained, reproducible container\n\n'
	@printf '$(BOLD)Install$(RST)\n'
	@printf '  install         Install connie to PREFIX (default: /usr/local)\n'
	@printf '  install-dev     Install to ~/.local + set up the pre-commit hook\n'
	@printf '  install-hooks   Set up the pre-commit hook only\n'
	@printf '  uninstall       Remove connie from PREFIX\n\n'
	@printf '$(BOLD)Lint and format$(RST)\n'
	@printf '  check           Syntax-check src/connie (sh -n)\n'
	@printf '  lint            shellcheck + markdownlint + hadolint + yq parse\n'
	@printf '                  (sub-targets: lint-sh, lint-md, lint-docker, lint-yaml)\n'
	@printf '  format          Auto-format shell scripts with shfmt (writes in place)\n'
	@printf '  format-check    Verify shell scripts match shfmt style without writing\n\n'
	@printf '$(BOLD)Test$(RST)\n'
	@printf '  test            Run the POSIX shell test suite (tests/run.sh)\n'
	@printf '  test-docker     Run the Docker-gated test layer (tests/run-docker.sh)\n'
	@printf '                  Skips if docker is not on PATH.\n'
	@printf '  watch           Re-run tests on every file change (requires entr)\n\n'
	@printf '$(DIM)Test runner flags (sh tests/run.sh ...)$(RST)\n'
	@printf '$(DIM)  --pretty   ANSI-coloured output instead of TAP$(RST)\n'
	@printf '$(DIM)  -v         Verbose: show breadcrumbs even on pass, keep artifacts$(RST)\n'
	@printf '$(DIM)  -f STR     Run only tests whose name contains STR$(RST)\n'
	@printf '$(DIM)  See tests/README.md for full conventions.$(RST)\n\n'
	@printf '$(BOLD)PREFIX$(RST)\n'
	@printf '  Override PREFIX to install without sudo:  make install PREFIX=~/.local\n\n'
	@printf 'Then run "connie init <dir>" and "connie run" — base image builds automatically.\n'

# ── Install ───────────────────────────────────────────────────────────────────

install: check
	@echo "==> Installing connie to $(PREFIX)"
	$(INSTALL) -d $(BINDIR)
	$(INSTALL) -d $(LIBDIR)/docker
	$(INSTALL) -d $(LIBDIR)/config
	$(INSTALL) -m 755 $(CURDIR)/src/connie                              $(BINDIR)/connie
	$(INSTALL) -m 644 $(CURDIR)/src/docker/base.Dockerfile              $(LIBDIR)/docker/base.Dockerfile
	$(INSTALL) -m 755 $(CURDIR)/src/docker/entrypoint.sh                $(LIBDIR)/docker/entrypoint.sh
	$(INSTALL) -m 644 $(CURDIR)/src/docker/docker-compose.yml           $(LIBDIR)/docker/docker-compose.yml
	$(INSTALL) -m 644 $(CURDIR)/src/docker/extend.Dockerfile            $(LIBDIR)/docker/extend.Dockerfile
	$(INSTALL) -m 644 $(CURDIR)/src/config/defaults.yml                 $(LIBDIR)/config/defaults.yml
	$(INSTALL) -m 644 $(CURDIR)/src/config/project.yml                  $(LIBDIR)/config/project.yml
	@echo "==> Done."
	@echo ""
	@echo "    Next: run 'connie init <project-dir>' then 'connie run'."
	@echo "    The base Docker image is built automatically on first run."

# ── Dev install ───────────────────────────────────────────────────────────────
# Convenience target for contributors working in this checkout. Pins PREFIX
# to ~/.local (no sudo) and chains the pre-commit hook install so the lint
# convention is enforced automatically on every commit.
install-dev: PREFIX := $(HOME)/.local
install-dev: install install-hooks
	@echo "==> Dev environment ready."

# ── Pre-commit hook ───────────────────────────────────────────────────────────
# Symlink (not copy) so edits to scripts/pre-commit are picked up immediately
# without reinstalling. Falls back to copy on filesystems where symlinks fail.
install-hooks:
	@if [ ! -d $(CURDIR)/.git ]; then \
		echo "error: not a git checkout — run from the repo root" >&2; \
		exit 1; \
	fi
	@mkdir -p $(CURDIR)/.git/hooks
	@if ln -sf $(CURDIR)/scripts/pre-commit $(CURDIR)/.git/hooks/pre-commit 2>/dev/null; then \
		echo "==> Symlinked .git/hooks/pre-commit → scripts/pre-commit"; \
	else \
		cp $(CURDIR)/scripts/pre-commit $(CURDIR)/.git/hooks/pre-commit; \
		chmod +x $(CURDIR)/.git/hooks/pre-commit; \
		echo "==> Copied .git/hooks/pre-commit (symlink unsupported on this fs)"; \
	fi

# ── Uninstall ─────────────────────────────────────────────────────────────────

uninstall:
	@echo "==> Removing connie from $(PREFIX)"
	rm -f  $(BINDIR)/connie
	rm -rf $(LIBDIR)
	@echo "==> Done."

# ── Development helpers ───────────────────────────────────────────────────────

check:
	@echo "==> Checking src/connie syntax"
	@sh -n $(CURDIR)/src/connie && echo "    OK"

# Aggregate lint: chains four orthogonal linters across every file of the
# matching type. Each sub-target is independently runnable so a contributor
# debugging a single class of failure can iterate fast. Exits non-zero on
# first failure (set -e in the wrapper sub-shell) so CI fails noisily.
lint: lint-sh lint-md lint-docker lint-yaml
	@echo "==> Lint clean."

# The set of shell scripts linted AND format-checked: every *.sh plus the
# extensionless src/connie and scripts/pre-commit. Defined once so lint-sh
# and SHFMT_FILES cannot drift apart and leave a script unchecked.
SH_FIND := -type f \( -name "*.sh" -o -path "$(CURDIR)/src/connie" -o -path "$(CURDIR)/scripts/pre-commit" \) -not -path "$(CURDIR)/.git/*"

lint-sh:
	@echo "==> shellcheck (POSIX sh enforcement)"
	@find $(CURDIR) $(SH_FIND) -print0 \
	  | xargs -0 shellcheck -s sh
	@echo "    OK"

lint-md:
	@echo "==> markdownlint-cli2"
	@cd $(CURDIR) && markdownlint-cli2 \
	    "**/*.md" \
	    "#.git" \
	    "#node_modules"
	@echo "    OK"

lint-docker:
	@echo "==> hadolint"
	@find $(CURDIR) -type f \
	    \( -name "Dockerfile" -o -name "*.Dockerfile" \) \
	    -not -path "$(CURDIR)/.git/*" \
	    -print0 \
	  | xargs -0 hadolint
	@echo "    OK"

lint-yaml:
	@echo "==> yq parse-check"
	@find $(CURDIR) -type f \( -name "*.yml" -o -name "*.yaml" \) \
	    -not -path "$(CURDIR)/.git/*" \
	    -exec sh -c 'yq eval-all "null" "$$1" >/dev/null' _ {} \;
	@echo "    OK"

# shfmt is not pre-installed everywhere; check for it and emit a helpful
# install hint if missing. Uses the same SH_FIND expression as lint-sh so
# the format-check and shellcheck scopes are identical by construction.
SHFMT_FILES = $(shell find $(CURDIR) $(SH_FIND))

format:
	@command -v shfmt >/dev/null 2>&1 || { \
		printf 'shfmt not installed. Install:\n' >&2; \
		printf '  go install mvdan.cc/sh/v3/cmd/shfmt@latest\n' >&2; \
		printf '  or: brew install shfmt  /  apk add shfmt\n' >&2; \
		exit 1; \
	}
	@echo "==> shfmt -w (4-space indent, simplify, POSIX dialect)"
	@shfmt -ln posix -i 4 -ci -s -w $(SHFMT_FILES)
	@echo "    OK"

# Read-only variant — fails if any file would be reformatted. Suitable
# for CI; safe to wire into the pre-commit hook later.
format-check:
	@if ! command -v shfmt >/dev/null 2>&1; then \
		printf 'shfmt not installed; skipping format-check.\n' >&2; \
		exit 0; \
	fi; \
	echo "==> shfmt -d (diff against formatted version)"; \
	shfmt -ln posix -i 4 -ci -s -d $(SHFMT_FILES) && echo "    OK"

test:
	@sh $(CURDIR)/tests/run.sh

test-docker:
	@sh $(CURDIR)/tests/run-docker.sh

# Watch every git-tracked file and rerun the test suite on change.
# Wraps tests/watch.sh (which uses entr); extra args go to run.sh:
#   make watch -- --pretty -f slug
watch:
	@sh $(CURDIR)/tests/watch.sh $(filter-out watch,$(MAKECMDGOALS))
