#!/usr/bin/env bash
# Tests for F17: named repo sets via REPOS_CONFIG. Real cloning needs network
# and root, so the clone paths are checked statically the way the rest of the
# bare-metal script suite is; the resolver and the parser are pure logic and
# are exercised for real.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_DIR="${REPO_DIR}/manifest"
CFG="${MANIFEST_DIR}/config.txt"
BUILD="${REPO_DIR}/scripts/bare-metal-build.sh"
DOCKERFILE="${REPO_DIR}/Dockerfile"
TEMPLATE="${REPO_DIR}/host-file-templates/cloud/user-data.template"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

source "${MANIFEST_DIR}/lib.sh"

echo "=== F17 REPOS_CONFIG tests ==="

echo "--- TF17.1: manifest_repos_file resolves names to files ---"
got=$(manifest_repos_file SAFE "${MANIFEST_DIR}")
[[ "${got}" == "${MANIFEST_DIR}/repos-safe.txt" ]] \
    && pass "SAFE resolves to repos-safe.txt" || fail "SAFE resolved to '${got}'"

got=$(manifest_repos_file DOME "${MANIFEST_DIR}")
[[ "${got}" == "${MANIFEST_DIR}/repos-dome.txt" ]] \
    && pass "DOME resolves to repos-dome.txt" || fail "DOME resolved to '${got}'"

got=$(manifest_repos_file NONE "${MANIFEST_DIR}")
[[ -z "${got}" ]] \
    && pass "NONE is reserved and resolves to the empty string" \
    || fail "NONE resolved to '${got}' instead of empty"

if err=$(manifest_repos_file NONSENSE "${MANIFEST_DIR}" 2>&1); then
    fail "an unknown set name exited zero"
else
    pass "an unknown set name exits non-zero"
    [[ "${err}" == *"repos-nonsense.txt"* ]] \
        && pass "the error names the path it looked for" \
        || fail "the error does not name the path: ${err}"
fi

[[ ! -f "${MANIFEST_DIR}/repos-none.txt" ]] \
    && pass "no repos-none.txt shadows the reserved NONE" \
    || fail "manifest/repos-none.txt exists and must not"

echo "--- TF17.2: both set files parse under clone_section's extraction ---"
# The exact awk clone_section uses, so a leading-whitespace regression in a set
# file fails here rather than silently yielding an empty section on a build.
extract() {
    awk -v s="$2" '$0=="["s"]"{f=1;next} /^\[/{f=0} f && /^[^#[:space:]]/ && NF' "$1"
}

for set_file in repos-dome.txt repos-safe.txt; do
    path="${MANIFEST_DIR}/${set_file}"
    total=0
    for sect in $(manifest_sections "${path}"); do
        count=$(extract "${path}" "${sect}" | wc -l | tr -d ' ')
        total=$((total + count))
    done
    [[ "${total}" -gt 0 ]] \
        && pass "${set_file} yields ${total} entries across its sections" \
        || fail "${set_file} yields no entries at all"
done

for sect in root root-pi ros_ws uros_ws; do
    manifest_sections "${MANIFEST_DIR}/repos-safe.txt" | grep -qx "${sect}" \
        && pass "repos-safe.txt declares [${sect}]" \
        || fail "repos-safe.txt is missing [${sect}]"
done

safe_dests=$(extract "${MANIFEST_DIR}/repos-safe.txt" root; \
             extract "${MANIFEST_DIR}/repos-safe.txt" root-pi; \
             extract "${MANIFEST_DIR}/repos-safe.txt" ros_ws; \
             extract "${MANIFEST_DIR}/repos-safe.txt" uros_ws)
dest_list=$(echo "${safe_dests}" | awk 'NF{print $2}' | sort | tr '\n' ' ')
[[ "${dest_list}" == "better_launch rosutils " ]] \
    && pass "SAFE is exactly rosutils + better_launch" \
    || fail "SAFE holds '${dest_list}'"

if grep -qE '(^|[[:space:]])(git@|ssh://)' "${MANIFEST_DIR}/repos-safe.txt"; then
    fail "repos-safe.txt has an SSH url and would demand a GitHub key"
else
    pass "repos-safe.txt is all-HTTPS, so SAFE needs no GitHub key"
fi

echo "--- TF17.3: bare-metal-build.sh resolves the set ---"
grep -q '^REPOS_CONFIG=DOME$' "${CFG}" \
    && pass "config.txt defaults REPOS_CONFIG to DOME" \
    || fail "config.txt has no REPOS_CONFIG=DOME default"
[[ "$(manifest_config REPOS_CONFIG "${CFG}")" == "DOME" ]] \
    && pass "manifest_config reads the REPOS_CONFIG default" \
    || fail "manifest_config did not read REPOS_CONFIG=DOME"

