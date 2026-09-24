# OCI cloud dev host (F07) — start/stop the A1 box between sessions.
# The instance OCID and public IP come from Terraform state so this stays
# in sync with terraform/oci. Stopping the box drops compute cost to ~$0;
# the public IP survives stop/start.

TF_DIR := terraform/oci
OCID   := $(shell terraform -chdir=$(TF_DIR) output -raw instance_ocid 2>/dev/null)
IP     := $(shell terraform -chdir=$(TF_DIR) output -raw instance_public_ip 2>/dev/null)
SSH_KEY := ~/.ssh/id_oci

# Ports opened for the temporary public-noVNC test (see vnc-down).
VNC_PORTS := 48210 48211

.PHONY: start stop status ip ssh vnc-up vnc-down help

help:
	@echo "OCI dev host targets:"
	@echo "  make start    - power the box on (START)"
	@echo "  make stop     - power the box off (SOFTSTOP); IP survives"
	@echo "  make status   - show lifecycle state (RUNNING/STOPPED/...)"
	@echo "  make ip       - print the public IP"
	@echo "  make ssh      - SSH in as ubuntu, pinning the host key"
	@echo "  make vnc-up   - (re)launch the public noVNC test: desktop +"
	@echo "                  view/control mirrors + firewall (box + OCI edge)."
	@echo "                  Reuses ~/.vnc/passwd. Run after 'make start'."
	@echo "  make vnc-down - tear down the public noVNC test (kill services,"
	@echo "                  drop firewall rules on box + OCI edge)"
	@echo ""
	@echo "  noVNC URLs when up:  view-only  http://\$$(make -s ip):48210/vnc.html?autoconnect=true"
	@echo "                       control    http://\$$(make -s ip):48211/vnc.html?autoconnect=true"

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

# (Re)launch the temporary public noVNC test. Idempotent: safe to re-run,
# and used after `make start` to bring the demo back after a stop/start.
#  1. on the box: ensure desktop :1 is up, then relaunch both x11vnc mirrors
#     (view-only/no-pw on 5902, control/password on 5903 from ~/.vnc/passwd)
#     and their websockify bridges, and ensure the iptables ACCEPT rules;
#  2. at the OCI edge: open the test ports (var.vnc_test=true).
# ~/.vnc/passwd and ~/.vnc/xstartup persist on the box, so no re-setup needed.
vnc-up:
	ssh -i $(SSH_KEY) -o IdentitiesOnly=yes ubuntu@$(IP) '\
		pgrep -x Xtigervnc >/dev/null || vncserver :1 -localhost yes -SecurityTypes None -AcceptKeyEvents=0 -AcceptPointerEvents=0; \
		pkill -f x11vnc || true; pkill -f websockify || true; sleep 1; \
		nohup x11vnc -display :1 -forever -shared -viewonly -nopw -localhost -rfbport 5902 >/tmp/x11vnc_view.log 2>&1 & \
		nohup x11vnc -display :1 -forever -shared -rfbauth ~/.vnc/passwd -localhost -rfbport 5903 >/tmp/x11vnc_full.log 2>&1 & \
		sleep 1; \
		nohup websockify --web=/usr/share/novnc 0.0.0.0:48210 localhost:5902 >/tmp/ws_view.log 2>&1 & \
		nohup websockify --web=/usr/share/novnc 0.0.0.0:48211 localhost:5903 >/tmp/ws_full.log 2>&1 & \
		sleep 1; \
		for p in $(VNC_PORTS); do sudo iptables -C INPUT -p tcp --dport $$p -j ACCEPT 2>/dev/null || sudo iptables -I INPUT 5 -p tcp --dport $$p -j ACCEPT; done; \
		echo "box: desktop + mirrors + bridges up, iptables ensured"'
	terraform -chdir=$(TF_DIR) apply -auto-approve -var vnc_test=true -target=oci_core_security_list.dome
	@echo "noVNC up:  view  http://$(IP):48210/vnc.html?autoconnect=true"
	@echo "           ctrl  http://$(IP):48211/vnc.html?autoconnect=true"

# Tear down the temporary public noVNC test:
#  1. on the box: stop websockify/x11vnc/VNC and drop the iptables rules;
#  2. at the OCI edge: re-apply the SSH-only security list (var.vnc_test=false).
# Leading '-' on the ssh line: pkill/iptables exit non-zero when nothing
# matches, which is fine here.
vnc-down:
	-ssh -i $(SSH_KEY) -o IdentitiesOnly=yes ubuntu@$(IP) '\
		pkill -f websockify || true; \
		pkill -f x11vnc || true; \
		vncserver -kill :1 >/dev/null 2>&1 || true; \
		for p in $(VNC_PORTS); do sudo iptables -D INPUT -p tcp --dport $$p -j ACCEPT 2>/dev/null || true; done; \
		echo "box: services stopped, iptables rules dropped"'
	terraform -chdir=$(TF_DIR) apply -auto-approve -var vnc_test=false -target=oci_core_security_list.dome
