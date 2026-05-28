# connie Makefile

PREFIX   ?= /usr/local
BINDIR   := $(PREFIX)/bin
LIBDIR   := $(PREFIX)/lib/connie

INSTALL  := install

# ── Phony targets ─────────────────────────────────────────────────────────────

.PHONY: all install uninstall check help

all: help

help:
	@echo "connie make targets:"
	@echo ""
	@echo "  install    Install connie to PREFIX (default: /usr/local)"
	@echo "  uninstall  Remove connie from PREFIX"
	@echo "  check      Syntax-check the CLI script"
	@echo ""
	@echo "Override PREFIX to install without sudo:"
	@echo "  make install PREFIX=~/.local"
	@echo ""
	@echo "Then run 'connie init <dir>' and 'connie run' — base image builds automatically."

# ── Install ───────────────────────────────────────────────────────────────────

install: check
	@echo "==> Installing connie to $(PREFIX)"
	$(INSTALL) -d $(BINDIR)
	$(INSTALL) -d $(LIBDIR)/templates
	$(INSTALL) -d $(LIBDIR)/config
	$(INSTALL) -m 755 $(CURDIR)/bin/connie                              $(BINDIR)/connie
	$(INSTALL) -m 644 $(CURDIR)/lib/connie/base.Dockerfile              $(LIBDIR)/base.Dockerfile
	$(INSTALL) -m 755 $(CURDIR)/lib/connie/entrypoint.sh                $(LIBDIR)/entrypoint.sh
	$(INSTALL) -m 644 $(CURDIR)/lib/connie/templates/.containerrc       $(LIBDIR)/templates/.containerrc
	$(INSTALL) -m 644 $(CURDIR)/lib/connie/templates/docker-compose.yml $(LIBDIR)/templates/docker-compose.yml
	$(INSTALL) -m 644 $(CURDIR)/lib/connie/templates/extend.Dockerfile  $(LIBDIR)/templates/extend.Dockerfile
	$(INSTALL) -m 644 $(CURDIR)/lib/connie/config/defaults.yml          $(LIBDIR)/config/defaults.yml
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
	@echo "==> Checking bin/connie syntax"
	@sh -n $(CURDIR)/bin/connie && echo "    OK"
