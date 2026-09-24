#!/usr/bin/env bash
# Host provisioning script: installs Docker, creates the robot user, sets up
# udev/netplan/boot firmware, and builds the ReSpeaker dtoverlay. Run as root.
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo scripts/host-setup.sh" >&2
  exit 1
fi

_DOME_USER_DEFAULT=$(grep '^DOME_USER=' manifest/config.txt | cut -d= -f2)
_DOME_USER_FILE=$(grep '^[[:space:]]*DOME_USER=' manifest/user.txt 2>/dev/null | cut -d= -f2 | tr -d '[:space:]' || true)
USERNAME="${DOME_USER:-${_DOME_USER_FILE:-${_DOME_USER_DEFAULT:-robot}}}"
PASSWORD="${DOME_PASSWORD-}"
DOCKER_APT_HOST="download.docker.com"

_DOME_TARGET_DEFAULT=$(grep '^DOME_TARGET=' manifest/config.txt | cut -d= -f2)
_DOME_TARGET_FILE=$(grep '^[[:space:]]*DOME_TARGET=' manifest/user.txt 2>/dev/null | cut -d= -f2 | tr -d '[:space:]' || true)
DOME_TARGET="${DOME_TARGET:-${_DOME_TARGET_FILE:-${_DOME_TARGET_DEFAULT:-pi}}}"

_DOME_MODE_DEFAULT=$(grep '^DOME_MODE=' manifest/config.txt | cut -d= -f2)
_DOME_MODE_FILE=$(grep '^[[:space:]]*DOME_MODE=' manifest/user.txt 2>/dev/null | cut -d= -f2 | tr -d '[:space:]' || true)
DOME_MODE="${DOME_MODE:-${_DOME_MODE_FILE:-${_DOME_MODE_DEFAULT:-native}}}"

default_network_interface() {
  ip route get 1.1.1.1 | awk '{for (i = 1; i <= NF; i++) if ($i == "dev") {print $(i + 1); exit}}'
}

check_network_ready() {
  if ! ip route get 1.1.1.1 >/dev/null 2>&1; then
    echo "Network is not ready: no route to the internet." >&2
    exit 1
  fi
  if [[ "${DOME_MODE}" == "docker" ]] && ! getent ahostsv4 "${DOCKER_APT_HOST}" >/dev/null 2>&1; then
    echo "DNS not resolving ${DOCKER_APT_HOST}. Check DNS config and rerun." >&2
    exit 1
  fi
}

apt-get update
apt-get install -y \
  ca-certificates \
  curl \
  git \
  gnupg \
  make \
  net-tools \
  openssh-server \
  ripgrep \
  rsync \
  sudo \
  udev \
  usbutils \
  v4l-utils

if ! id "${USERNAME}" >/dev/null 2>&1; then
  adduser --gecos "" "${USERNAME}"
fi

if [[ -n "${PASSWORD}" ]]; then
  echo "${USERNAME}:${PASSWORD}" | chpasswd
fi
usermod -aG sudo "${USERNAME}"

check_network_ready

if [[ "${DOME_MODE}" == "docker" ]]; then
  install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
    curl -4 -fsSL "https://${DOCKER_APT_HOST}/linux/ubuntu/gpg" -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
  fi

  . /etc/os-release
  cat >/etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://${DOCKER_APT_HOST}/linux/ubuntu ${VERSION_CODENAME} stable
EOF

  apt-get -o Acquire::ForceIPv4=true update
  apt-get -o Acquire::ForceIPv4=true install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  systemctl enable docker
  systemctl start docker
  usermod -aG docker "${USERNAME}"
else
  echo "DOME_MODE=native — skipping Docker install."
fi

