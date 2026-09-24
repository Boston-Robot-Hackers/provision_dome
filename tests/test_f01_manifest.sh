#!/usr/bin/env bash
# Tests for F01: manifest as single source of truth.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_DIR="${REPO_DIR}/manifest"
source "${MANIFEST_DIR}/lib.sh"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

assert_file() {
    local f="$1"
    [[ -f "$f" ]] && pass "exists: ${f#$REPO_DIR/}" || fail "missing: ${f#$REPO_DIR/}"
}

assert_field() {
    local file="$1" key="$2"
    grep -qF "$key" "$file" && pass "${file#$REPO_DIR/} has '$key'" || fail "${file#$REPO_DIR/} missing '$key'"
}

assert_no_hardcode() {
    local file="$1" pattern="$2" desc="$3"
    grep -qE "$pattern" "$file" && fail "${file#$REPO_DIR/} still hardcodes: $desc" || pass "${file#$REPO_DIR/} no hardcoded $desc"
}

assert_lib_field() {
    local section="$1" field="$2" file="$3" expected="$4"
    source "${MANIFEST_DIR}/lib.sh"
    local got
    got=$(manifest_field "$section" "$field" "$file")
    [[ "$got" == "$expected" ]] && pass "lib.sh manifest_field [$section].$field" || fail "lib.sh manifest_field [$section].$field: got='$got' expected='$expected'"
}

echo "=== F01 manifest tests ==="

echo "--- Manifest files exist ---"
assert_file "${MANIFEST_DIR}/config.txt"
assert_file "${MANIFEST_DIR}/packages.txt"
assert_file "${MANIFEST_DIR}/pip.txt"
assert_file "${MANIFEST_DIR}/repos.txt"
assert_file "${MANIFEST_DIR}/apt-repos.txt"
assert_file "${MANIFEST_DIR}/tools.txt"
assert_file "${MANIFEST_DIR}/colcon.txt"
assert_file "${MANIFEST_DIR}/rosdep.txt"
assert_file "${MANIFEST_DIR}/dirs.txt"
assert_file "${MANIFEST_DIR}/lib.sh"

echo "--- config.txt required fields ---"
assert_field "${MANIFEST_DIR}/config.txt" "ROS_DISTRO="
assert_field "${MANIFEST_DIR}/config.txt" "UBUNTU_CODENAME="
assert_field "${MANIFEST_DIR}/config.txt" "DOME_USER="

echo "--- bashrc exports ROS_DISTRO before sourcing rosutils ---"
bashrc_body=$(grep -v '^[[:space:]]*#' "${MANIFEST_DIR}/bashrc")
export_line=$(echo "$bashrc_body" | grep -n "ROS_DISTRO=" | head -1 | cut -d: -f1)
source_line=$(echo "$bashrc_body" | grep -n "source ~/rosutils/ros2_robot_bashrc.bash" | head -1 | cut -d: -f1)
if [[ -n "$export_line" && -n "$source_line" && "$export_line" -lt "$source_line" ]]; then
    pass "bashrc exports ROS_DISTRO before sourcing ros2_robot_bashrc.bash"
else
    fail "bashrc must export ROS_DISTRO before sourcing ros2_robot_bashrc.bash (it requires ROS_DISTRO set)"
fi

echo "--- packages.txt [ros] has no bogus self-referential entry ---"
ros_pkgs=$(awk '/^\[ros\]/{f=1;next} /^\[/{f=0} f && /^[^#[:space:]]/' "${MANIFEST_DIR}/packages.txt")
echo "$ros_pkgs" | grep -qx "dome-docker" \
    && fail "packages.txt [ros] still lists bogus 'dome-docker' (not a real ROS package — apt install fails: ros-<distro>-dome-docker not found)" \
    || pass "packages.txt [ros] has no bogus 'dome-docker' entry"

echo "--- apt-repos.txt sections and fields ---"
for sect in doppler github-cli vscode; do
    for field in key_url key_file key_dearmor list packages; do
        source "${MANIFEST_DIR}/lib.sh"
        val=$(manifest_field "$sect" "$field" "${MANIFEST_DIR}/apt-repos.txt")
        [[ -n "$val" ]] && pass "apt-repos.txt [$sect].$field set" || fail "apt-repos.txt [$sect].$field missing"
    done
done

echo "--- colcon.txt required fields ---"
assert_field "${MANIFEST_DIR}/colcon.txt" "packages_skip"

echo "--- rosdep.txt required fields ---"
assert_field "${MANIFEST_DIR}/rosdep.txt" "skip_keys"

echo "--- dirs.txt non-empty ---"
count=$(grep -c '^[^#[:space:]]' "${MANIFEST_DIR}/dirs.txt" || true)
[[ "$count" -gt 0 ]] && pass "dirs.txt has $count entries" || fail "dirs.txt empty"

echo "--- tools.txt has mcfly, claude-code ---"
assert_field "${MANIFEST_DIR}/tools.txt" "[mcfly]"
assert_field "${MANIFEST_DIR}/tools.txt" "[claude-code]"

echo "--- bare-metal-base.sh supports curl-bash tool method ---"
grep -q 'curl-bash' "${REPO_DIR}/scripts/bare-metal-base.sh" \
    && pass "bare-metal-base.sh handles curl-bash method" \
    || fail "bare-metal-base.sh handles curl-bash method"

