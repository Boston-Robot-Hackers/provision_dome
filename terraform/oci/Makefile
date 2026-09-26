# OCI cloud dev host (F07) — laptop-side control plane.
# Start/stop the A1 box between sessions, SSH in, and toggle the public noVNC
# desktop (F14). Run from this directory (or `make -C terraform/oci <t>`).
# The instance OCID and public IP come from Terraform state, so this stays in
# sync with the .tf files here. Stopping the box drops compute cost to ~$0;
# the public IP survives stop/start. These targets need the `oci` CLI and this
# directory's Terraform state — they do NOT belong on the box (see F13).

TF_DIR := .
OCID   := $(shell terraform -chdir=$(TF_DIR) output -raw instance_ocid 2>/dev/null)
IP     := $(shell terraform -chdir=$(TF_DIR) output -raw instance_public_ip 2>/dev/null)
SSH_KEY ?= ~/.ssh/id_ed25519

.PHONY: start stop status ip ssh vnc-up vnc-down help

help:
	@echo "OCI dev host control (laptop-side; run from terraform/oci):"
	@echo "  make start    - power the box on (START)"
	@echo "  make stop     - power the box off (SOFTSTOP); IP survives"
	@echo "  make status   - show lifecycle state (RUNNING/STOPPED/...)"
	@echo "  make ip       - print the public IP"
	@echo "  make ssh      - SSH in as ubuntu, pinning the host key"
	@echo "  make vnc-up   - open the public noVNC desktop: vnc_access=public at"
	@echo "                  the OCI edge + start dome-vnc on the box. Needs a VNC"
	@echo "                  password set once on the box (vncpasswd)."
	@echo "  make vnc-down - close it: stop dome-vnc on the box + vnc_access=none"
	@echo ""
	@echo "  noVNC URL when up:  http://\$$(make -s ip):48210/vnc.html?autoconnect=true"

start:
	oci compute instance action --instance-id $(OCID) --action START

stop:
	oci compute instance action --instance-id $(OCID) --action SOFTSTOP

status:
	oci compute instance get --instance-id $(OCID) --query 'data."lifecycle-state"' --raw-output

ip:
	@echo $(IP)

ssh:
	ssh -i $(SSH_KEY) -o IdentitiesOnly=yes ubuntu@$(IP)

# Manual override for the public noVNC desktop (F14). Steady state is driven by
# var.vnc_access (set in terraform.tfvars); these targets just flip it and the
# on-box service for an ad-hoc bring-up. Single controllable TigerVNC session
# (no x11vnc, no second port); reached at http://<ip>:48210/vnc.html behind a
# VNC password. The box must be provisioned in public mode (dome-vnc.service +
# dome-vnc-firewall.service installed by bare-metal-base.sh) and have a VNC
# password set once with `vncpasswd`.
vnc-up:
	terraform -chdir=$(TF_DIR) apply -auto-approve -var vnc_access=public -target=oci_core_security_list.dome
	ssh -i $(SSH_KEY) -o IdentitiesOnly=yes ubuntu@$(IP) '\
		sudo systemctl start dome-vnc-firewall.service 2>/dev/null || true; \
		sudo systemctl restart dome-vnc.service || { echo "dome-vnc.service missing — provision this box in public mode (bare-metal-base.sh) and set a password (vncpasswd)"; exit 1; }; \
		echo "box: dome-vnc (+firewall) started"'
	@echo "noVNC up:  http://$(IP):48210/vnc.html?autoconnect=true  (enter the VNC password)"

# Close the public noVNC desktop: stop the on-box service, then re-apply the
# SSH-only security list (var.vnc_access=none). Leading '-' on the ssh line:
# systemctl exits non-zero when a unit is absent, which is fine here.
vnc-down:
	-ssh -i $(SSH_KEY) -o IdentitiesOnly=yes ubuntu@$(IP) '\
		sudo systemctl stop dome-vnc.service 2>/dev/null || true; \
		sudo systemctl stop dome-vnc-firewall.service 2>/dev/null || true; \
		echo "box: dome-vnc services stopped"'
	terraform -chdir=$(TF_DIR) apply -auto-approve -var vnc_access=none -target=oci_core_security_list.dome
