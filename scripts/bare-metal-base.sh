#!/usr/bin/env bash
# Bare-metal base setup: installs ROS, apt/pip/curl packages from manifest.
# Mirrors Dockerfile.base. Run as root on a fresh Ubuntu 24.04 Pi.
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: run as root: sudo scripts/bare-metal-base.sh" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_DIR="${SCRIPT_DIR}/../manifest"

source "${MANIFEST_DIR}/lib.sh"

ROS_DISTRO=$(manifest_config ROS_DISTRO "${MANIFEST_DIR}/config.txt")
UBUNTU_CODENAME=$(manifest_config UBUNTU_CODENAME "${MANIFEST_DIR}/config.txt")
_DOME_USER_DEFAULT=$(manifest_config DOME_USER "${MANIFEST_DIR}/config.txt")
_DOME_USER_FILE=$(grep '^[[:space:]]*DOME_USER=' "${MANIFEST_DIR}/user.txt" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]' || true)
# Priority: env var > user.txt > config.txt default
DOME_USER="${DOME_USER:-${_DOME_USER_FILE:-${_DOME_USER_DEFAULT}}}"
_DOME_TARGET_DEFAULT=$(manifest_config DOME_TARGET "${MANIFEST_DIR}/config.txt")
_DOME_TARGET_FILE=$(grep '^[[:space:]]*DOME_TARGET=' "${MANIFEST_DIR}/user.txt" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]' || true)
DOME_TARGET="${DOME_TARGET:-${_DOME_TARGET_FILE:-${_DOME_TARGET_DEFAULT}}}"
_SWAP_SIZE_MB_DEFAULT=$(manifest_config SWAP_SIZE_MB "${MANIFEST_DIR}/config.txt")
_SWAP_SIZE_MB_FILE=$(grep '^[[:space:]]*SWAP_SIZE_MB=' "${MANIFEST_DIR}/user.txt" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]' || true)
SWAP_SIZE_MB="${SWAP_SIZE_MB:-${_SWAP_SIZE_MB_FILE:-${_SWAP_SIZE_MB_DEFAULT}}}"
_DOME_DESKTOP_DEFAULT=$(manifest_config DOME_DESKTOP "${MANIFEST_DIR}/config.txt")
_DOME_DESKTOP_FILE=$(grep '^[[:space:]]*DOME_DESKTOP=' "${MANIFEST_DIR}/user.txt" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]' || true)
DOME_DESKTOP="${DOME_DESKTOP:-${_DOME_DESKTOP_FILE:-${_DOME_DESKTOP_DEFAULT}}}"

echo "==> Starting bare-metal-base.sh"
echo "==> ROS_DISTRO=${ROS_DISTRO}  UBUNTU_CODENAME=${UBUNTU_CODENAME}  DOME_TARGET=${DOME_TARGET}  SWAP_SIZE_MB=${SWAP_SIZE_MB}"
echo ""

# --- Swapfile (pi and cloud) ---
echo "==> [1/9] Setting up swapfile"
if [[ "${DOME_TARGET}" == "pi" || "${DOME_TARGET}" == "cloud" ]]; then
    if [[ "${SWAP_SIZE_MB}" -eq 0 ]]; then
        echo "  SWAP_SIZE_MB=0, skipping"
    elif swapon --show=NAME --noheadings 2>/dev/null | grep -qx "/swapfile"; then
        echo "  /swapfile already active, skipping"
    else
        fallocate -l "${SWAP_SIZE_MB}M" /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        grep -qx '/swapfile none swap sw 0 0' /etc/fstab \
            || echo '/swapfile none swap sw 0 0' >> /etc/fstab
        echo "  /swapfile created (${SWAP_SIZE_MB}MB) and activated"
    fi
else
    echo "  DOME_TARGET=${DOME_TARGET}, skipping (swap is for pi and cloud only)"
fi
echo "==> [1/9] Swapfile done"

# --- Locale ---
echo ""
echo "==> [2/9] Setting locale"
apt-get install -y locales
locale-gen en_US en_US.UTF-8
update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
export LANG=en_US.UTF-8
echo "==> [2/9] Locale done"

# --- ROS 2 apt repository ---
echo ""
echo "==> [3/9] Adding ROS 2 apt repository"
apt-get install -y software-properties-common curl gnupg apt-transport-https
echo "  adding universe..."
add-apt-repository -y universe
echo "  fetching ROS signing key..."
curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
    -o /usr/share/keyrings/ros-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] \
http://packages.ros.org/ros2/ubuntu ${UBUNTU_CODENAME} main" \
    > /etc/apt/sources.list.d/ros2.list
echo "  running apt-get update..."
apt-get update
echo "==> [3/9] ROS 2 repo done"

# --- ROS base install ---
echo ""
echo "==> [4/9] Installing ros-${ROS_DISTRO}-ros-base (slow)"
apt-get install -y "ros-${ROS_DISTRO}-ros-base"
echo "==> [4/9] ROS base done"

# --- apt packages from manifest/packages.txt ---
echo ""
echo "==> [5/9] Installing apt packages from manifest/packages.txt"
APT_PKGS=$(awk '/^\[apt\]/{f=1;next} /^\[/{f=0} f && /^[^#[:space:]]/' "${MANIFEST_DIR}/packages.txt")
if [[ "${DOME_TARGET}" == "pi" ]]; then
    APT_PKGS="${APT_PKGS}
$(awk '/^\[apt-pi\]/{f=1;next} /^\[/{f=0} f && /^[^#[:space:]]/' "${MANIFEST_DIR}/packages.txt")"
fi
if [[ "${DOME_DESKTOP}" == "vnc" ]]; then
    echo "  DOME_DESKTOP=vnc, adding [apt-desktop] packages"
    APT_PKGS="${APT_PKGS}