install -m 0755 -d /etc/udev/rules.d
_udev_installed=0
if [[ -d ./host-file-templates/etc/udev/rules.d ]]; then
  install -m 0644 ./host-file-templates/etc/udev/rules.d/*.rules /etc/udev/rules.d/
  _udev_installed=1
fi
if [[ -d ./host-files/etc/udev/rules.d ]]; then
  install -m 0644 ./host-files/etc/udev/rules.d/*.rules /etc/udev/rules.d/
  _udev_installed=1
fi
if [[ "${_udev_installed}" -eq 1 ]]; then
  udevadm control --reload-rules
  udevadm trigger
else
  echo "No udev rules found in host-file-templates or host-files; skipping."
fi

if [[ -d ./host-files/etc/netplan ]]; then
  install -m 0755 -d /etc/netplan
  install -m 0600 ./host-files/etc/netplan/*.yaml /etc/netplan/
  echo "Netplan files copied. Review them, then run: sudo netplan apply"
else
  echo "No ./host-files/etc/netplan directory found; skipping netplan restore."
fi

if [[ "${RESTORE_BOOT_FIRMWARE:-0}" == "1" ]]; then
  if [[ -d ./host-files/boot/firmware ]]; then
    install -m 0755 -d /boot/firmware
    for boot_file in config.txt cmdline.txt; do
      if [[ -f "./host-files/boot/firmware/${boot_file}" ]]; then
        if [[ -f "/boot/firmware/${boot_file}" ]]; then
          cp "/boot/firmware/${boot_file}" "/boot/firmware/${boot_file}.pre-dome-docker"
        fi
        install -m 0644 "./host-files/boot/firmware/${boot_file}" "/boot/firmware/${boot_file}"
      fi
    done
    echo "Boot firmware files copied. Reboot the Pi for /boot/firmware changes to apply."
  else
    echo "RESTORE_BOOT_FIRMWARE=1 set, but no ./host-files/boot/firmware directory found."
  fi
else
  echo "Skipping /boot/firmware restore. Set RESTORE_BOOT_FIRMWARE=1 to copy reviewed boot files."
fi

if [[ "${DOME_TARGET}" == "pi" ]]; then
  apt-get install -y flex bison libssl-dev bc libncurses5-dev libncursesw5-dev

  OVERLAY_DTBO=/boot/firmware/overlays/respeaker-2mic-v2_0.dtbo
  if [[ ! -f "${OVERLAY_DTBO}" ]]; then
    SEEED_DIR="$(mktemp -d)"
    git clone https://github.com/Seeed-Studio/seeed-linux-dtoverlays.git "${SEEED_DIR}"
    make -C "${SEEED_DIR}" overlays/rpi/respeaker-2mic-v2_0-overlay.dtbo
    install -m 0644 "${SEEED_DIR}/overlays/rpi/respeaker-2mic-v2_0-overlay.dtbo" "${OVERLAY_DTBO}"
    rm -rf "${SEEED_DIR}"
    if ! grep -q 'dtoverlay=respeaker-2mic-v2_0' /boot/firmware/config.txt; then
      echo "dtoverlay=respeaker-2mic-v2_0" >> /boot/firmware/config.txt
    fi
    echo "ReSpeaker overlay installed. Reboot required."
  else
    echo "ReSpeaker overlay already present; skipping."
  fi
else
  echo "DOME_TARGET=${DOME_TARGET} — skipping ReSpeaker overlay build (Pi-only, needs /boot/firmware)."
fi

if [[ "${DOME_MODE}" == "docker" ]]; then
  DOME_DIR="/home/${USERNAME}/provision_dome"
  mkdir -p \
    "${DOME_DIR}/runtime-data/ros" \
    "${DOME_DIR}/runtime-data/control" \
    "${DOME_DIR}/runtime-data/dome"
  chown -R "${USERNAME}:${USERNAME}" "${DOME_DIR}/runtime-data"

  # Generate dome.env (plain KEY=VALUE) for use by dome.service EnvironmentFile.
  MANIFEST_DIR="${DOME_DIR}/manifest"
  DOCKERHUB_USERNAME=$(grep '^DOCKERHUB_USERNAME=' "${MANIFEST_DIR}/user.txt" | cut -d= -f2)
  ROS_DISTRO_VAL=$(grep '^ROS_DISTRO=' "${MANIFEST_DIR}/config.txt" | cut -d= -f2)
  cat > "${DOME_DIR}/dome.env" <<EOF
DOME_USER=${USERNAME}
DOCKERHUB_USERNAME=${DOCKERHUB_USERNAME}
DOME_BASE_IMAGE=docker.io/${DOCKERHUB_USERNAME}/dome-base:${ROS_DISTRO_VAL}
DOME_IMAGE=docker.io/${DOCKERHUB_USERNAME}/dome-docker:dome-${ROS_DISTRO_VAL}
ROS_DISTRO=${ROS_DISTRO_VAL}
EOF
  chmod 0600 "${DOME_DIR}/dome.env"
  chown "${USERNAME}:${USERNAME}" "${DOME_DIR}/dome.env"

  SERVICE_SRC="${DOME_DIR}/host-file-templates/etc/systemd/system/dome.service"
  sed "s/@@DOME_USER@@/${USERNAME}/g" "${SERVICE_SRC}" > /etc/systemd/system/dome.service
  chmod 0644 /etc/systemd/system/dome.service
  systemctl daemon-reload
  systemctl enable dome
  echo "dome.service installed and enabled."
else
  echo "DOME_MODE=native — skipping dome.env/dome.service setup."
fi

if [[ "${DOME_MODE}" == "docker" ]]; then
  echo "Host setup complete. Log out and back in for docker group membership to apply."
else
  echo "Host setup complete."
fi
echo ""
echo "Reconnect using one of these IPs if dome.local (mDNS) doesn't resolve:"
ip -4 -o addr show scope global | awk '{print "  " $2 ": " $4}'
