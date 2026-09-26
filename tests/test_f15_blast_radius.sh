#!/usr/bin/env bash
# Tests for F15: contain the cloud box's blast radius. Live hardening behavior
# (sshd refusing an agent, the OCI edge refusing a connection, a pinned
# installer resolving) needs a real box, so those are static grep/parse checks
# per the suite's convention; TF15.16 records the manual half.
#
# Two things here are exercised for real rather than grepped: the sha256 verify
# helper and scripts/box-audit.sh, both of which are pure logic over a temp
# directory.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_DIR="${REPO_DIR}/manifest"
TOOLS="${MANIFEST_DIR}/tools.txt"
REPOS="${MANIFEST_DIR}/repos.txt"
BMB="${REPO_DIR}/scripts/bare-metal-base.sh"
BUILD="${REPO_DIR}/scripts/bare-metal-build.sh"
SD="${REPO_DIR}/scripts/start-desktop.sh"
AUDIT="${REPO_DIR}/scripts/box-audit.sh"
DOCKERFILE="${REPO_DIR}/Dockerfile"
NET="${REPO_DIR}/terraform/oci/network.tf"
VARS="${REPO_DIR}/terraform/oci/variables.tf"
TFVARS_EX="${REPO_DIR}/terraform/oci/terraform.tfvars.example"
MK="${REPO_DIR}/terraform/oci/Makefile"
SSHD_DROPIN="${REPO_DIR}/host-file-templates/etc/ssh/sshd_config.d/60-dome-hardening.conf"
HOWTO="${REPO_DIR}/02-doc/cloud-howto.md"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
check() { if eval "$1" >/dev/null 2>&1; then pass "$2"; else fail "$2"; fi; }

echo "=== F15 blast-radius tests ==="

echo "--- TF15.1: pinned, verified curl installers ---"
if grep -qE 'url.*raw\.githubusercontent\.com/[^/]+/[^/]+/(master|main)/' "${TOOLS}"; then
    fail "tools.txt still fetches an installer from a moving branch"
else
    pass "tools.txt has no master/main installer URL"
fi
check "grep -qE '^url.*raw\.githubusercontent\.com/cantino/mcfly/[0-9a-f]{40}/' '${TOOLS}'" \
    "[mcfly] URL is pinned to a 40-hex commit"
check "grep -qE '^sha256[[:space:]]*=[[:space:]]*[0-9a-f]{64}$' '${TOOLS}'" \
    "[mcfly] carries a 64-hex sha256"
check "grep -q 'manifest_verify_sha256' '${BMB}'" \
    "bare-metal-base.sh verifies the digest"
if grep -qE "curl[^|]*\|[[:space:]]*(sh|bash)" "${BMB}"; then
    fail "bare-metal-base.sh still pipes curl straight into a shell"
else
    pass "bare-metal-base.sh downloads to a file instead of piping to a shell"
fi
# The verify helper itself, for real.
source "${MANIFEST_DIR}/lib.sh"
TMPD=$(mktemp -d)
trap 'rm -rf "${TMPD}"' EXIT
echo "dome" > "${TMPD}/f"
GOOD=$(if command -v sha256sum >/dev/null 2>&1; then sha256sum "${TMPD}/f"; else shasum -a 256 "${TMPD}/f"; fi | cut -d' ' -f1)
check "manifest_verify_sha256 '${TMPD}/f' '${GOOD}'" "verify accepts a matching digest"
check "! manifest_verify_sha256 '${TMPD}/f' 'deadbeef'" "verify rejects a mismatched digest"
check "! manifest_verify_sha256 '${TMPD}/f' ''" "verify rejects an empty digest"

echo "--- TF15.2: claude-code version pin ---"
check "grep -qE '^args[[:space:]]*=[[:space:]]*(stable|[0-9]+\.[0-9]+\.[0-9]+)' '${TOOLS}'" \
    "[claude-code] passes a version/channel argument"
check "grep -q 'vendor endpoint' '${TOOLS}'" \
    "tools.txt records why that installer carries no sha256"

echo "--- TF15.3: commit pins in the repo format ---"
manifest_parse_repo "https://example.com/a.git dest 1111111111111111111111111111111111111111"
[[ -n "${REPO_COMMIT}" && -z "${REPO_BRANCH}" ]] \
    && pass "40-hex field parses as a commit, not a branch" \
    || fail "40-hex field: commit='${REPO_COMMIT}' branch='${REPO_BRANCH}'"
