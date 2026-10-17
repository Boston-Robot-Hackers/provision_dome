#!/usr/bin/env bash
# Tests for F14: per-VM VNC access mode (public URL+password vs key-tunnel),
# single-server TigerVNC (no x11vnc). Live serving/firewall behavior needs a
# real box, so those are static grep/parse checks, per the suite's convention.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_DIR="${REPO_DIR}/manifest"
SD="${REPO_DIR}/scripts/start-desktop.sh"
BMB="${REPO_DIR}/scripts/bare-metal-base.sh"
NET="${REPO_DIR}/terraform/oci/network.tf"
VARS="${REPO_DIR}/terraform/oci/variables.tf"
HOWTO="${REPO_DIR}/02-doc/cloud-howto.md"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

echo "=== F14 VNC access-mode tests ==="

echo "--- TF14.1: DOME_VNC_ACCESS config flag ---"
source "${MANIFEST_DIR}/lib.sh"
got=$(manifest_config DOME_VNC_ACCESS "${MANIFEST_DIR}/config.txt")
[[ "$got" == "none" ]] && pass "config.txt DOME_VNC_ACCESS defaults to none" \
    || fail "config.txt DOME_VNC_ACCESS: got='$got' expected='none'"
grep -q 'public|tunnel' "${MANIFEST_DIR}/config.txt" \
    && pass "config.txt documents the public/tunnel values" \
    || fail "config.txt does not document DOME_VNC_ACCESS values"

echo "--- TF14.2: single-server VNC, no x11vnc ---"
if grep -rn 'x11vnc' "${REPO_DIR}/scripts" "${REPO_DIR}/terraform" "${REPO_DIR}/host-file-templates" 2>/dev/null | grep -vE ':[0-9]+:[[:space:]]*#' >/dev/null; then
    fail "x11vnc invoked (non-comment) in scripts/terraform/templates"
else
    pass "no x11vnc invocation (comments noting its absence are fine)"
fi
grep -q '0.0.0.0:${PUBLIC_PORT}' "${SD}" && grep -q 'PUBLIC_PORT=48210' "${SD}" \
    && pass "start-desktop.sh binds 0.0.0.0:48210 in public mode" \
    || fail "start-desktop.sh public bind missing"
grep -q '127.0.0.1:${TUNNEL_PORT}' "${SD}" \
    && pass "start-desktop.sh binds loopback in tunnel mode" \
    || fail "start-desktop.sh tunnel bind missing"
[[ -f "${REPO_DIR}/host-file-templates/etc/systemd/system/dome-vnc.service" ]] \
    && pass "dome-vnc.service template exists" || fail "dome-vnc.service template missing"
# F15.9 changed this: the unit is installed but deliberately NOT enabled, so a
# reboot leaves the box disarmed and arming is always an explicit `vnc-up`.
grep -q 'install -m 0644 "${VNC_FW_SRC}"' "${BMB}" \
    && grep -q '/etc/systemd/system/dome-vnc.service' "${BMB}" \
    && pass "bare-metal-base.sh installs the dome-vnc units" \
    || fail "bare-metal-base.sh does not install the dome-vnc units"
grep -qE '^[[:space:]]*systemctl enable dome-vnc' "${BMB}" \
    && fail "bare-metal-base.sh enables a VNC unit at boot (F15.9: it must not)" \
    || pass "bare-metal-base.sh leaves the VNC units disabled (F15.9)"
bash -n "${SD}" && pass "syntax: start-desktop.sh" || fail "syntax: start-desktop.sh"
bash -n "${BMB}" && pass "syntax: bare-metal-base.sh" || fail "syntax: bare-metal-base.sh"

echo "--- TF14.3: Terraform opens exactly one port in public mode ---"
grep -q 'var.vnc_access == "public"' "${NET}" \
    && pass "network.tf opens ports only in public mode" \
    || fail "network.tf public-mode guard missing"
grep -q 'toset(\[48210\])' "${NET}" \
    && pass "network.tf opens exactly port 48210" \
    || fail "network.tf single-port 48210 missing"
grep -q '48211' "${NET}" && fail "network.tf still references 48211" \
    || pass "network.tf no longer references 48211"
grep -q 'variable "vnc_access"' "${VARS}" \
    && pass "variables.tf defines vnc_access" || fail "variables.tf missing vnc_access"
grep -q 'variable "vnc_test"' "${VARS}" && fail "variables.tf still defines vnc_test" \
    || pass "variables.tf no longer defines vnc_test"

echo "--- TF14.4: password required in public; no passwordless exposure ---"
grep -q 'vncpasswd' "${SD}" && grep -q '.vnc/passwd' "${SD}" \
    && pass "start-desktop.sh requires a VNC password in public mode" \
    || fail "start-desktop.sh does not enforce a public-mode password"
if grep -rn 'SecurityTypes None' "${REPO_DIR}/scripts" "${REPO_DIR}/terraform" >/dev/null 2>&1; then
    fail "a passwordless VNC (SecurityTypes None) is still configured"
else
    pass "no passwordless VNC (SecurityTypes None) anywhere"
fi

echo "--- TF14.5: cloud-howto documents both modes ---"
grep -qi 'DOME_VNC_ACCESS=tunnel' "${HOWTO}" && grep -qi 'DOME_VNC_ACCESS=public' "${HOWTO}" \
    && pass "cloud-howto documents both tunnel and public modes" \
    || fail "cloud-howto missing a mode"
grep -q 'x11vnc' "${HOWTO}" && fail "cloud-howto still mentions x11vnc" \
    || pass "cloud-howto no longer mentions x11vnc"

echo "--- TF14.6: desktop is self-sufficient ([apt-desktop] apps) ---"
desktop_section="$(awk '/^\[apt-desktop\]/{f=1;next} /^\[/{f=0} f' "${MANIFEST_DIR}/packages.txt")"
for app in xfce4-terminal terminator mousepad firefox thunar xfce4-taskmanager xfce4-screenshooter htop tigervnc-tools; do
    grep -qx "$app" <<<"$desktop_section" \
        && pass "[apt-desktop] includes $app" \
        || fail "[apt-desktop] missing $app"
done

echo ""
echo "=== F14: ${PASS} passed, ${FAIL} failed ==="
[[ "${FAIL}" -eq 0 ]]
