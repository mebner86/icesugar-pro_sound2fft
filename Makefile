# iCESugar-Pro Sound2FFT Project
# Top-level Makefile

# On Windows, force cmd.exe so ifeq branches match the active shell.
# On Linux/macOS, Make defaults to /bin/sh which is correct.
ifeq ($(OS),Windows_NT)
SHELL := cmd.exe
.SHELLFLAGS := /c
endif

# Project selection (use PROJECT=name to specify)
PROJECT ?=
PROJECTS_DIR := projects

# Discover available projects (platform-independent, uses Make builtins)
AVAILABLE_PROJECTS := $(patsubst $(PROJECTS_DIR)/%/,%,$(wildcard $(PROJECTS_DIR)/*/))

# Docker commands
DOCKER_COMPOSE := docker compose -f docker/docker-compose.yml
DOCKER_RUN := $(DOCKER_COMPOSE) run --rm fpga-dev

# Sub-targets for cleaning individual projects
CLEAN_TARGETS := $(addprefix clean-,$(AVAILABLE_PROJECTS))

.PHONY: help docker-build docker-shell docker-down setup lint build sim program clean list-projects $(CLEAN_TARGETS)

# =============================================================================
# Default target
# =============================================================================

help:
	$(info iCESugar-Pro Sound2FFT - Build System)
	$(info )
	$(info Project targets (use PROJECT=<name>):)
	$(info   make build PROJECT=01_blinky   - Build bitstream for project)
	$(info   make sim PROJECT=01_blinky     - Run simulation for project)
	$(info   make program PROJECT=01_blinky - Program FPGA with project)
	$(info   make clean PROJECT=01_blinky   - Clean project build files)
	$(info   make list-projects             - List available projects)
	$(info )
	$(info Setup (runs in Docker):)
	$(info   make setup          - Install pre-commit hooks)
	$(info   make lint           - Run linters on all files)
	$(info )
	$(info Docker targets:)
	$(info   make docker-build   - Build the FPGA toolchain container)
	$(info   make docker-shell   - Open interactive shell in container)
	$(info   make docker-down    - Stop and remove container)
	@cd .

# =============================================================================
# Setup and lint targets (run inside Docker container)
# =============================================================================

setup:
	$(DOCKER_RUN) pre-commit install

lint:
	$(DOCKER_RUN) pre-commit run --all-files

# =============================================================================
# Project targets
# =============================================================================

# Validate PROJECT is set and exists (pure Make, no shell required)
define check_project
$(if $(PROJECT),,$(error PROJECT not specified. Usage: make $(1) PROJECT=<name>. Available: $(AVAILABLE_PROJECTS)))
$(if $(wildcard $(PROJECTS_DIR)/$(PROJECT)/),,$(error Project '$(PROJECT)' not found in $(PROJECTS_DIR)/. Available: $(AVAILABLE_PROJECTS)))
endef

list-projects:
	$(info Available projects:)
	$(foreach p,$(AVAILABLE_PROJECTS),$(info   - $(p)))
	@cd .

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
ifdef PROJECT
	$(call check_project,clean)
	$(DOCKER_RUN) make -C $(PROJECTS_DIR)/$(PROJECT) clean
else
	$(info Cleaning all projects...)
	@$(MAKE) --no-print-directory $(CLEAN_TARGETS)
endif

$(CLEAN_TARGETS): clean-%:
	-@$(DOCKER_RUN) make -C $(PROJECTS_DIR)/$* clean

# =============================================================================
# Docker targets
# =============================================================================

docker-build:
	$(DOCKER_COMPOSE) build

docker-shell:
	$(DOCKER_RUN) bash

docker-down:
	$(DOCKER_COMPOSE) down
