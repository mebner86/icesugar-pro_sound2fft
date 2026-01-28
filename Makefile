# iCESugar-Pro Sound2FFT Project
# Top-level Makefile

# Project selection (use PROJECT=name to specify)
PROJECT ?=
PROJECTS_DIR := projects

# List available projects
AVAILABLE_PROJECTS := $(shell ls -d $(PROJECTS_DIR)/*/ 2>/dev/null | xargs -n1 basename)

.PHONY: help docker-build docker-shell docker-down setup lint build sim program clean list-projects

# Default target
help:
	@echo "iCESugar-Pro Sound2FFT - Build System"
	@echo ""
	@echo "Project targets (use PROJECT=<name>):"
	@echo "  make build PROJECT=01_blinky   - Build bitstream for project"
	@echo "  make sim PROJECT=01_blinky     - Run simulation for project"
	@echo "  make program PROJECT=01_blinky - Program FPGA with project"
	@echo "  make clean PROJECT=01_blinky   - Clean project build files"
	@echo "  make list-projects             - List available projects"
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
# Project targets
# =============================================================================

# Helper to check PROJECT is set
define check_project
	@if [ -z "$(PROJECT)" ]; then \
		echo "Error: PROJECT not specified."; \
		echo "Usage: make $(1) PROJECT=<project_name>"; \
		echo ""; \
		echo "Available projects:"; \
		for p in $(AVAILABLE_PROJECTS); do echo "  - $$p"; done; \
		exit 1; \
	fi
	@if [ ! -d "$(PROJECTS_DIR)/$(PROJECT)" ]; then \
		echo "Error: Project '$(PROJECT)' not found in $(PROJECTS_DIR)/"; \
		echo ""; \
		echo "Available projects:"; \
		for p in $(AVAILABLE_PROJECTS); do echo "  - $$p"; done; \
		exit 1; \
	fi
endef

list-projects:
	@echo "Available projects:"
	@for p in $(AVAILABLE_PROJECTS); do echo "  - $$p"; done

build:
	$(call check_project,build)
	$(DOCKER_RUN) make -C $(PROJECTS_DIR)/$(PROJECT) all

sim:
	$(call check_project,sim)
	$(DOCKER_RUN) make -C $(PROJECTS_DIR)/$(PROJECT) sim

program:
	$(call check_project,program)
	$(MAKE) -C $(PROJECTS_DIR)/$(PROJECT) program

clean:
ifndef PROJECT
	@echo "Cleaning all projects..."
	@for p in $(AVAILABLE_PROJECTS); do \
		echo "Cleaning $$p..."; \
		$(MAKE) -C $(PROJECTS_DIR)/$$p clean 2>/dev/null || true; \
	done
else
	$(call check_project,clean)
	$(MAKE) -C $(PROJECTS_DIR)/$(PROJECT) clean
endif

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
