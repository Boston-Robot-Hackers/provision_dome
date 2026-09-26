# Dome dev host — box-side convenience targets (F13).
# This Makefile is meant to run ON the provisioned host, from the repo clone
# at ~/provision_dome. It wraps the existing scripts; it adds no provisioning
# logic of its own.
#
# The laptop-side OCI control plane (start/stop/status/ip/ssh/vnc) lives in
# terraform/oci/Makefile — run it with `make -C terraform/oci <target>`. Those
# targets need the `oci` CLI and Terraform state and do not work on the box.

SHELL := /bin/bash

MANIFEST := manifest
CFG := $(MANIFEST)/config.txt
USR := $(MANIFEST)/user.txt

# Resolve a config key with the same precedence the scripts use:
#   environment  >  manifest/user.txt  >  manifest/config.txt
resolve = $(or $($(1)),$(shell grep -s '^[[:space:]]*$(1)=' $(USR) | tail -1 | cut -d= -f2 | tr -d '[:space:]'),$(shell grep -s '^$(1)=' $(CFG) | cut -d= -f2 | tr -d '[:space:]'))

OVERLAY := $(HOME)/ros2_ws/install/setup.bash

.PHONY: help build desktop env status
.DEFAULT_GOAL := help

help:
	@echo "Dome dev-host targets (run on the box, from ~/provision_dome):"
	@echo "  make build    - clone any new repos + colcon-build the workspace (sudo)"
	@echo "  make desktop  - start the loopback noVNC desktop (DOME_DESKTOP=vnc)"
	@echo "  make env      - show resolved DOME_USER/DOME_TARGET/ROS_DISTRO + overlay state"
	@echo "  make status   - workspace build state + ROS package count"
	@echo ""
	@echo "Laptop-side OCI control (start/stop/status/ip/ssh/vnc) lives in"
	@echo "terraform/oci/Makefile:  make -C terraform/oci help"

build:
	sudo scripts/bare-metal-build.sh

desktop:
	scripts/start-desktop.sh

env:
	@echo "DOME_USER=$(call resolve,DOME_USER)"
	@echo "DOME_TARGET=$(call resolve,DOME_TARGET)"
	@echo "ROS_DISTRO=$(call resolve,ROS_DISTRO)"
	@if [[ -f "$(OVERLAY)" ]]; then \
		echo "workspace overlay: present ($(OVERLAY))"; \
	else \
		echo "workspace overlay: NOT built (run: make build)"; \
	fi

status:
	@if [[ -f "$(OVERLAY)" ]]; then \
		distro="$(call resolve,ROS_DISTRO)"; \
		source "/opt/ros/$$distro/setup.bash" 2>/dev/null || true; \
		source "$(OVERLAY)" 2>/dev/null || true; \
		echo "workspace: built"; \
		echo "packages:  $$(ros2 pkg list 2>/dev/null | wc -l | tr -d ' ')"; \
	else \
		echo "workspace: not built (run: make build)"; \
	fi
