# connie Makefile

PREFIX   ?= /usr/local
BINDIR   := $(PREFIX)/bin
LIBDIR   := $(PREFIX)/lib/connie

INSTALL  := install

# ── Phony targets ─────────────────────────────────────────────────────────────

.PHONY: all install install-dev install-hooks uninstall check lint \
        lint-sh lint-md lint-docker lint-yaml test test-docker help

all: help

help:
	@echo "connie make targets:"
	@echo ""
	@echo "  install        Install connie to PREFIX (default: /usr/local)"
	@echo "  install-dev    Install to ~/.local + set up the pre-commit hook"
	@echo "  install-hooks  Set up the pre-commit hook only"
	@echo "  uninstall      Remove connie from PREFIX"
	@echo "  check          Syntax-check the CLI script (sh -n)"
	@echo "  lint           Run shellcheck + markdownlint + hadolint + yq parse"
	@echo "                 across every file of the matching type. Catches the"
	@echo "                 drift that 'check' alone misses (bashisms, doc style,"
	@echo "                 Dockerfile smells, malformed YAML)."
	@echo "  test           Run the POSIX shell test suite (tests/run.sh)"
	@echo "  test-docker    Run the Docker-gated test layer (tests/run-docker.sh)"
	@echo "                 Skips if docker is not on PATH; otherwise builds"
	@echo "                 real images into a connie-test/* namespace and"
	@echo "                 cleans up after itself."
	@echo ""
	@echo "Test runner accepts flags via 'sh tests/run.sh':"
	@echo "  --pretty   ANSI-coloured output instead of TAP"
	@echo "  -v         Verbose: show breadcrumbs even on pass, keep artifacts"
	@echo "  -f STR     Run only tests whose name contains STR"
	@echo "  See tests/README.md for full conventions."
	@echo ""
	@echo "Override PREFIX to install without sudo:"
	@echo "  make install PREFIX=~/.local"
	@echo ""
	@echo "Then run 'connie init <dir>' and 'connie run' — base image builds automatically."

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

lint-sh:
	@echo "==> shellcheck (POSIX sh enforcement)"
	@find $(CURDIR) -type f \
	    \( -name "*.sh" -o -path "$(CURDIR)/src/connie" \) \
	    -not -path "$(CURDIR)/.git/*" \
	    -print0 \
	  | xargs -0 shellcheck -s sh
	@echo "    OK"

lint-md:
	@echo "==> markdownlint"
	@find $(CURDIR) -type f -name "*.md" \
	    -not -path "$(CURDIR)/.git/*" \
	    -not -path "$(CURDIR)/node_modules/*" \
	    -print0 \
	  | xargs -0 markdownlint
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

test:
	@sh $(CURDIR)/tests/run.sh

test-docker:
	@sh $(CURDIR)/tests/run-docker.sh
