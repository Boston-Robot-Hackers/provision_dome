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

# Per-box key (F15.1): the box gets an identity of its own, so a box
# compromise cannot sign as you against GitHub or the robot. Generate with
#   ssh-keygen -t ed25519 -f ~/.ssh/id_dome_cloud -C dome-cloud-1
# and point ssh_public_key_path at the .pub half in terraform.tfvars.
SSH_KEY ?= ~/.ssh/id_dome_cloud

# Ingress for the public noVNC port (F15.5). Recursive '=' so the lookup only
# runs when a vnc-up actually needs it, not on every make invocation. Override
# for a changing address: make vnc-up CIDR=1.2.3.0/24
MY_IP = $(shell curl -fsS --max-time 10 https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]')
CIDR ?= $(if $(MY_IP),$(MY_IP)/32,)

.PHONY: start stop status ip ssh audit check-key vnc-up vnc-down help

help:
	@echo "OCI dev host control (laptop-side; run from terraform/oci):"
	@echo "  make start    - power the box on (START); stays disarmed until vnc-up"
	@echo "  make stop     - close the VNC port, then power off (SOFTSTOP);"
	@echo "                  stopped means disarmed. IP survives."
	@echo "  make status   - show lifecycle state (RUNNING/STOPPED/...)"
	@echo "  make ip       - print the public IP"
	@echo "  make ssh      - SSH in as ubuntu, pinning the host key"
	@echo "  make audit    - fail if the box holds credentials or private keys"
	@echo "  make vnc-up   - open the public noVNC desktop to YOUR address only:"
	@echo "                  vnc_access=public + vnc_allowed_cidr=<your ip>/32 at"
	@echo "                  the OCI edge + start dome-vnc on the box. Needs a VNC"
	@echo "                  password set once on the box (vncpasswd)."
	@echo "                  Override with: make vnc-up CIDR=1.2.3.0/24"
	@echo "  make vnc-down - close it: stop dome-vnc on the box + vnc_access=none"
	@echo ""
	@echo "  noVNC URL when up:  https://\$$(make -s ip):48210/vnc.html?autoconnect=true"

start:
	oci compute instance action --instance-id $(OCID) --action START

# Stopped means disarmed (F15.9). SOFTSTOP alone left 48210 open at the edge
# and both VNC units enabled, so a later `make start` silently restored a
# publicly reachable desktop. vnc-down is a prerequisite rather than a repeated
# command: it already tolerates an unreachable box, which is exactly the case
# here.
stop: vnc-down
	oci compute instance action --instance-id $(OCID) --action SOFTSTOP

status:
	oci compute instance get --instance-id $(OCID) --query 'data."lifecycle-state"' --raw-output

ip:
	@echo $(IP)

# The per-box key is created by hand (F15.1), so until it exists the targets
# that need it fail with a confusing ssh error. Say what to do instead.
check-key:
	@test -f $(SSH_KEY) || { \
		echo "ERROR: $(SSH_KEY) not found — this box wants a key of its own (F15.1)."; \
		echo "  ssh-keygen -t ed25519 -f $(SSH_KEY) -C dome-cloud-box"; \
		echo "then append its .pub to ~/.ssh/authorized_keys on the box, verify from a"; \
		echo "SECOND session, and remove the old key. Meanwhile: make ssh SSH_KEY=~/.ssh/id_ed25519"; \
		exit 1; }

ssh: check-key
	ssh -i $(SSH_KEY) -o IdentitiesOnly=yes ubuntu@$(IP)

# F15.4: a public-mode box must hold no credentials and no private keys. Runs
# scripts/box-audit.sh from the box's own clone, so the checks live in one
# reviewable file rather than inline here.
audit: check-key
	ssh -i $(SSH_KEY) -o IdentitiesOnly=yes ubuntu@$(IP) \
		'bash ~/provision_dome/scripts/box-audit.sh'

# Manual override for the public noVNC desktop (F14). Steady state is driven by
# var.vnc_access (set in terraform.tfvars); these targets just flip it and the
# on-box service for an ad-hoc bring-up. Single controllable TigerVNC session
# (no x11vnc, no second port); reached at https://<ip>:48210/vnc.html behind a
# VNC password. The box must be provisioned in public mode (dome-vnc.service +
# dome-vnc-firewall.service installed by bare-metal-base.sh) and have a VNC
# password set once with `vncpasswd`.
# The CIDR test is deliberate: an unresolvable public IP must stop the target,
# not fall back to 0.0.0.0/0. A silent widening here is the bug F15.5 fixes.
vnc-up:
	@test -n "$(CIDR)" || { \
		echo "ERROR: could not determine your public IP, and refusing to default to 0.0.0.0/0."; \
		echo "Pass one explicitly:  make vnc-up CIDR=<your.ip>/32"; \
		exit 1; }
	@echo "==> opening 48210 to $(CIDR) only"
	terraform -chdir=$(TF_DIR) apply -auto-approve -var vnc_access=public -var vnc_allowed_cidr=$(CIDR) -target=oci_core_security_list.dome
	ssh -i $(SSH_KEY) -o IdentitiesOnly=yes ubuntu@$(IP) '\
		sudo systemctl start dome-vnc-firewall.service 2>/dev/null || true; \
		sudo systemctl restart dome-vnc.service || { echo "dome-vnc.service missing — provision this box in public mode (bare-metal-base.sh) and set a password (vncpasswd)"; exit 1; }; \
		echo "box: dome-vnc (+firewall) started"'
	@echo "noVNC up:  https://$(IP):48210/vnc.html?autoconnect=true  (self-signed cert warning is expected; then enter the VNC password)"

# Close the public noVNC desktop: stop the on-box service, then re-apply the
# SSH-only security list (var.vnc_access=none). Leading '-' on the ssh line:
# systemctl exits non-zero when a unit is absent, which is fine here.
vnc-down:
	-ssh -i $(SSH_KEY) -o IdentitiesOnly=yes ubuntu@$(IP) '\
		sudo systemctl stop dome-vnc.service 2>/dev/null || true; \
		sudo systemctl stop dome-vnc-firewall.service 2>/dev/null || true; \
		echo "box: dome-vnc services stopped"'
	terraform -chdir=$(TF_DIR) apply -auto-approve -var vnc_access=none -target=oci_core_security_list.dome