echo "--- bare-metal-base.sh runs run_as_user tools as DOME_USER, not root ---"
grep -q 'run_as_user' "${REPO_DIR}/scripts/bare-metal-base.sh" \
    && pass "bare-metal-base.sh reads run_as_user field" \
    || fail "bare-metal-base.sh reads run_as_user field"
grep -q 'sudo -u "\${DOME_USER}"' "${REPO_DIR}/scripts/bare-metal-base.sh" \
    && pass "bare-metal-base.sh can run tool installers as DOME_USER" \
    || fail "bare-metal-base.sh can run tool installers as DOME_USER"
for tool in claude-code; do
    val=$(manifest_field "$tool" run_as_user "${MANIFEST_DIR}/tools.txt")
    [[ "$val" == "true" ]] \
        && pass "tools.txt [$tool] run_as_user=true" \
        || fail "tools.txt [$tool] run_as_user not set to true"
done

echo "--- lib.sh functions work ---"
tmpfile=$(mktemp)
cat > "$tmpfile" <<'EOF'
[testsect]
mykey = myvalue
other = another value
EOF
source "${MANIFEST_DIR}/lib.sh"
got=$(manifest_field "testsect" "mykey" "$tmpfile")
[[ "$got" == "myvalue" ]] && pass "manifest_field basic lookup" || fail "manifest_field basic lookup: got='$got'"
got=$(manifest_sections "$tmpfile")
[[ "$got" == "testsect" ]] && pass "manifest_sections" || fail "manifest_sections: got='$got'"
manifest_require "testsect" "mykey" "$tmpfile" >/dev/null && pass "manifest_require found" || fail "manifest_require found"
( manifest_require "testsect" "nosuchkey" "$tmpfile" ) >/dev/null 2>&1 && fail "manifest_require should error on missing" || pass "manifest_require errors on missing"
rm -f "$tmpfile"

echo "--- Dockerfile.base no hardcoded apt-repo URLs ---"
assert_no_hardcode "${REPO_DIR}/Dockerfile.base" "packages\.doppler\.com" "Doppler URL"
assert_no_hardcode "${REPO_DIR}/Dockerfile.base" "cli\.github\.com/packages/githubcli" "GitHub CLI URL"
assert_no_hardcode "${REPO_DIR}/Dockerfile.base" "cantino/mcfly" "mcfly URL"

echo "--- Dockerfile no hardcoded manifest values ---"
assert_no_hardcode "${REPO_DIR}/Dockerfile" "\-\-symlink-install" "colcon --symlink-install flag"
assert_no_hardcode "${REPO_DIR}/Dockerfile" "ament_python gazebo_ros_pkgs" "rosdep skip-keys"
assert_no_hardcode "${REPO_DIR}/Dockerfile" '\.local/bin"' "hardcoded dirs"

echo "--- repos.txt entries parse via clone_section's awk extraction ---"
for sect in root root-pi ros_ws uros_ws; do
    count=$(awk -v s="$sect" '$0=="["s"]"{f=1;next} /^\[/{f=0} f && /^[^#[:space:]]/ && NF' \
        "${MANIFEST_DIR}/repos.txt" | wc -l | tr -d ' ')
    [[ "$count" -gt 0 ]] \
        && pass "repos.txt [$sect] has $count entries extractable by clone_section" \
        || fail "repos.txt [$sect] extracted 0 entries -- check for leading whitespace on entry lines"
done

echo "--- clone_section skips already-cloned repos ---"
grep -q '\[\[ -d "${base_dir}/${REPO_DEST}" \]\]' "${REPO_DIR}/scripts/bare-metal-build.sh" \
    && pass "bare-metal-build.sh clone_section checks for existing dest dir before cloning" \
    || fail "bare-metal-build.sh clone_section checks for existing dest dir before cloning"

echo "--- Bare-metal scripts syntax check ---"
bash -n "${REPO_DIR}/scripts/bare-metal-base.sh" && pass "bare-metal-base.sh syntax" || fail "bare-metal-base.sh syntax"
bash -n "${REPO_DIR}/scripts/bare-metal-build.sh" && pass "bare-metal-build.sh syntax" || fail "bare-metal-build.sh syntax"

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck "${REPO_DIR}/scripts/bare-metal-base.sh" && pass "bare-metal-base.sh shellcheck" || fail "bare-metal-base.sh shellcheck"
    shellcheck "${REPO_DIR}/scripts/bare-metal-build.sh" && pass "bare-metal-build.sh shellcheck" || fail "bare-metal-build.sh shellcheck"
else
    echo "  SKIP: shellcheck not installed"
fi

echo "--- dome-config.sh sourced under zsh ---"
if command -v zsh >/dev/null 2>&1; then
    got=$(cd "${REPO_DIR}" && zsh -c 'source scripts/dome-config.sh && echo "$DOME_USER"' 2>&1)
    [[ -n "$got" && "$got" != *ERROR* ]] \
        && pass "dome-config.sh sourced cleanly under zsh (DOME_USER='$got')" \
        || fail "dome-config.sh under zsh: $got"
else
    echo "  SKIP: zsh not installed"
fi

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
[[ "${FAIL}" -eq 0 ]]
