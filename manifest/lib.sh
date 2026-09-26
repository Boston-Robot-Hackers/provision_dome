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

# manifest_parse_repo <repos.txt line>
# Sets REPO_URL, REPO_DEST, REPO_BRANCH, REPO_COMMIT and REPO_IS_PRIVATE.
# Trailing fields are the PRIVATE_REPO marker and one revision, in either
# order. A 40-hex revision is a commit pin (F15.3), anything else a branch:
# `git clone --branch` takes branches and tags only, so a pinned commit has to
# be cloned and then checked out, which is why the two are distinguished here
# rather than left as one field.
manifest_parse_repo() {
    local extra token
    read -r REPO_URL REPO_DEST extra <<< "$1"
    REPO_BRANCH=""
    REPO_COMMIT=""
    REPO_IS_PRIVATE=false
    for token in ${extra}; do
        if [[ "${token}" == "PRIVATE_REPO" ]]; then
            REPO_IS_PRIVATE=true
        elif [[ "${token}" =~ ^[0-9a-f]{40}$ ]]; then
            REPO_COMMIT="${token}"
        else
            REPO_BRANCH="${token}"
        fi
    done
}

# manifest_validate_clone_override <value>
# Errors on anything but unset, PUBLIC_ONLY or NONE, rather than guessing.
manifest_validate_clone_override() {
    case "$1" in
        ""|PUBLIC_ONLY|NONE) ;;
        *)
            echo "ERROR: DOME_CLONE_OVERRIDE='$1' is not one of: (unset) PUBLIC_ONLY NONE" >&2
            exit 1
            ;;
    esac
}

# manifest_should_clone <override> <is_private> <url>
# Returns 0 to clone, 1 to skip. Unset override always clones. Under
# PUBLIC_ONLY an unmarked SSH url is an error, so a private repo missing its
# marker can never pull in or require the account key.
manifest_should_clone() {
    local override="$1" is_private="$2" url="$3"
    case "${override}" in
        "") return 0 ;;
        NONE) return 1 ;;
    esac
    [[ "${is_private}" == "true" ]] && return 1
    if [[ "${url}" == git@* || "${url}" == ssh://* ]]; then
        echo "ERROR: ${url} needs an SSH credential but is not marked PRIVATE_REPO; refusing to clone under DOME_CLONE_OVERRIDE=${override}" >&2
        exit 1
    fi
    return 0
}
