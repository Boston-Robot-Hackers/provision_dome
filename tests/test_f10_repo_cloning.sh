#!/usr/bin/env bash
# Tests for F10: PRIVATE_REPO marker parsing and selectable repo cloning.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_DIR="${REPO_DIR}/manifest"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

source "${MANIFEST_DIR}/lib.sh"

echo "=== F10 repo cloning tests ==="

check_parse() {
    local label="$1" line="$2" want_dest="$3" want_branch="$4" want_private="$5"
    manifest_parse_repo "${line}"
    if [[ "${REPO_DEST}" == "${want_dest}" && "${REPO_BRANCH}" == "${want_branch}" \
        && "${REPO_IS_PRIVATE}" == "${want_private}" ]]; then
        pass "parse: ${label}"
    else
        fail "parse: ${label} got dest='${REPO_DEST}' branch='${REPO_BRANCH}' private='${REPO_IS_PRIVATE}'"
    fi
}

echo "--- manifest_parse_repo handles all line shapes ---"
check_parse "url dest" "https://x/a.git a" "a" "" "false"
check_parse "url dest branch" "https://x/a.git a devel" "a" "devel" "false"
check_parse "url dest PRIVATE_REPO" "git@x:o/a.git a PRIVATE_REPO" "a" "" "true"
check_parse "url dest branch PRIVATE_REPO" "git@x:o/a.git a devel PRIVATE_REPO" "a" "devel" "true"
check_parse "url dest PRIVATE_REPO branch" "git@x:o/a.git a PRIVATE_REPO devel" "a" "devel" "true"

echo "--- both clone_section copies use the shared parser ---"
for f in scripts/bare-metal-build.sh Dockerfile; do
    grep -q 'manifest_parse_repo' "${REPO_DIR}/${f}" \
        && pass "${f} uses manifest_parse_repo" || fail "${f} missing manifest_parse_repo"
    grep -q 'read -r repo dest branch' "${REPO_DIR}/${f}" \
        && fail "${f} still reads a trailing field as the branch" \
        || pass "${f} no longer reads a trailing field as the branch"
done
grep -q 'source /manifest/lib.sh' "${REPO_DIR}/Dockerfile" \
    && pass "Dockerfile sources lib.sh before cloning" || fail "Dockerfile does not source lib.sh"

echo "--- repos.txt marker rules ---"
bad_private=$(grep -E '^git@' "${MANIFEST_DIR}/repos.txt" | grep -vc 'PRIVATE_REPO' || true)
[[ "${bad_private}" == "0" ]] \
    && pass "every git@ line carries PRIVATE_REPO" \
    || fail "${bad_private} git@ line(s) missing PRIVATE_REPO"
bad_public=$(grep -E '^https://' "${MANIFEST_DIR}/repos.txt" | grep -c 'PRIVATE_REPO' || true)
[[ "${bad_public}" == "0" ]] \
    && pass "no https:// line carries PRIVATE_REPO" \
    || fail "${bad_public} https:// line(s) wrongly marked PRIVATE_REPO"

echo "--- marker never becomes a branch ---"
leaks=0
while read -r line; do
    manifest_parse_repo "${line}"
    [[ "${REPO_BRANCH}" == "PRIVATE_REPO" ]] && leaks=$((leaks+1))
done < <(grep -E '^(git@|https://)' "${MANIFEST_DIR}/repos.txt")
[[ "${leaks}" == "0" ]] && pass "no repos.txt line parses PRIVATE_REPO as a branch" \
    || fail "${leaks} line(s) parse PRIVATE_REPO as a branch"
manifest_parse_repo "$(grep 'better_launch' "${MANIFEST_DIR}/repos.txt")"
[[ "${REPO_BRANCH}" == "devel" ]] \
    && pass "better_launch still resolves branch devel" \
    || fail "better_launch branch: got '${REPO_BRANCH}'"

echo "--- DOME_CLONE_OVERRIDE is documented and unset by default ---"
grep -q '^# DOME_CLONE_OVERRIDE' "${MANIFEST_DIR}/config.txt" \
    && pass "config.txt documents DOME_CLONE_OVERRIDE" || fail "config.txt missing DOME_CLONE_OVERRIDE docs"
