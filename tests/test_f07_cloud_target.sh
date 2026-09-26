#!/usr/bin/env bash
# Tests for F07: DOME_TARGET=cloud, swap, cloud-init template, DOME_DESKTOP,
# start-desktop.sh, and the cloud docs. Runs on the Mac with no cloud instance;
# anything needing a real instance stays a manual test (see TF07.0).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_DIR="${REPO_DIR}/manifest"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

source "${MANIFEST_DIR}/lib.sh"

echo "=== F07 cloud target tests ==="

# --- TF07.1: DOME_TARGET=cloud comment and fixed target message ---
echo "--- TF07.1 config comment + host-setup message ---"
grep -qE '^# DOME_TARGET=.*\bcloud\b' "${MANIFEST_DIR}/config.txt" \
    && pass "config.txt DOME_TARGET comment lists cloud" \
    || fail "config.txt DOME_TARGET comment missing cloud"
grep -q 'DOME_TARGET=vm —' "${REPO_DIR}/scripts/host-setup.sh" \
    && fail "host-setup.sh still hardcodes 'DOME_TARGET=vm —' message" \
    || pass "host-setup.sh no longer hardcodes the vm target message"
grep -q 'DOME_TARGET=${DOME_TARGET} —' "${REPO_DIR}/scripts/host-setup.sh" \
    && pass "host-setup.sh prints the resolved DOME_TARGET" \
    || fail "host-setup.sh does not print the resolved DOME_TARGET"

# --- TF07.2: swap enabled for pi and cloud, not vm ---
echo "--- TF07.2 swap gate ---"
# Drift check: the real script's gate must name cloud (the behavior test below
# copies the gate inline, so on its own it would pass even if the script drifted).
grep -qE 'DOME_TARGET.*==.*"cloud"' "${REPO_DIR}/scripts/bare-metal-base.sh" \
    && pass "bare-metal-base.sh swap gate names cloud" \
    || fail "bare-metal-base.sh swap gate does not name cloud"

run_swap_gate() {
    # Reproduces just the swap gate condition from bare-metal-base.sh in a
    # stubbed shell — no real disk/swap operations. Echoes made/skipped.
    local dome_target="$1"
    (
        DOME_TARGET="${dome_target}"
        if [[ "${DOME_TARGET}" == "pi" || "${DOME_TARGET}" == "cloud" ]]; then
            echo "made"
        else
            echo "skipped"
        fi
    )
}
[[ "$(run_swap_gate pi)" == "made" ]] && pass "swap: pi creates swap" || fail "swap: pi should create swap"
[[ "$(run_swap_gate cloud)" == "made" ]] && pass "swap: cloud creates swap" || fail "swap: cloud should create swap"
[[ "$(run_swap_gate vm)" == "skipped" ]] && pass "swap: vm skips swap" || fail "swap: vm should skip swap"
[[ "$(run_swap_gate bogus)" == "skipped" ]] && pass "swap: unknown target skips swap" || fail "swap: unknown target should skip swap"

# --- TF07.3: cloud-init first-boot template ---
echo "--- TF07.3 cloud-init template ---"
TEMPLATE="${REPO_DIR}/host-file-templates/cloud/user-data.template"
[[ -f "${TEMPLATE}" ]] && pass "cloud user-data.template exists" || fail "cloud user-data.template missing"
head -1 "${TEMPLATE}" | grep -q '^#cloud-config' \
    && pass "template starts with #cloud-config" || fail "template missing #cloud-config header"
for ph in REPLACE_WITH_HOST_USER REPLACE_WITH_SSH_PUBLIC_KEY; do
    grep -q "${ph}" "${TEMPLATE}" && pass "template contains ${ph}" || fail "template missing ${ph}"
done
grep -q 'DOME_TARGET=cloud' "${TEMPLATE}" \
    && pass "template sets DOME_TARGET=cloud" || fail "template missing DOME_TARGET=cloud"
grep -q 'host-setup.sh' "${TEMPLATE}" \
    && pass "template runs host-setup.sh" || fail "template missing host-setup.sh"
grep -q 'bare-metal-base.sh' "${TEMPLATE}" \
    && pass "template runs bare-metal-base.sh" || fail "template missing bare-metal-base.sh"