manifest_parse_repo "https://example.com/a.git dest devel"
[[ -z "${REPO_COMMIT}" && "${REPO_BRANCH}" == "devel" ]] \
    && pass "non-hex field still parses as a branch" \
    || fail "branch field: commit='${REPO_COMMIT}' branch='${REPO_BRANCH}'"
manifest_parse_repo "https://example.com/a.git dest"
[[ -z "${REPO_COMMIT}" && -z "${REPO_BRANCH}" ]] \
    && pass "two-field line sets neither" \
    || fail "two-field line: commit='${REPO_COMMIT}' branch='${REPO_BRANCH}'"
manifest_parse_repo "git@example.com:a.git dest PRIVATE_REPO 2222222222222222222222222222222222222222"
[[ "${REPO_IS_PRIVATE}" == "true" && -n "${REPO_COMMIT}" ]] \
    && pass "marker and commit coexist in either order" \
    || fail "marker+commit: private='${REPO_IS_PRIVATE}' commit='${REPO_COMMIT}'"
check "grep -q 'checkout --detach' '${BUILD}'" "bare-metal-build.sh checks out a pinned commit"
check "grep -q 'checkout --detach' '${DOCKERFILE}'" "Dockerfile mirrors the pinned checkout"

echo "--- TF15.4: rosutils is pinned ---"
rosutils_lines=$(grep -h 'rosutils' "${MANIFEST_DIR}"/repos*.txt 2>/dev/null | grep -v '^#' || true)
if [[ -z "${rosutils_lines}" ]]; then
    fail "no rosutils entry found under manifest/"
else
    unpinned=$(echo "${rosutils_lines}" | grep -vcE '[0-9a-f]{40}' || true)
    [[ "${unpinned}" -eq 0 ]] \
        && pass "every rosutils entry carries a commit pin" \
        || fail "${unpinned} rosutils entry/entries have no commit pin"
    distinct=$(echo "${rosutils_lines}" | grep -oE '[0-9a-f]{40}' | sort -u | wc -l | tr -d ' ')
    [[ "${distinct}" -le 1 ]] \
        && pass "all rosutils pins agree" \
        || fail "rosutils pinned to ${distinct} different commits"
fi

echo "--- TF15.5 / TF15.10: the written rules ---"
check "grep -qi 'no interactive credential login' '${HOWTO}'" "cloud-howto states the no-login rule"
check "grep -qi 'deploy key' '${HOWTO}'" "cloud-howto documents read-only deploy keys"
check "grep -qi 'separate browser profile' '${HOWTO}'" "cloud-howto states the browser-profile rule"
check "grep -qi 'xquartz' '${HOWTO}'" "cloud-howto says to keep XQuartz off the Mac"
if grep -q 'The key can also push to your repos' "${HOWTO}"; then
    fail "cloud-howto still documents an account key that can push"
else
    pass "the push-capable account-key wording is gone"
fi

echo "--- TF15.6 / TF15.7: stopped means disarmed ---"
check "grep -qE '^stop:[[:space:]]*vnc-down' '${MK}'" "make stop depends on vnc-down"
check "make -C '${REPO_DIR}/terraform/oci' -n stop 2>/dev/null | grep -q 'vnc_access=none'" \
    "a dry-run stop reaches the vnc_access=none apply"
check "make -C '${REPO_DIR}/terraform/oci' -n stop 2>/dev/null | grep -q 'SOFTSTOP'" \
    "a dry-run stop still issues the SOFTSTOP"
check "grep -qi 'stopped means disarmed' '${MK}'" "make help says stopping disarms"
if grep -qE '^[[:space:]]*systemctl enable dome-vnc' "${BMB}"; then
    fail "bare-metal-base.sh still enables the VNC units at boot"
else
    pass "VNC units are installed but not enabled"
fi
check "grep -q 'Keep vnc_access OUT of this file' '${TFVARS_EX}'" \
    "tfvars.example documents the none steady state"

echo "--- TF15.8: the VNC port is not open to the internet ---"
check "grep -q 'var.vnc_allowed_cidr' '${NET}'" "network.tf sources the VNC rule from the variable"
check "grep -q 'variable \"vnc_allowed_cidr\"' '${VARS}'" "vnc_allowed_cidr is declared"
check "grep -q 'cidrhost(var.vnc_allowed_cidr' '${VARS}'" "vnc_allowed_cidr is validated as a CIDR"
check "grep -q 'vnc_allowed_cidr=' '${MK}'" "vnc-up passes the CIDR"
check "grep -q 'refusing to default to 0.0.0.0/0' '${MK}'" \
    "vnc-up fails loudly rather than widening to the internet"