grep -q '^DOME_CLONE_OVERRIDE=' "${MANIFEST_DIR}/config.txt" \
    && fail "config.txt sets DOME_CLONE_OVERRIDE (must be unset by default)" \
    || pass "config.txt leaves DOME_CLONE_OVERRIDE unset"

echo "--- DOME_CLONE_OVERRIDE precedence: env > user.txt > empty ---"
resolve_override() {
    local user_file="$1" env_value="$2" file_value
    file_value=$(grep '^[[:space:]]*DOME_CLONE_OVERRIDE=' "${user_file}" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]' || true)
    echo "${env_value:-${file_value}}"
}
scratch=$(mktemp -d)
trap 'rm -rf "${scratch}"' EXIT
echo "DOME_CLONE_OVERRIDE=PUBLIC_ONLY" > "${scratch}/user.txt"
[[ "$(resolve_override "${scratch}/user.txt" NONE)" == "NONE" ]] \
    && pass "env wins over user.txt" || fail "env should win over user.txt"
[[ "$(resolve_override "${scratch}/user.txt" "")" == "PUBLIC_ONLY" ]] \
    && pass "user.txt used when env unset" || fail "user.txt should be used when env unset"
[[ -z "$(resolve_override "${scratch}/missing.txt" "")" ]] \
    && pass "empty when neither is set" || fail "should be empty when neither is set"
grep -q 'DOME_CLONE_OVERRIDE:-' "${REPO_DIR}/scripts/bare-metal-build.sh" \
    && pass "bare-metal-build.sh resolves DOME_CLONE_OVERRIDE" || fail "bare-metal-build.sh does not resolve DOME_CLONE_OVERRIDE"

echo "--- override validation (TF10.3) ---"
for value in "" PUBLIC_ONLY NONE; do
    (manifest_validate_clone_override "${value}") 2>/dev/null \
        && pass "accepts '${value:-unset}'" || fail "rejected '${value:-unset}'"
done
(manifest_validate_clone_override "public_only") 2>/dev/null \
    && fail "accepted unrecognized value" || pass "rejects unrecognized value"

echo "--- clone gate ---"
should_clone() { (manifest_should_clone "$@") 2>/dev/null; }
private_url="git@x:o/p.git"; public_url="https://x/o/p.git"
should_clone "" true "${private_url}" && pass "unset clones a private repo" || fail "unset skipped a private repo"
should_clone "" false "${public_url}" && pass "unset clones a public repo" || fail "unset skipped a public repo"
should_clone PUBLIC_ONLY true "${private_url}" && fail "PUBLIC_ONLY cloned a private repo" || pass "PUBLIC_ONLY skips a private repo"
should_clone PUBLIC_ONLY false "${public_url}" && pass "PUBLIC_ONLY clones a public repo" || fail "PUBLIC_ONLY skipped a public repo"
should_clone NONE false "${public_url}" && fail "NONE cloned a repo" || pass "NONE skips a public repo"
should_clone NONE true "${private_url}" && fail "NONE cloned a repo" || pass "NONE skips a private repo"

echo "--- SSH safety net (TF10.4) ---"
for override in PUBLIC_ONLY; do
    for url in "git@x:o/leak.git" "ssh://git@x/o/leak.git"; do
        err=$( (manifest_should_clone "${override}" false "${url}") 2>&1 >/dev/null) && rc=0 || rc=$?
        [[ "${rc}" -ne 0 && "${err}" == *"${url}"* ]] \
            && pass "${override}: unmarked ${url} errors and names the repo" \
            || fail "${override}: unmarked ${url} rc=${rc} err='${err}'"
    done
done
should_clone "" false "git@x:o/ok.git" \
    && pass "safety net inert when override unset" || fail "safety net fired with override unset"

