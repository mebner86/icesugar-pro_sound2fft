# iCESugar-Pro Sound2FFT Project
# Top-level Makefile

.PHONY: help docker-build docker-shell docker-down setup lint

# Default target
help:
	@echo "iCESugar-Pro Sound2FFT - Build System"
	@echo ""
	@echo "Setup:"
	@echo "  make setup          - Install pre-commit hooks"
	@echo "  make lint           - Run pre-commit on all files"
	@echo ""
	@echo "Docker targets:"
	@echo "  make docker-build   - Build the FPGA toolchain container"
	@echo "  make docker-shell   - Open interactive shell in container"
	@echo "  make docker-down    - Stop and remove container"

# =============================================================================
# Setup targets
# =============================================================================

setup:
	@command -v pre-commit >/dev/null 2>&1 || { \
		echo "Error: pre-commit is not installed."; \
		echo ""; \
		echo "Install it with one of:"; \
		echo "  pipx install pre-commit   (recommended)"; \
		echo "  pip install pre-commit"; \
		echo "  brew install pre-commit   (macOS)"; \
		echo "  apt install pre-commit    (Debian/Ubuntu)"; \
		exit 1; \
	}
	pre-commit install

lint:
	@command -v pre-commit >/dev/null 2>&1 || { \
		echo "Error: pre-commit is not installed. Run 'make setup' first."; \
		exit 1; \
	}
	pre-commit run --all-files

# =============================================================================
# Docker targets
# =============================================================================

DOCKER_COMPOSE := docker compose -f docker/docker-compose.yml
DOCKER_RUN := $(DOCKER_COMPOSE) run --rm fpga-dev

docker-build:
	$(DOCKER_COMPOSE) build

docker-shell:
	$(DOCKER_RUN) bash

docker-down:
	$(DOCKER_COMPOSE) down
