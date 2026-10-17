#!/usr/bin/env bash

# Source this file before running host setup or Docker builds, from the repo
# root (required — manifest/ is located relative to the current directory,
# not this script's path, since BASH_SOURCE isn't reliably set when sourced
# under zsh):
#
#   cd ~/provision_dome
#   nano manifest/user.txt   # set DOCKERHUB_USERNAME and DOME_USER
#   source scripts/dome-config.sh

_MANIFEST_DIR="$(pwd)/manifest"
if [[ ! -f "${_MANIFEST_DIR}/config.txt" ]]; then
    echo "ERROR: ${_MANIFEST_DIR}/config.txt not found." >&2
    echo "Source this file from the repo root: cd ~/provision_dome && source scripts/dome-config.sh" >&2
    return 1
fi

_require_field() {
    local file="$1" key="$2"
    local val
    val=$(grep "^${key}=" "$file" | cut -d= -f2)
    if [[ -z "$val" ]]; then
        echo "ERROR: '${key}' not set in ${file}" >&2
        return 1
    fi
    echo "$val"
}

_DOME_USER_DEFAULT=$(_require_field "${_MANIFEST_DIR}/config.txt" DOME_USER) || return 1
_ROS_DISTRO=$(_require_field "${_MANIFEST_DIR}/config.txt" ROS_DISTRO) || return 1
_DOCKERHUB_USERNAME=$(grep '^DOCKERHUB_USERNAME=' "${_MANIFEST_DIR}/user.txt" 2>/dev/null | cut -d= -f2)
_DOME_USER=$(grep '^DOME_USER=' "${_MANIFEST_DIR}/user.txt" 2>/dev/null | cut -d= -f2)

# User created or configured on the Pi host and inside the Docker image.
export DOME_USER="${DOME_USER:-${_DOME_USER:-${_DOME_USER_DEFAULT}}}"

# Optional password for DOME_USER. Leave empty to preserve an existing host
# password from cloud-init or Raspberry Pi Imager. If used for Docker image
# builds, the value is baked into the image and may be visible in local image
# metadata or build logs. Do not commit real passwords.
export DOME_PASSWORD="${DOME_PASSWORD:-}"

# Which named repo set a Docker build clones (F17). Same precedence the
# bare-metal scripts use: environment > manifest/user.txt > manifest/config.txt.
_REPOS_CONFIG_DEFAULT=$(_require_field "${_MANIFEST_DIR}/config.txt" REPOS_CONFIG) || return 1
_REPOS_CONFIG=$(grep '^[[:space:]]*REPOS_CONFIG=' "${_MANIFEST_DIR}/user.txt" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')
export REPOS_CONFIG="${REPOS_CONFIG:-${_REPOS_CONFIG:-${_REPOS_CONFIG_DEFAULT}}}"

# Docker Hub image names with ROS distro tags from manifest/config.txt.
# Set DOCKERHUB_USERNAME in manifest/user.txt.
export DOME_BASE_IMAGE="${DOME_BASE_IMAGE:-docker.io/${_DOCKERHUB_USERNAME}/dome-base:${_ROS_DISTRO}}"
export DOME_IMAGE="${DOME_IMAGE:-docker.io/${_DOCKERHUB_USERNAME}/dome-docker:dome-${_ROS_DISTRO}}"

# Repository URL for cloning this public setup repo onto a fresh Pi.
export DOME_DOCKER_REPO_URL="${DOME_DOCKER_REPO_URL:-https://github.com/Boston-Robot-Hackers/provision_dome.git}"

# SSH key settings used during Docker builds.
export DOME_SSH_KEY="${DOME_SSH_KEY:-${HOME}/.ssh/id_ed25519}"
export DOME_SSH_KEY_COMMENT="${DOME_SSH_KEY_COMMENT:-${USER}@$(hostname -s)}"