echo "--- additive guarantee: unset override clones every repos.txt line ---"
total=0; cloned=0
while read -r line; do
    total=$((total+1))
    manifest_parse_repo "${line}"
    should_clone "" "${REPO_IS_PRIVATE}" "${REPO_URL}" && cloned=$((cloned+1))
done < <(grep -E '^(git@|https://)' "${MANIFEST_DIR}/repos.txt")
[[ "${total}" -gt 0 && "${cloned}" == "${total}" ]] \
    && pass "unset override clones all ${total} repos" || fail "unset override cloned ${cloned}/${total}"

echo "--- PUBLIC_ONLY selects only credential-free repos ---"
ssh_cloned=0
while read -r line; do
    manifest_parse_repo "${line}"
    should_clone PUBLIC_ONLY "${REPO_IS_PRIVATE}" "${REPO_URL}" \
        && [[ "${REPO_URL}" == git@* ]] && ssh_cloned=$((ssh_cloned+1))
done < <(grep -E '^(git@|https://)' "${MANIFEST_DIR}/repos.txt")
[[ "${ssh_cloned}" == "0" ]] && pass "PUBLIC_ONLY selects no git@ repo from repos.txt" \
    || fail "PUBLIC_ONLY would clone ${ssh_cloned} git@ repo(s)"

echo "--- build script wiring ---"
grep -q 'manifest_should_clone' "${REPO_DIR}/scripts/bare-metal-build.sh" \
    && pass "clone_section calls manifest_should_clone" || fail "clone_section missing the gate"
grep -q 'manifest_validate_clone_override' "${REPO_DIR}/scripts/bare-metal-build.sh" \
    && pass "build validates DOME_CLONE_OVERRIDE" || fail "build does not validate the override"

echo "--- cloud host is credential-free (TF10.5) ---"
TEMPLATE="${REPO_DIR}/host-file-templates/cloud/user-data.template"
grep -q 'DOME_CLONE_OVERRIDE=PUBLIC_ONLY' "${TEMPLATE}" \
    && pass "cloud-init template sets DOME_CLONE_OVERRIDE=PUBLIC_ONLY" \
    || fail "cloud-init template missing DOME_CLONE_OVERRIDE=PUBLIC_ONLY"
grep -qE 'PRIVATE KEY|ssh-keygen|id_ed25519' "${TEMPLATE}" \
    && fail "cloud-init template contains key material or key generation" \
    || pass "cloud-init template contains no private-key material"
grep -q 'PUBLIC_ONLY' "${REPO_DIR}/02-doc/cloud-howto.md" \
    && pass "cloud-howto.md mentions PUBLIC_ONLY" || fail "cloud-howto.md missing PUBLIC_ONLY"
grep -qi 'no GitHub key' "${REPO_DIR}/02-doc/cloud-howto.md" \
    && pass "cloud-howto.md says no GitHub key is needed" || fail "cloud-howto.md missing 'no GitHub key'"

echo "--- bashrc works without rosutils (PUBLIC_ONLY) ---"
grep -q 'if \[\[ -f ~/rosutils/ros2_robot_bashrc.bash \]\]' "${MANIFEST_DIR}/bashrc" \
    && pass "bashrc sources rosutils only when present" || fail "bashrc does not guard the rosutils source"
grep -q 'source /opt/ros/${ROS_DISTRO}/setup.bash' "${MANIFEST_DIR}/bashrc" \
    && pass "bashrc falls back to the ROS underlay" || fail "bashrc has no ROS underlay fallback"
grep -q 'source ~/ros2_ws/install/setup.bash' "${MANIFEST_DIR}/bashrc" \
    && pass "bashrc falls back to the workspace overlay" || fail "bashrc has no workspace overlay fallback"
bash -n "${MANIFEST_DIR}/bashrc" && pass "syntax: manifest/bashrc" || fail "syntax: manifest/bashrc"

echo "--- syntax ---"
for f in scripts/bare-metal-build.sh manifest/lib.sh; do
    bash -n "${REPO_DIR}/${f}" && pass "syntax: ${f}" || fail "syntax: ${f}"
done

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
[[ "${FAIL}" -eq 0 ]]
