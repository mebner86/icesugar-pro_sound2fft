# iCESugar-Pro Sound2FFT Project
# Top-level Makefile

# On Windows, force cmd.exe so ifeq branches match the active shell.
# On Linux/macOS, Make defaults to /bin/sh which is correct.
ifeq ($(OS),Windows_NT)
SHELL := cmd.exe
.SHELLFLAGS := /c
endif

# Project selection — supports positional arg or explicit variable:
#   make build 03       (positional, prefix-matched)
#   make build PROJECT=03_i2s_loopback   (explicit)
PROJECT ?=
PROJECTS_DIR := projects

# Discover available projects (platform-independent, uses Make builtins)
AVAILABLE_PROJECTS := $(patsubst $(PROJECTS_DIR)/%/,%,$(wildcard $(PROJECTS_DIR)/*/))

# Sub-targets for building/simulating/cleaning individual projects
BUILD_TARGETS := $(addprefix build-,$(AVAILABLE_PROJECTS))
SIM_TARGETS   := $(addprefix sim-,$(AVAILABLE_PROJECTS))
CLEAN_TARGETS := $(addprefix clean-,$(AVAILABLE_PROJECTS))

# --- Positional project argument ---
# Any command-line word that isn't a known target is treated as the project,
# but only when a project-accepting target (build/sim/program/clean) is present.
_KNOWN_TARGETS := help build sim program clean list setup lint \
  docker-build docker-shell docker-down \
  $(BUILD_TARGETS) $(SIM_TARGETS) $(CLEAN_TARGETS)
_PROJECT_TARGETS := build sim program clean

_EXTRA_GOALS := $(filter-out $(_KNOWN_TARGETS),$(MAKECMDGOALS))
ifneq ($(_EXTRA_GOALS),)
  ifeq ($(filter $(_PROJECT_TARGETS),$(MAKECMDGOALS)),)
    $(error Unknown command: $(_EXTRA_GOALS). Run 'make help' for usage)
  endif
  ifneq ($(words $(_EXTRA_GOALS)),1)
    $(error Unexpected extra arguments: $(_EXTRA_GOALS))
  endif
  ifneq ($(PROJECT),)
    $(error Conflicting project: positional '$(_EXTRA_GOALS)' and PROJECT=$(PROJECT))
  endif
  override PROJECT := $(_EXTRA_GOALS)
endif

# --- Resolve PROJECT abbreviations ---
# Exact match first, then prefix. Errors on 0 or 2+ matches.
ifdef PROJECT
  _PROJ_MATCHES := $(filter $(PROJECT),$(AVAILABLE_PROJECTS))
  ifeq ($(_PROJ_MATCHES),)
    _PROJ_MATCHES := $(filter $(PROJECT)%,$(AVAILABLE_PROJECTS))
  endif
  ifneq ($(words $(_PROJ_MATCHES)),1)
    ifeq ($(_PROJ_MATCHES),)
      $(error No project matching '$(PROJECT)'. Available: $(AVAILABLE_PROJECTS))
    else
      $(error Ambiguous project '$(PROJECT)' matches: $(_PROJ_MATCHES))
    endif
  endif
  override PROJECT := $(_PROJ_MATCHES)
endif

# Swallow positional arg so Make doesn't error on unknown target
ifneq ($(_EXTRA_GOALS),)
.PHONY: $(_EXTRA_GOALS)
$(_EXTRA_GOALS):
	@cd .
endif

# Docker commands
DOCKER_COMPOSE := docker compose -f docker/docker-compose.yml
DOCKER_RUN := $(DOCKER_COMPOSE) run --rm fpga-dev

.PHONY: help docker-build docker-shell docker-down setup lint build sim program clean list $(BUILD_TARGETS) $(SIM_TARGETS) $(CLEAN_TARGETS)

# =============================================================================
# Default target
# =============================================================================

help:
	$(info iCESugar-Pro Sound2FFT - Build System)
	$(info )
	$(info Project targets:)
	$(info   make list                - List available projects)
	$(info   make build [<project>]   - Build bitstream)
	$(info   make sim [<project>]     - Run simulation)
	$(info   make clean [<project>]   - Clean build files)
	$(info   make program <project>   - Program FPGA)
	$(info )
	$(info   <project> = full name or unambiguous prefix, e.g. 01_blinky or 01.)
	$(info   [<project>] is optional — omit to run on all projects.)
	$(info )
	$(info Setup (runs in Docker):)
	$(info   make setup               - Install pre-commit hooks)
	$(info   make lint                - Run linters on all files)
	$(info )
	$(info Docker targets:)
	$(info   make docker-build        - Build the FPGA toolchain container)
	$(info   make docker-shell        - Open interactive shell in container)
	$(info   make docker-down         - Stop and remove container)
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

# Validate PROJECT is set (abbreviation resolution above already ensures it exists)
define check_project
$(if $(PROJECT),,$(error No project specified. Usage: make $(1) <project>. Available: $(AVAILABLE_PROJECTS)))
endef

list:
	$(info Available projects:)
	$(foreach p,$(AVAILABLE_PROJECTS),$(info   - $(p)))
	@cd .

build:
ifdef PROJECT
	$(call check_project,build)
	$(DOCKER_RUN) make -C $(PROJECTS_DIR)/$(PROJECT) all
else
	$(info Building all projects...)
	@$(MAKE) --no-print-directory $(BUILD_TARGETS)
endif

$(BUILD_TARGETS): build-%:
	-@$(DOCKER_RUN) make -C $(PROJECTS_DIR)/$* all

sim:
ifdef PROJECT
	$(call check_project,sim)
	$(DOCKER_RUN) make -C $(PROJECTS_DIR)/$(PROJECT) sim
else
	$(info Simulating all projects...)
	@$(MAKE) --no-print-directory $(SIM_TARGETS)
endif

$(SIM_TARGETS): sim-%:
	-@$(DOCKER_RUN) make -C $(PROJECTS_DIR)/$* sim

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