# The SSH rule keeps 0.0.0.0/0 deliberately; the VNC block must not.
vnc_block=$(awk '/dynamic "ingress_security_rules"/{f=1} f{print} /^  }/{if(f)exit}' "${NET}")
if echo "${vnc_block}" | grep -q '0\.0\.0\.0/0'; then
    fail "the VNC ingress block still hardcodes 0.0.0.0/0"
else
    pass "no 0.0.0.0/0 inside the VNC ingress block"
fi
check "grep -q 'source   = \"0.0.0.0/0\"' '${NET}'" "the SSH rule still admits any source (deliberate)"

echo "--- TF15.9: the audit ---"
check "grep -qE '^audit:' '${MK}'" "make audit exists"
check "grep -qE '^\.PHONY:.*audit' '${MK}'" "audit is .PHONY"
check "grep -q 'make audit' '${MK}'" "audit appears in make help"
for path in '.claude/.credentials.json' '.git-credentials' '.config/gh' 'oauthAccount' 'PRIVATE KEY'; do
    check "grep -q '${path}' '${AUDIT}'" "box-audit checks ${path}"
done
AUD="${TMPD}/home"
mkdir -p "${AUD}/.ssh"
check "bash '${AUDIT}' '${AUD}'" "audit passes on a clean home"
mkdir -p "${AUD}/.claude"
echo '{}' > "${AUD}/.claude/.credentials.json"
check "! bash '${AUDIT}' '${AUD}'" "audit fails when a credential file appears"
rm -rf "${AUD}/.claude"
printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\n' > "${AUD}/.ssh/id_x"
check "! bash '${AUDIT}' '${AUD}'" "audit fails when a private key appears"

echo "--- TF15.11 / TF15.12: keys and sshd ---"
check "grep -q 'id_dome_cloud' '${MK}'" "Makefile defaults to the per-box key"
check "grep -q 'id_dome_cloud' '${TFVARS_EX}'" "tfvars.example points at the per-box key"
check "grep -qi 'ForwardAgent no' '${HOWTO}'" "cloud-howto documents ForwardAgent no"
check "test -f '${SSHD_DROPIN}'" "the sshd drop-in template exists"
for d in 'AllowAgentForwarding no' 'X11Forwarding no' 'PermitRootLogin no'; do
    check "grep -q '^${d}\$' '${SSHD_DROPIN}'" "drop-in sets ${d}"
done
check "grep -q 'AllowTcpForwarding' '${SSHD_DROPIN}'" \
    "drop-in records that port forwarding stays on"
check "grep -q '60-dome-hardening.conf' '${BMB}'" "bare-metal-base.sh installs the drop-in"
check "grep -q 'sshd -t' '${BMB}'" "bare-metal-base.sh validates sshd before reloading"
check "grep -q 'systemctl mask --now rpcbind' '${BMB}'" "bare-metal-base.sh masks rpcbind"
check "grep -qi 'NOPASSWD' '${HOWTO}'" "cloud-howto records the NOPASSWD sudo decision"
check "grep -qi 'fail2ban' '${HOWTO}'" "cloud-howto records why fail2ban is skipped"

echo "--- TF15.13: TLS on the public listener ---"
check "grep -q 'TLS_ARGS' '${SD}'" "start-desktop builds TLS args"
check "grep -q 'openssl req -x509' '${SD}'" "start-desktop generates a cert when absent"
check "grep -q 'DOME_VNC_ACCESS}\" == \"public\"' '${SD}'" "TLS is gated to public mode"
check "grep -qi 'self-signed' '${HOWTO}'" "cloud-howto warns about the self-signed cert"
check "grep -qi 'truncated to 8 characters' '${HOWTO}'" \
    "cloud-howto documents the 8-character VNC password truncation"

echo "--- syntax ---"
for f in "${BMB}" "${BUILD}" "${SD}" "${AUDIT}" "${MANIFEST_DIR}/lib.sh"; do
    bash -n "$f" && pass "syntax: $(basename "$f")" || fail "syntax: $(basename "$f")"
done
if command -v terraform >/dev/null 2>&1; then
    check "terraform -chdir='${REPO_DIR}/terraform/oci' validate -no-color" "terraform validate"
else
    echo "  SKIP: terraform not installed"
fi

echo ""
echo "=== F15: ${PASS} passed, ${FAIL} failed ==="
[[ "${FAIL}" -eq 0 ]]