grep -q 'REPOS_CONFIG="\${REPOS_CONFIG:-\${_REPOS_CONFIG_FILE:-\${_REPOS_CONFIG_DEFAULT}}}"' "${BUILD}" \
    && pass "build script cascades env > user.txt > config.txt" \
    || fail "build script does not cascade REPOS_CONFIG in that order"
grep -q 'REPOS_FILE=$(manifest_repos_file "\${REPOS_CONFIG}" "\${MANIFEST_DIR}")' "${BUILD}" \
    && pass "build script resolves the set through manifest_repos_file" \
    || fail "build script does not call manifest_repos_file"
grep -q 'local repos_file="\$3"' "${BUILD}" \
    && pass "clone_section takes the repos file as an argument" \
    || fail "clone_section does not take a repos file argument"
grep -q '"\${repos_file}")$' "${BUILD}" \
    && pass "clone_section extracts from the passed file" \
    || fail "clone_section still reads a hardcoded manifest path"
grep -q 'if \[\[ -n "\${REPOS_FILE}" \]\]; then' "${BUILD}" \
    && pass "NONE skips every clone_section call" \
    || fail "build script clones even when the set resolves to nothing"
grep -q 'reserved value: cloning no repositories' "${BUILD}" \
    && pass "NONE is reported, not silently empty" \
    || fail "build script does not report the reserved NONE value"
grep -q 'echo "==> REPOS_CONFIG=\${REPOS_CONFIG} (\${REPOS_FILE}, \${count} repos, \${needs})"' "${BUILD}" \
    && pass "the report names the set, file, count and key need" \
    || fail "the resolve-time report line is missing or reshaped"
grep -q 'needs a GitHub SSH key' "${BUILD}" \
    && pass "the key need is derived from the urls in the set" \
    || fail "build script does not derive whether a key is needed"

echo "--- TF17.3: the old mechanism is gone from the clone path ---"
for f in scripts/bare-metal-build.sh Dockerfile manifest/lib.sh manifest/config.txt; do
    if grep -q 'DOME_CLONE_OVERRIDE\|manifest_should_clone\|manifest_validate_clone_override' "${REPO_DIR}/${f}"; then
        fail "${f} still references the removed override mechanism"
    else
        pass "${f} has no trace of DOME_CLONE_OVERRIDE"
    fi
done

echo "--- TF17.4: the Dockerfile clone path takes the set too ---"
grep -q '^ARG REPOS_CONFIG=DOME$' "${DOCKERFILE}" \
    && pass "Dockerfile declares ARG REPOS_CONFIG=DOME" \
    || fail "Dockerfile has no REPOS_CONFIG build arg"
grep -q 'manifest_repos_file "\${REPOS_CONFIG}" /manifest' "${DOCKERFILE}" \
    && pass "Dockerfile resolves the set through the shared resolver" \
    || fail "Dockerfile does not call manifest_repos_file"
grep -q '/manifest/repos\.txt' "${DOCKERFILE}" \
    && fail "Dockerfile still references the literal repos.txt" \
    || pass "Dockerfile references no literal repos.txt"
grep -q 'REPOS_CONFIG: \${REPOS_CONFIG:-DOME}' "${REPO_DIR}/compose/compose.yaml" \
    && pass "compose passes REPOS_CONFIG as a build arg" \
    || fail "compose does not pass REPOS_CONFIG, so a Docker build cannot select a set"
grep -q 'export REPOS_CONFIG=' "${REPO_DIR}/scripts/dome-config.sh" \
    && pass "dome-config.sh exports REPOS_CONFIG for compose" \
    || fail "dome-config.sh does not export REPOS_CONFIG"

echo "--- TF17.5: the PRIVATE_REPO marker is gone ---"
if grep -rq 'PRIVATE_REPO' "${MANIFEST_DIR}"; then
    fail "PRIVATE_REPO still appears somewhere under manifest/"
else
    pass "no PRIVATE_REPO anywhere under manifest/"
fi
dome_count=$(awk '/^\[/{next} /^[^#[:space:]]/ && NF' "${MANIFEST_DIR}/repos-dome.txt" | wc -l | tr -d ' ')
[[ "${dome_count}" == "29" ]] \
    && pass "repos-dome.txt still holds 29 entries after the strip" \
    || fail "repos-dome.txt holds ${dome_count} entries, expected 29"

# Stripping a trailing token must not have eaten a dest or a revision: every
# entry still has 2 or 3 fields, and no dest is a bare url fragment.
malformed=0
while read -r line; do
    nf=$(echo "${line}" | awk '{print NF}')
    [[ "${nf}" -ge 2 && "${nf}" -le 3 ]] || malformed=$((malformed+1))
