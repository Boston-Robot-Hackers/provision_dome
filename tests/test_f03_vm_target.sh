#!/usr/bin/env bash
# Tests for F03: DOME_TARGET=pi|vm support for bare-metal provisioning.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_DIR="${REPO_DIR}/manifest"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

section_has() {
    local section="$1" entry="$2" file="$3"
    awk -v s="[$section]" '$0==s{f=1;next} /^\[/{f=0} f' "$file" | grep -q "$entry"
}

echo "=== F03 DOME_TARGET tests ==="

echo "--- config.txt defaults ---"
source "${MANIFEST_DIR}/lib.sh"
got=$(manifest_config DOME_TARGET "${MANIFEST_DIR}/config.txt")
[[ "$got" == "pi" ]] && pass "config.txt DOME_TARGET defaults to pi" \
    || fail "config.txt DOME_TARGET: got='$got' expected='pi'"

echo "--- packages.txt apt/apt-pi split ---"
section_has apt raspi-config "${MANIFEST_DIR}/packages.txt" \
    && fail "[apt] still contains raspi-config" || pass "[apt] no longer contains raspi-config"
section_has apt i2c-tools "${MANIFEST_DIR}/packages.txt" \
    && fail "[apt] still contains i2c-tools" || pass "[apt] no longer contains i2c-tools"
section_has apt-pi raspi-config "${MANIFEST_DIR}/packages.txt" \
    && pass "[apt-pi] contains raspi-config" || fail "[apt-pi] missing raspi-config"
section_has apt-pi i2c-tools "${MANIFEST_DIR}/packages.txt" \
    && pass "[apt-pi] contains i2c-tools" || fail "[apt-pi] missing i2c-tools"

echo "--- pip.txt pip/pip-pi split ---"
section_has pip RPi.GPIO "${MANIFEST_DIR}/pip.txt" \
    && fail "[pip] still contains RPi.GPIO" || pass "[pip] no longer contains RPi.GPIO"
section_has pip-pi RPi.GPIO "${MANIFEST_DIR}/pip.txt" \
    && pass "[pip-pi] contains RPi.GPIO" || fail "[pip-pi] missing RPi.GPIO"
section_has pip-pi spidev "${MANIFEST_DIR}/pip.txt" \
    && pass "[pip-pi] contains spidev" || fail "[pip-pi] missing spidev"
section_has pip PyAudio "${MANIFEST_DIR}/pip.txt" \
    && pass "[pip] still contains PyAudio" || fail "[pip] missing PyAudio"

echo "--- repos-dome.txt root/root-pi split ---"
for repo in seeed-linux-dtoverlays libcamera-apps mic_hat; do
    section_has root "$repo" "${MANIFEST_DIR}/repos-dome.txt" \
        && fail "[root] still contains $repo" || pass "[root] no longer contains $repo"
    section_has root-pi "$repo" "${MANIFEST_DIR}/repos-dome.txt" \
        && pass "[root-pi] contains $repo" || fail "[root-pi] missing $repo"
done
for repo in rosutils depthai-python linorobot2_hardware; do
    section_has root "$repo" "${MANIFEST_DIR}/repos-dome.txt" \
        && pass "[root] still contains $repo" || fail "[root] missing $repo"
done

echo "--- scripts reference DOME_TARGET ---"
for f in host-setup.sh bare-metal-base.sh bare-metal-build.sh; do
    grep -q 'DOME_TARGET' "${REPO_DIR}/scripts/${f}" \
        && pass "${f} references DOME_TARGET" || fail "${f} missing DOME_TARGET"
done

echo "--- scripts pass syntax check ---"
for f in host-setup.sh bare-metal-base.sh bare-metal-build.sh; do
    bash -n "${REPO_DIR}/scripts/${f}" && pass "syntax: scripts/${f}" || fail "syntax: scripts/${f}"
done

echo "--- Docker build path still installs Pi-only set (unaffected by target split) ---"
grep -q 'apt-pi' "${REPO_DIR}/Dockerfile.base" \
    && pass "Dockerfile.base installs [apt-pi]" || fail "Dockerfile.base missing [apt-pi]"
grep -q 'pip-pi' "${REPO_DIR}/Dockerfile.base" \
    && pass "Dockerfile.base installs [pip-pi]" || fail "Dockerfile.base missing [pip-pi]"
grep -q 'clone_section root-pi' "${REPO_DIR}/Dockerfile" \
    && pass "Dockerfile clones [root-pi]" || fail "Dockerfile missing [root-pi] clone"

echo "--- VM setup is documented ---"
# README is end-user facing and deliberately names no config flags; it must
# route users to the VM guide, and the guide must document the flag itself.
grep -q 'vm-howto.md' "${REPO_DIR}/README.md" \
    && pass "README.md points to the VM guide" || fail "README.md missing vm-howto.md link"
grep -q 'DOME_TARGET=vm' "${REPO_DIR}/02-doc/vm-howto.md" \
    && pass "vm-howto.md documents DOME_TARGET=vm" || fail "vm-howto.md missing DOME_TARGET=vm"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
[[ "${FAIL}" -eq 0 ]]