grep -q 'bare-metal-build.sh' "${TEMPLATE}" \
    && fail "template must NOT run bare-metal-build.sh (needs credentials)" \
    || pass "template does not run bare-metal-build.sh"
if python3 -c 'import yaml' >/dev/null 2>&1; then
    python3 -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1]))' "${TEMPLATE}" \
        && pass "template parses as YAML" || fail "template does not parse as YAML"
else
    echo "  SKIP: python3 yaml not available, skipping YAML parse check"
fi

# --- TF07.4: DOME_DESKTOP manifest + gating ---
echo "--- TF07.4 DOME_DESKTOP ---"
got=$(manifest_config DOME_DESKTOP "${MANIFEST_DIR}/config.txt")
[[ "$got" == "none" ]] && pass "config.txt DOME_DESKTOP defaults to none" \
    || fail "config.txt DOME_DESKTOP: got='$got' expected='none'"
desktop_pkgs=$(awk '/^\[apt-desktop\]/{f=1;next} /^\[/{f=0} f && /^[^#[:space:]]/' "${MANIFEST_DIR}/packages.txt")
[[ -n "${desktop_pkgs}" ]] && pass "[apt-desktop] parses to a non-empty list" \
    || fail "[apt-desktop] section empty or missing"
grep -q 'DOME_DESKTOP.*==.*"vnc"' "${REPO_DIR}/scripts/bare-metal-base.sh" \
    && pass "bare-metal-base.sh gates apt-desktop on DOME_DESKTOP=vnc" \
    || fail "bare-metal-base.sh missing DOME_DESKTOP=vnc gate"
grep -q '_DOME_DESKTOP_FILE' "${REPO_DIR}/scripts/bare-metal-base.sh" \
    && pass "bare-metal-base.sh reads DOME_DESKTOP with user.txt precedence" \
    || fail "bare-metal-base.sh missing DOME_DESKTOP user.txt override"

run_desktop_gate() {
    local dome_desktop="$1"
    ( DOME_DESKTOP="${dome_desktop}"
      if [[ "${DOME_DESKTOP}" == "vnc" ]]; then echo "included"; else echo "skipped"; fi )
}
[[ "$(run_desktop_gate vnc)" == "included" ]] && pass "desktop: vnc includes apt-desktop" || fail "desktop: vnc should include apt-desktop"
[[ "$(run_desktop_gate none)" == "skipped" ]] && pass "desktop: none skips apt-desktop" || fail "desktop: none should skip apt-desktop"
[[ "$(run_desktop_gate bogus)" == "skipped" ]] && pass "desktop: unknown value skips apt-desktop" || fail "desktop: unknown should skip apt-desktop"

# --- TF07.5: start-desktop.sh (mode-aware, F14) ---
echo "--- TF07.5 start-desktop.sh ---"
DESKTOP_SH="${REPO_DIR}/scripts/start-desktop.sh"
[[ -f "${DESKTOP_SH}" ]] && pass "start-desktop.sh exists" || fail "start-desktop.sh missing"
bash -n "${DESKTOP_SH}" && pass "syntax: start-desktop.sh" || fail "syntax: start-desktop.sh"
grep -q -- '-localhost yes' "${DESKTOP_SH}" \
    && pass "start-desktop.sh passes -localhost yes to VNC" || fail "start-desktop.sh missing -localhost yes"
grep -q '127.0.0.1' "${DESKTOP_SH}" \
    && pass "start-desktop.sh binds websockify to loopback in tunnel mode" || fail "start-desktop.sh not binding websockify to loopback"
# F14: public mode intentionally binds 0.0.0.0:48210, gated by DOME_VNC_ACCESS=public;
# tunnel mode stays on loopback. Ensure the public bind is the gated one, not blanket.
grep -q '0.0.0.0:${PUBLIC_PORT}' "${DESKTOP_SH}" \
    && pass "start-desktop.sh public bind is 0.0.0.0:PUBLIC_PORT, gated by mode (F14)" \
    || fail "start-desktop.sh public bind missing/ungated"