done < <(awk '/^\[/{next} /^[^#[:space:]]/ && NF' "${MANIFEST_DIR}/repos-dome.txt")
[[ "${malformed}" == "0" ]] \
    && pass "every repos-dome.txt entry has 2 or 3 fields" \
    || fail "${malformed} repos-dome.txt entries have the wrong field count"

echo "--- TF17.6: the parser reads one revision field, nothing else ---"
manifest_parse_repo "https://x/a.git a"
[[ "${REPO_DEST}" == "a" && -z "${REPO_BRANCH}" && -z "${REPO_COMMIT}" ]] \
    && pass "a two-field line sets no branch and no commit" \
    || fail "two-field line gave branch='${REPO_BRANCH}' commit='${REPO_COMMIT}'"
manifest_parse_repo "https://x/a.git a devel"
[[ "${REPO_BRANCH}" == "devel" && -z "${REPO_COMMIT}" ]] \
    && pass "a non-hex third field is a branch" \
    || fail "three-field line gave branch='${REPO_BRANCH}' commit='${REPO_COMMIT}'"
pin="2febc367e2e39bc6fbc223856447d326e465cc79"
manifest_parse_repo "https://x/a.git a ${pin}"
[[ "${REPO_COMMIT}" == "${pin}" && -z "${REPO_BRANCH}" ]] \
    && pass "a 40-hex third field is a commit pin, not a branch" \
    || fail "pinned line gave branch='${REPO_BRANCH}' commit='${REPO_COMMIT}'"

# The ordering hazard this feature's task list warns about: had the parser been
# simplified before the markers were stripped, this is the line that would have
# produced `git clone --branch PRIVATE_REPO` on 17 repos.
manifest_parse_repo "git@x:o/a.git a PRIVATE_REPO"
[[ "${REPO_BRANCH}" != "PRIVATE_REPO" ]] \
    && fail "a stray PRIVATE_REPO token would still be read as a branch" \
    || pass "a stray PRIVATE_REPO token would land in REPO_BRANCH (markers must stay stripped)"

for fn in manifest_should_clone manifest_validate_clone_override; do
    if declare -F "${fn}" >/dev/null; then
        fail "${fn} is still defined in lib.sh"
    else
        pass "${fn} is deleted"
    fi
done
if grep -q 'REPO_IS_PRIVATE' "${MANIFEST_DIR}/lib.sh"; then
    fail "lib.sh still sets REPO_IS_PRIVATE"
else
    pass "REPO_IS_PRIVATE is gone from the parser"
fi

echo "--- TF17.7: the cloud-init template selects SAFE ---"
grep -q 'REPOS_CONFIG=SAFE' "${TEMPLATE}" \
    && pass "the cloud template writes REPOS_CONFIG=SAFE" \
    || fail "the cloud template does not write REPOS_CONFIG=SAFE"
grep -q 'DOME_CLONE_OVERRIDE' "${TEMPLATE}" \
    && fail "the cloud template still mentions DOME_CLONE_OVERRIDE" \
    || pass "the cloud template no longer mentions DOME_CLONE_OVERRIDE"

echo "--- TF17.8: docs describe REPOS_CONFIG, not the old mechanism ---"
# current.md, history.md, chores.md and the F10/F15 files keep their historical
# mentions on purpose; this checks only the guides a reader follows today.
for doc in README.md 02-doc/cloud-howto.md 02-doc/pi-howto.md 02-doc/vm-howto.md \
           02-doc/docker-howto.md 02-doc/oci-howto.md 02-doc/manifest-format.md \
           02-doc/spec.md 02-doc/notes.md; do
    # PUBLIC_ONLY is in this list because grepping only for the flag name and
    # the marker missed three prose mentions of the *value* in cloud-howto.md,
    # one of which had become factually wrong (it called rosutils private and
    # absent; rosutils is public HTTPS and is in SAFE).
    if grep -q 'DOME_CLONE_OVERRIDE\|PRIVATE_REPO\|PUBLIC_ONLY' "${REPO_DIR}/${doc}"; then
        fail "${doc} still presents the removed mechanism as live"
    else
        pass "${doc} has no live DOME_CLONE_OVERRIDE/PRIVATE_REPO/PUBLIC_ONLY"
    fi
done
grep -q 'REPOS_CONFIG=SAFE' "${REPO_DIR}/02-doc/cloud-howto.md" \
    && pass "cloud-howto.md documents REPOS_CONFIG=SAFE" \
    || fail "cloud-howto.md does not document REPOS_CONFIG=SAFE"