$(awk '/^\[apt-desktop\]/{f=1;next} /^\[/{f=0} f && /^[^#[:space:]]/' "${MANIFEST_DIR}/packages.txt")"
else
    echo "  DOME_DESKTOP=${DOME_DESKTOP}, skipping [apt-desktop] packages"
fi
echo "  packages: $(echo "$APT_PKGS" | wc -l) items"
echo "$APT_PKGS" | xargs apt-get install -y --no-install-recommends
echo "==> [5/9] apt packages done"

# --- ROS packages from manifest/packages.txt ---
echo ""
echo "==> [6/9] Installing ROS packages from manifest/packages.txt"
ROS_PKGS=$(awk -v d="${ROS_DISTRO}" \
    '/^\[ros\]/{f=1;next} /^\[/{f=0} f && /^[^#[:space:]]/{print "ros-"d"-"$0}' \
    "${MANIFEST_DIR}/packages.txt")
echo "  packages: $(echo "$ROS_PKGS" | wc -l) items"
echo "$ROS_PKGS" | xargs apt-get install -y --no-install-recommends
echo "==> [6/9] ROS packages done"

# --- curl-installed tools from manifest/tools.txt ---
echo ""
echo "==> [7/9] Installing curl tools from manifest/tools.txt"
for sect in $(manifest_sections "${MANIFEST_DIR}/tools.txt"); do
    method=$(manifest_require "$sect" method "${MANIFEST_DIR}/tools.txt")
    url=$(manifest_require "$sect" url "${MANIFEST_DIR}/tools.txt")
    args=$(manifest_field "$sect" args "${MANIFEST_DIR}/tools.txt")
    run_as_user=$(manifest_field "$sect" run_as_user "${MANIFEST_DIR}/tools.txt")
    echo "  installing [$sect] via $method..."
    case "$method" in
        curl-sh) shell="sh" ;;
        curl-bash) shell="bash" ;;
        *)
            echo "ERROR: unknown tool method '$method' for [$sect]" >&2
            exit 1
            ;;
    esac
    if [[ "$run_as_user" == "true" ]]; then
        sudo -u "${DOME_USER}" bash -c "curl -LSfs '$url' | $shell -s -- $args"
    else
        curl -LSfs "$url" | "$shell" -s -- $args
    fi
done
echo "==> [7/9] curl tools done"

# --- third-party apt repos from manifest/apt-repos.txt ---
echo ""
echo "==> [8/9] Adding third-party apt repositories from manifest/apt-repos.txt"
arch=$(dpkg --print-architecture)
for sect in $(manifest_sections "${MANIFEST_DIR}/apt-repos.txt"); do
    echo "  setting up [$sect]..."
    key_url=$(manifest_require "$sect" key_url "${MANIFEST_DIR}/apt-repos.txt")
    key_file=$(manifest_require "$sect" key_file "${MANIFEST_DIR}/apt-repos.txt")
    key_dearmor=$(manifest_require "$sect" key_dearmor "${MANIFEST_DIR}/apt-repos.txt")
    list=$(manifest_require "$sect" list "${MANIFEST_DIR}/apt-repos.txt")
    list="${list//\{arch\}/$arch}"
    list="${list//\{key_file\}/$key_file}"
    if [[ "$key_dearmor" == "yes" ]]; then
        curl -sLf --retry 3 --tlsv1.2 --proto "=https" "$key_url" | gpg --dearmor -o "$key_file"
    else
        curl -fsSL --retry 3 --tlsv1.2 --proto "=https" "$key_url" -o "$key_file"
        chmod go+r "$key_file"
    fi
    echo "$list" > "/etc/apt/sources.list.d/${sect}.list"
    echo "  [$sect] repo added"
done
echo "  running apt-get update..."
apt-get update
echo "  installing packages from apt-repos..."
awk '/^\[/{next} /^packages[[:space:]]*=/{sub(/^packages[[:space:]]*=[[:space:]]*/,""); print}' \
    "${MANIFEST_DIR}/apt-repos.txt" \
    | tr ' ' '\n' | grep -v '^$' | xargs apt-get install -y
echo "==> [8/9] third-party repos done"

# --- pip packages from manifest/pip.txt ---
echo ""
echo "==> [9/9] Installing pip packages from manifest/pip.txt"
PIP_PKGS=$(awk '/^\[pip\]/{f=1;next} /^\[/{f=0} f && /^[^#[:space:]]/' "${MANIFEST_DIR}/pip.txt")
if [[ "${DOME_TARGET}" == "pi" ]]; then
    PIP_PKGS="${PIP_PKGS}
$(awk '/^\[pip-pi\]/{f=1;next} /^\[/{f=0} f && /^[^#[:space:]]/' "${MANIFEST_DIR}/pip.txt")"
fi
if [[ -n "$(echo "$PIP_PKGS" | tr -d '[:space:]')" ]]; then
    echo "  packages: $(echo "$PIP_PKGS" | grep -c '^[^[:space:]]')"
    echo "$PIP_PKGS" | xargs pip3 install --break-system-packages --ignore-installed
fi
echo "==> [9/9] pip packages done"

# --- rosdep ---
echo ""
echo "==> Initialising rosdep"
rosdep init || true
echo "==> rosdep init done"

apt-get clean
rm -rf /var/lib/apt/lists/*

echo ""
echo "==> bare-metal-base.sh complete. Run bare-metal-build.sh next."
