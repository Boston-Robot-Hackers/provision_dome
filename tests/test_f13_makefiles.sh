#!/usr/bin/env bash
# Tests for F13: box-side dev Makefile split from the laptop OCI control Makefile.
# Static checks (real `make start`/`ip` need the oci CLI + Terraform state, so
# they are not exercised here — consistent with the other bare-metal checks).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT_MK="${REPO_DIR}/Makefile"
CTRL_MK="${REPO_DIR}/terraform/oci/Makefile"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

echo "=== F13 Makefile-split tests ==="

echo "--- TF13.1: laptop control targets moved to terraform/oci/Makefile ---"
[[ -f "${CTRL_MK}" ]] && pass "terraform/oci/Makefile exists" \
    || fail "terraform/oci/Makefile missing"
for t in start stop status ip ssh vnc-up vnc-down; do
    grep -qE "^${t}:" "${CTRL_MK}" \
        && pass "control Makefile defines '${t}'" \
        || fail "control Makefile missing target '${t}'"
done
grep -qE '^TF_DIR[[:space:]]*:=[[:space:]]*\.[[:space:]]*$' "${CTRL_MK}" \
    && pass "control Makefile anchors TF_DIR to '.'" \
    || fail "control Makefile TF_DIR not re-anchored to '.'"
grep -qE 'TF_DIR[[:space:]]*:=[[:space:]]*terraform/oci' "${CTRL_MK}" \
    && fail "control Makefile still uses a terraform/oci sub-path in TF_DIR" \
    || pass "control Makefile has no terraform/oci sub-path in TF_DIR"

echo "--- TF13.2: root Makefile is box-side only ---"
for t in help build desktop env status; do
    grep -qE "^${t}:" "${ROOT_MK}" \
        && pass "root Makefile defines '${t}'" \
        || fail "root Makefile missing target '${t}'"
done
grep -q 'scripts/bare-metal-build.sh' "${ROOT_MK}" \
    && pass "root 'build' wraps bare-metal-build.sh" \
    || fail "root Makefile does not reference bare-metal-build.sh"
grep -q 'scripts/start-desktop.sh' "${ROOT_MK}" \
    && pass "root 'desktop' wraps start-desktop.sh" \
    || fail "root Makefile does not reference start-desktop.sh"
grep -q 'oci compute' "${ROOT_MK}" \
    && fail "root Makefile still invokes the oci CLI (oci compute)" \
    || pass "root Makefile has no oci CLI invocation"
for t in start stop ip ssh vnc-up vnc-down; do
    grep -qE "^${t}:" "${ROOT_MK}" \
        && fail "root Makefile still defines control target '${t}'" \
        || pass "root Makefile does not define control target '${t}'"
done

echo "--- TF13.3: env/status resolve state and guard the unbuilt case ---"
grep -q 'user.txt' "${ROOT_MK}" && grep -q 'config.txt' "${ROOT_MK}" \
    && pass "root Makefile resolves via user.txt + config.txt cascade" \
    || fail "root Makefile missing the user.txt/config.txt cascade"
grep -qi 'not built' "${ROOT_MK}" \
    && pass "root Makefile guards the not-yet-built workspace" \
    || fail "root Makefile does not guard the unbuilt case"
env_out="$(make -C "${REPO_DIR}" -s env)"
grep -q '^DOME_USER=' <<<"${env_out}" \
    && grep -q '^ROS_DISTRO=' <<<"${env_out}" \
    && pass "'make env' prints resolved DOME_USER/ROS_DISTRO" \
    || fail "'make env' output missing keys: ${env_out}"
make -C "${REPO_DIR}" -s status >/dev/null \
    && pass "'make status' runs clean on an unbuilt workspace" \
    || fail "'make status' errored on an unbuilt workspace"

echo "--- TF13.4: docs point at the new locations ---"
grep -q 'make -C terraform/oci ssh' "${REPO_DIR}/02-doc/current.md" \
    && pass "current.md re-entry uses 'make -C terraform/oci ssh'" \
    || fail "current.md still shows a bare-root 'make ssh'"
grep -qE '`make ssh`,' "${REPO_DIR}/02-doc/current.md" \
    && fail "current.md still shows a bare-root 'make ssh,'" \
    || pass "current.md no longer shows a bare-root 'make ssh'"
grep -q 'make build' "${REPO_DIR}/02-doc/cloud-howto.md" \
    && pass "cloud-howto notes the box-side 'make build'" \
    || fail "cloud-howto missing the 'make build' pointer"

echo "--- syntax check ---"
make -C "${REPO_DIR}" -n help >/dev/null 2>&1 \
    && pass "syntax: root Makefile parses" || fail "syntax: root Makefile"
make -C "${REPO_DIR}/terraform/oci" -n help >/dev/null 2>&1 \
    && pass "syntax: control Makefile parses" || fail "syntax: control Makefile"

echo ""
echo "=== F13: ${PASS} passed, ${FAIL} failed ==="
[[ "${FAIL}" -eq 0 ]]
