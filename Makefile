# iCESugar-Pro Sound2FFT Project
# Top-level Makefile

.PHONY: help docker-build docker-shell docker-down

# Default target
help:
	@echo "iCESugar-Pro Sound2FFT - Build System"
	@echo ""
	@echo "Docker targets:"
	@echo "  make docker-build   - Build the FPGA toolchain container"
	@echo "  make docker-shell   - Open interactive shell in container"
	@echo "  make docker-down    - Stop and remove container"

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