grep -q 'REPOS_CONFIG=DOME' "${REPO_DIR}/02-doc/cloud-howto.md" \
    && pass "cloud-howto.md documents opting in with REPOS_CONFIG=DOME" \
    || fail "cloud-howto.md does not say how to opt into the private set"
grep -q 'repos-<set>.txt\|repos-&lt;set&gt;.txt' "${REPO_DIR}/02-doc/manifest-format.md" \
    && pass "manifest-format.md documents the per-set file naming" \
    || fail "manifest-format.md does not document repos-<set>.txt"

echo "--- TF17.9: no entry drifts between sets ---"
# Separate set files duplicate entries, which is this design's one real cost.
# Any dest named by more than one set must be byte-identical in all of them, so
# a hand-edit to one file cannot silently give two hosts different code.
# Compares whitespace-normalized entry lines keyed by dest, across every set
# file at once. Comment and section lines are excluded, or a comment merely
# mentioning a repo's name would read as a competing definition.
drift=$(awk '
    /^\[/ { next }
    /^[^#[:space:]]/ && NF {
        line = $1
        for (i = 2; i <= NF; i++) line = line " " $i
        if (($2 in seen) && seen[$2] != line) bad[$2] = 1
        seen[$2] = line
    }
    END { for (d in bad) printf "%s ", d }
' "${MANIFEST_DIR}"/repos-*.txt)
[[ -z "${drift}" ]] \
    && pass "every repo listed more than once has one identical definition" \
    || fail "these repos have drifted between or within set files: ${drift}"

# micro-ROS-Agent and micro_ros_msgs are listed twice in repos-dome.txt on
# purpose ([ros_ws] and [uros_ws]). Pinned here so a third duplicate, which is
# far more likely to be an accident, shows up as a failure.
dupes=$(awk '/^\[/{next} /^[^#[:space:]]/ && NF{print $2}' "${MANIFEST_DIR}/repos-dome.txt" \
    | LC_ALL=C sort | uniq -d | tr '\n' ' ')
[[ "${dupes}" == "micro-ROS-Agent micro_ros_msgs " ]] \
    && pass "repos-dome.txt's only intra-file duplicates are the micro-ROS pair" \
    || fail "repos-dome.txt duplicate dests changed: '${dupes}'"

echo "--- TF17.9: the F10 suite is retired ---"
[[ ! -f "${REPO_DIR}/tests/test_f10_repo_cloning.sh" ]] \
    && pass "tests/test_f10_repo_cloning.sh is deleted" \
    || fail "the F10 suite still exists and tests a removed mechanism"

echo "--- carried over from the retired F10 suite ---"
# Both clone paths must keep using the shared parser rather than re-deriving
# fields inline; the Dockerfile drifting from lib.sh is what F10 and F17 both
# had to go back and fix.
for f in scripts/bare-metal-build.sh Dockerfile; do
    grep -q 'manifest_parse_repo' "${REPO_DIR}/${f}" \
        && pass "${f} uses manifest_parse_repo" || fail "${f} missing manifest_parse_repo"
    grep -q 'read -r repo dest branch' "${REPO_DIR}/${f}" \
        && fail "${f} re-reads fields inline instead of using the parser" \
        || pass "${f} does not re-read repo fields inline"
done

# A host can legitimately have no rosutils (REPOS_CONFIG=NONE), so bashrc must
# still give an interactive shell a working ros2. Under F10 this was the
# PUBLIC_ONLY case and it broke live; the property outlives the mechanism.
grep -q 'if \[\[ -f ~/rosutils/ros2_robot_bashrc.bash \]\]' "${MANIFEST_DIR}/bashrc" \
    && pass "bashrc sources rosutils only when present" \
    || fail "bashrc does not guard the rosutils source"
grep -q 'source /opt/ros/${ROS_DISTRO}/setup.bash' "${MANIFEST_DIR}/bashrc" \
    && pass "bashrc falls back to the ROS underlay" || fail "bashrc has no ROS underlay fallback"
grep -q 'source ~/ros2_ws/install/setup.bash' "${MANIFEST_DIR}/bashrc" \
    && pass "bashrc falls back to the workspace overlay" \
    || fail "bashrc has no workspace overlay fallback"
bash -n "${MANIFEST_DIR}/bashrc" && pass "syntax: manifest/bashrc" || fail "syntax: manifest/bashrc"

echo "--- syntax ---"
for f in manifest/lib.sh scripts/bare-metal-build.sh scripts/dome-config.sh; do
    bash -n "${REPO_DIR}/${f}" && pass "syntax: ${f}" || fail "syntax: ${f}"
done

echo ""
echo "=== F17: ${PASS} passed, ${FAIL} failed ==="
[[ "${FAIL}" -eq 0 ]]
