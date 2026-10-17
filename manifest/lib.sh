#!/usr/bin/env bash
# Shared manifest parsing helpers — sourced by Dockerfiles and bare-metal scripts.

# manifest_field <section> <field> <file>
manifest_field() {
    local section="$1" field="$2" file="$3"
    awk -v s="[$section]" -v f="$field" \
        '$0==s{found=1;next} /^\[/{found=0} found && $0~"^"f"[[:space:]]*="{sub(/^[^=]*=[[:space:]]*/,""); print; exit}' \
        "$file"
}

# manifest_require <section> <field> <file>
# Like manifest_field but errors if value is empty or missing.
manifest_require() {
    local section="$1" field="$2" file="$3"
    local val
    val=$(manifest_field "$section" "$field" "$file")
    if [[ -z "$val" ]]; then
        echo "ERROR: [$section] $field not set in $file" >&2
        exit 1
    fi
    echo "$val"
}

# manifest_config <key> <file>
# Read a simple key=value from a flat config file. Errors if missing.
manifest_config() {
    local key="$1" file="$2"
    local val
    val=$(grep "^${key}=" "$file" | cut -d= -f2)
    if [[ -z "$val" ]]; then
        echo "ERROR: '$key' not set in $file" >&2
        exit 1
    fi
    echo "$val"
}

# manifest_sections <file>
manifest_sections() {
    awk '/^\[/{gsub(/[\[\]]/,""); print}' "$1"
}

# manifest_verify_sha256 <file> <expected>
# Verify a downloaded file before it is executed (F15.2). Returns non-zero on
# mismatch, printing both digests, so the caller can decide — it must never
# fall through to running the file. Returns non-zero on an empty expectation
# too: "no digest" is a caller bug here, not a permission to skip the check.
manifest_verify_sha256() {
    local file="$1" expected="$2" actual
    if [[ -z "${expected}" ]]; then
        echo "ERROR: no expected sha256 given for ${file}" >&2
        return 1
    fi
    if command -v sha256sum >/dev/null 2>&1; then
        actual=$(sha256sum "${file}" | cut -d' ' -f1)
    else
        actual=$(shasum -a 256 "${file}" | cut -d' ' -f1)
    fi
    if [[ "${actual}" != "${expected}" ]]; then
        echo "ERROR: sha256 mismatch for ${file}" >&2
        echo "  expected: ${expected}" >&2
        echo "  actual:   ${actual}" >&2
        return 1
    fi
}

# manifest_repos_file <set_name> <manifest_dir>
# Map a REPOS_CONFIG value to the manifest file naming that set's repos (F17).
# NONE is reserved: it returns the empty string, which keeps "clone nothing"
# structurally distinct from "set not found". A name with no file is a hard
# error naming the path it looked for, never a fallback to a default set and
# never an empty clone, which would read as a successful build.
manifest_repos_file() {
    local set_name="$1" manifest_dir="$2" path
    if [[ "${set_name}" == "NONE" ]]; then
        echo ""
        return 0
    fi
    path="${manifest_dir}/repos-$(echo "${set_name}" | tr '[:upper:]' '[:lower:]').txt"
    if [[ ! -f "${path}" ]]; then
        echo "ERROR: REPOS_CONFIG='${set_name}' names no repo set: ${path} not found" >&2
        return 1
    fi
    echo "${path}"
}

# manifest_parse_repo <repos-<set>.txt line>
# Sets REPO_URL, REPO_DEST, REPO_BRANCH and REPO_COMMIT. The one optional
# trailing field is a revision: 40 hex characters is a commit pin (F15.3),
# anything else a branch. `git clone --branch` takes branches and tags only, so
# a pinned commit has to be cloned and then checked out, which is why the two
# are distinguished here rather than left as one field.
manifest_parse_repo() {
    local revision
    read -r REPO_URL REPO_DEST revision <<< "$1"
    REPO_BRANCH=""
    REPO_COMMIT=""
    if [[ "${revision}" =~ ^[0-9a-f]{40}$ ]]; then
        REPO_COMMIT="${revision}"
    else
        REPO_BRANCH="${revision}"
    fi
}
