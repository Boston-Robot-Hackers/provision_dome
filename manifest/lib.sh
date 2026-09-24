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

# manifest_parse_repo <repos.txt line>
# Sets REPO_URL, REPO_DEST, REPO_BRANCH and REPO_IS_PRIVATE. Trailing fields
# are the optional branch and the PRIVATE_REPO marker, in either order.
manifest_parse_repo() {
    local extra token
    read -r REPO_URL REPO_DEST extra <<< "$1"
    REPO_BRANCH=""
    REPO_IS_PRIVATE=false
    for token in ${extra}; do
        if [[ "${token}" == "PRIVATE_REPO" ]]; then
            REPO_IS_PRIVATE=true
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