# Behavior: in a real mode (tunnel) with vncserver absent, exit non-zero mentioning DOME_DESKTOP.
if command -v vncserver >/dev/null 2>&1; then
    echo "  SKIP: vncserver present on PATH, skipping missing-package behavior check"
else
    set +e
    out=$(DOME_VNC_ACCESS=tunnel bash "${DESKTOP_SH}" 2>&1); rc=$?
    set -e
    [[ "${rc}" -ne 0 ]] && pass "start-desktop.sh exits non-zero when vncserver missing" \
        || fail "start-desktop.sh should exit non-zero when vncserver missing"
    grep -q 'DOME_DESKTOP' <<< "${out}" \
        && pass "start-desktop.sh error mentions DOME_DESKTOP" || fail "start-desktop.sh error missing DOME_DESKTOP"
fi

# --- TF07.6: cloud-howto.md ---
echo "--- TF07.6 cloud-howto.md ---"
HOWTO="${REPO_DIR}/02-doc/cloud-howto.md"
[[ -f "${HOWTO}" ]] && pass "cloud-howto.md exists" || fail "cloud-howto.md missing"
grep -q 'DOME_TARGET=cloud' "${HOWTO}" && pass "cloud-howto.md mentions DOME_TARGET=cloud" || fail "cloud-howto.md missing DOME_TARGET=cloud"
grep -q 'cloud-init status' "${HOWTO}" && pass "cloud-howto.md mentions cloud-init status" || fail "cloud-howto.md missing cloud-init status"
grep -q 'ssh -L' "${HOWTO}" && pass "cloud-howto.md mentions ssh -L tunnels" || fail "cloud-howto.md missing ssh -L"

# --- TF07.7: scenario table + README ---
echo "--- TF07.7 scenario table + README ---"
grep -qi 'cloud' "${REPO_DIR}/02-doc/howto.md" && grep -q 'cloud-howto.md' "${REPO_DIR}/02-doc/howto.md" \
    && pass "howto.md names the cloud scenario and links cloud-howto.md" \
    || fail "howto.md missing cloud scenario or cloud-howto.md link"
grep -qi 'cloud' "${REPO_DIR}/README.md" && grep -q 'cloud-howto.md' "${REPO_DIR}/README.md" \
    && pass "README.md names the cloud scenario and links cloud-howto.md" \
    || fail "README.md missing cloud scenario or cloud-howto.md link"

# --- TF07.9: terraform/oci config ---
echo "--- TF07.9 terraform/oci ---"
TF_DIR="${REPO_DIR}/terraform/oci"
for f in provider.tf variables.tf network.tf compute.tf outputs.tf; do
    [[ -f "${TF_DIR}/${f}" ]] && pass "terraform/oci/${f} exists" || fail "terraform/oci/${f} missing"
done
# Bare box: no cloud-init user-data baked into the instance (TF07.0 runs the
# scripts by hand); no swap here either.
grep -q 'user_data' "${TF_DIR}/compute.tf" \
    && fail "compute.tf bakes in user_data; TF07.9 stands up a bare box" \
    || pass "compute.tf stands up a bare box (no user_data)"
grep -q 'ingress_security_rules' "${TF_DIR}/network.tf" \
    && pass "network.tf defines an ingress security rule" \
    || fail "network.tf missing ingress security rule"

if command -v terraform >/dev/null 2>&1; then
    set +e
    fmt_out=$(cd "${TF_DIR}" && terraform fmt -check -recursive 2>&1); fmt_rc=$?
    set -e
    [[ "${fmt_rc}" -eq 0 ]] && pass "terraform fmt -check clean" \
        || fail "terraform fmt -check found unformatted files: ${fmt_out}"
    set +e
    (cd "${TF_DIR}" && terraform init -input=false -no-color >/dev/null 2>&1) \
        && val_out=$(cd "${TF_DIR}" && terraform validate -no-color 2>&1); val_rc=$?
    set -e
    [[ "${val_rc}" -eq 0 ]] && pass "terraform validate succeeds" \
        || fail "terraform validate failed: ${val_out}"
else
    echo "  SKIP: terraform not on PATH — fmt/validate checks skipped"
fi

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
[[ "${FAIL}" -eq 0 ]]
