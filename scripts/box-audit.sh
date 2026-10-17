#!/usr/bin/env bash
# box-audit.sh — fail if the box has accumulated credentials or private keys.
#
# F15.4: the "box is expendable" premise holds only while there is nothing on
# the box worth stealing. Provisioning installs claude-code and gh, and the
# first interactive login writes a live token to disk — silently, and without
# the premise being revisited. This is the check that notices.
#
# Run over ssh by `make -C terraform/oci audit`, or by hand on the box.
# Takes an optional home directory to scan, which is what lets the test suite
# exercise it against a seeded temp directory instead of a real box.
#
# Exits non-zero when anything is found: a check that only prints is a check
# nobody reads.
set -euo pipefail

HOME_DIR="${1:-${HOME}}"
FOUND=0

report() {
    echo "  FOUND: $1"
    FOUND=$((FOUND + 1))
}

echo "==> Auditing ${HOME_DIR} for credentials and private keys"

# Live credential files, by exact path.
[[ -f "${HOME_DIR}/.claude/.credentials.json" ]] \
    && report "${HOME_DIR}/.claude/.credentials.json (Claude Code login)"
[[ -f "${HOME_DIR}/.git-credentials" ]] \
    && report "${HOME_DIR}/.git-credentials (git stored credentials)"
[[ -d "${HOME_DIR}/.config/gh" ]] \
    && report "${HOME_DIR}/.config/gh (gh auth login)"

# An account token inside an otherwise-normal config file.
if [[ -f "${HOME_DIR}/.claude.json" ]] \
    && grep -qE '"(oauthAccount|primaryApiKey)"' "${HOME_DIR}/.claude.json"; then
    report "${HOME_DIR}/.claude.json contains oauthAccount/primaryApiKey"
fi

# Any private key, whatever it is called — the name is not the evidence, the
# header is. Scanned: all of ~/.ssh, plus the top level of the home directory.
# Not a full recursive walk: a provisioned box has ~20 cloned repos and a built
# colcon workspace under $HOME, and an audit slow enough to skip is an audit
# that gets skipped.
while IFS= read -r keyfile; do
    grep -qs -- '-----BEGIN .*PRIVATE KEY-----' "${keyfile}" \
        && report "${keyfile} (private key)"
done < <(
    find "${HOME_DIR}/.ssh" -type f 2>/dev/null || true
    find "${HOME_DIR}" -maxdepth 1 -type f 2>/dev/null || true
)

if [[ "${FOUND}" -gt 0 ]]; then
    echo ""
    echo "FAIL: ${FOUND} credential(s) or key(s) on this box." >&2
    echo "A public-mode box must hold none — see 02-doc/cloud-howto.md." >&2
    exit 1
fi

echo "  clean: no credential files, no private keys"
