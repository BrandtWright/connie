# connie Makefile

PREFIX   ?= /usr/local
BINDIR   := $(PREFIX)/bin
LIBDIR   := $(PREFIX)/lib/connie

INSTALL  := install

# ── Phony targets ─────────────────────────────────────────────────────────────

.PHONY: all install uninstall check test help

all: help

help:
	@echo "connie make targets:"
	@echo ""
	@echo "  install    Install connie to PREFIX (default: /usr/local)"
	@echo "  uninstall  Remove connie from PREFIX"
	@echo "  check      Syntax-check the CLI script (sh -n)"
	@echo "  test       Run the POSIX shell test suite (tests/run.sh)"
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

test:
	@sh $(CURDIR)/tests/run.sh
