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
DRIVE ?= D:\\

# Discover available projects (platform-independent, uses Make builtins)
AVAILABLE_PROJECTS := $(patsubst $(PROJECTS_DIR)/%/,%,$(wildcard $(PROJECTS_DIR)/*/))

# Sub-targets for building/simulating/cleaning individual projects
BUILD_TARGETS := $(addprefix build-,$(AVAILABLE_PROJECTS))
SIM_TARGETS   := $(addprefix sim-,$(AVAILABLE_PROJECTS))
CLEAN_TARGETS := $(addprefix clean-,$(AVAILABLE_PROJECTS))

# --- Positional project argument ---
# Any command-line word that isn't a known target is treated as the project,
# but only when a project-accepting target (build/sim/program/clean) is present.
_KNOWN_TARGETS := help build sim program upload clean clean-tests list setup lint test \
  docker-build docker-shell docker-down \
  $(BUILD_TARGETS) $(SIM_TARGETS) $(CLEAN_TARGETS)
_PROJECT_TARGETS := build sim program upload clean

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

# Discover test directories (each subdir of tests/ with a Makefile)
TESTS_DIR := tests
TEST_DIRS := $(patsubst $(TESTS_DIR)/%/Makefile,%,$(wildcard $(TESTS_DIR)/*/Makefile))

.PHONY: help check-docker docker-build docker-shell docker-down setup lint test build sim program upload clean clean-tests list $(BUILD_TARGETS) $(SIM_TARGETS) $(CLEAN_TARGETS) $(TEST_TARGETS)

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
	$(info   make upload <project> [DRIVE=<path>] - Copy bitstream to USB drive)
	$(info )
	$(info   <project> = full name or unambiguous prefix, e.g. 01_blinky or 01.)
	$(info   [<project>] is optional -- omit to run on all projects.)
	$(info   DRIVE defaults to D:\ (Windows). Linux example: DRIVE=/media/$$USER/iCESugar-Pro)
	$(info )
	$(info Setup:)
	$(info   make setup               - Install pre-commit hooks (runs locally))
	$(info   make lint                - Run linters on all files (runs in Docker))
	$(info   make test               - Run RTL unit tests (cocotb, runs in Docker))
	$(info )
	$(info Docker targets:)
	$(info   make docker-build        - Build the FPGA toolchain container)
	$(info   make docker-shell        - Open interactive shell in container)
	$(info   make docker-down         - Stop and remove container)
	@cd .

# =============================================================================
# Setup and lint targets
# =============================================================================

check-docker:
ifeq ($(OS),Windows_NT)
	@docker info >nul 2>&1 || (echo ERROR: Docker is not running. Please start Docker Desktop and try again. & exit /b 1)
else
	@docker info > /dev/null 2>&1 || (echo "ERROR: Docker is not running. Please start Docker Desktop and try again." && exit 1)
endif

setup:
	pre-commit install

lint: check-docker
	$(DOCKER_RUN) pre-commit run --all-files

TEST_TARGETS := $(addprefix test-,$(TEST_DIRS))

test: check-docker $(TEST_TARGETS)

$(TEST_TARGETS): test-%: check-docker
	$(DOCKER_RUN) make -C $(TESTS_DIR)/$* SIM=icarus

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

build: check-docker
ifdef PROJECT
	$(call check_project,build)
	$(DOCKER_RUN) make -C $(PROJECTS_DIR)/$(PROJECT) all
else
	$(info Building all projects...)
	@$(MAKE) --no-print-directory $(BUILD_TARGETS)
endif

$(BUILD_TARGETS): build-%:
	-@$(DOCKER_RUN) make -C $(PROJECTS_DIR)/$* all

sim: check-docker
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

upload:
	$(call check_project,upload)
ifeq ($(OS),Windows_NT)
	copy $(subst /,\,$(PROJECTS_DIR)\$(PROJECT)\build\*.bit) $(DRIVE)
else
	cp $(PROJECTS_DIR)/$(PROJECT)/build/*.bit $(DRIVE)
endif

clean: check-docker
ifdef PROJECT
	$(call check_project,clean)
	$(DOCKER_RUN) make -C $(PROJECTS_DIR)/$(PROJECT) clean
else
	$(info Cleaning all projects and tests...)
	@$(MAKE) --no-print-directory $(CLEAN_TARGETS) clean-tests
endif

$(CLEAN_TARGETS): clean-%:
	-@$(DOCKER_RUN) make -C $(PROJECTS_DIR)/$* clean

clean-tests: check-docker
	$(DOCKER_RUN) sh -c "rm -rf $(TESTS_DIR)/*/sim_build $(TESTS_DIR)/*/results.xml"

# =============================================================================
# Docker targets
# =============================================================================

docker-build: check-docker
	$(DOCKER_COMPOSE) build

docker-shell: check-docker
	$(DOCKER_RUN) bash

docker-down: check-docker
	$(DOCKER_COMPOSE) down
