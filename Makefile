# iCESugar-Pro Sound2FFT Project
# Top-level Makefile
# Runs inside the VS Code Dev Container (all tools available on PATH).

# Project selection — supports positional arg or explicit variable:
#   make build 03       (positional, prefix-matched)
#   make build PROJECT=03_i2s_loopback   (explicit)
PROJECT ?=
PROJECTS_DIR := projects

# Discover available projects (uses Make builtins)
AVAILABLE_PROJECTS := $(patsubst $(PROJECTS_DIR)/%/,%,$(wildcard $(PROJECTS_DIR)/*/))

# Sub-targets for building/simulating/cleaning individual projects
BUILD_TARGETS := $(addprefix build-,$(AVAILABLE_PROJECTS))
SIM_TARGETS   := $(addprefix sim-,$(AVAILABLE_PROJECTS))
CLEAN_TARGETS := $(addprefix clean-,$(AVAILABLE_PROJECTS))

# --- Positional project argument ---
# Any command-line word that isn't a known target is treated as the project,
# but only when a project-accepting target (build/sim/clean) is present.
_KNOWN_TARGETS := help build sim clean clean-tests list setup lint test \
  $(BUILD_TARGETS) $(SIM_TARGETS) $(CLEAN_TARGETS)
_PROJECT_TARGETS := build sim clean

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
	@:
endif

# Discover test directories (each subdir of tests/ with a Makefile)
TESTS_DIR := tests
TEST_DIRS := $(patsubst $(TESTS_DIR)/%/Makefile,%,$(wildcard $(TESTS_DIR)/*/Makefile))
TEST_TARGETS := $(addprefix test-,$(TEST_DIRS))

.PHONY: help setup lint test build sim clean clean-tests list \
  $(BUILD_TARGETS) $(SIM_TARGETS) $(CLEAN_TARGETS) $(TEST_TARGETS)

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
	$(info )
	$(info   <project> = full name or unambiguous prefix, e.g. 01_blinky or 01.)
	$(info   [<project>] is optional -- omit to run on all projects.)
	$(info )
	$(info Development targets:)
	$(info   make setup               - Install pre-commit hooks)
	$(info   make lint                - Run linters on all files)
	$(info   make test                - Run RTL unit tests (cocotb))
	@:

# =============================================================================
# Setup and lint targets
# =============================================================================

setup:
	pre-commit install

lint:
	pre-commit run --all-files

test: $(TEST_TARGETS)

$(TEST_TARGETS): test-%:
	$(MAKE) -C $(TESTS_DIR)/$* SIM=icarus

# =============================================================================
# Project targets
# =============================================================================

define check_project
$(if $(PROJECT),,$(error No project specified. Usage: make $(1) <project>. Available: $(AVAILABLE_PROJECTS)))
endef

list:
	$(info Available projects:)
	$(foreach p,$(AVAILABLE_PROJECTS),$(info   - $(p)))
	@:

build:
ifdef PROJECT
	$(call check_project,build)
	$(MAKE) -C $(PROJECTS_DIR)/$(PROJECT) all
else
	$(info Building all projects...)
	@$(MAKE) --no-print-directory $(BUILD_TARGETS)
endif

$(BUILD_TARGETS): build-%:
	-@$(MAKE) -C $(PROJECTS_DIR)/$* all

sim:
ifdef PROJECT
	$(call check_project,sim)
	$(MAKE) -C $(PROJECTS_DIR)/$(PROJECT) sim
else
	$(info Simulating all projects...)
	@$(MAKE) --no-print-directory $(SIM_TARGETS)
endif

$(SIM_TARGETS): sim-%:
	-@$(MAKE) -C $(PROJECTS_DIR)/$* sim

clean:
ifdef PROJECT
	$(call check_project,clean)
	$(MAKE) -C $(PROJECTS_DIR)/$(PROJECT) clean
else
	$(info Cleaning all projects and tests...)
	@$(MAKE) --no-print-directory $(CLEAN_TARGETS) clean-tests
endif

$(CLEAN_TARGETS): clean-%:
	-@$(MAKE) -C $(PROJECTS_DIR)/$* clean

clean-tests:
	rm -rf $(TESTS_DIR)/*/sim_build $(TESTS_DIR)/*/results.xml
