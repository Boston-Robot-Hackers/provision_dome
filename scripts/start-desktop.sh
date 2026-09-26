#!/usr/bin/env bash
# Serve the Dome VNC desktop (F07/F14). ONE TigerVNC session on :1, bridged to
# noVNC by websockify. The bind address depends on DOME_VNC_ACCESS:
#   public  -> 0.0.0.0:48210   reachable by URL; a VNC password is required, and
#              the OCI security list + dome-vnc-firewall.service open the port.
#   tunnel  -> 127.0.0.1:6080  loopback only; reach it with
#              `ssh -L 6080:localhost:6080 <user>@<host>` then http://localhost:6080
#   none    -> refuse (no remote desktop configured)
# No x11vnc, no second mirror: a single controllable session (F14). Runs in the
# foreground (websockify), so it is driven by dome-vnc.service on the box and
# blocks when run by hand.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_DIR="${SCRIPT_DIR}/../manifest"

# Resolve DOME_VNC_ACCESS: env > user.txt > config.txt
_ACCESS_DEFAULT=$(grep '^DOME_VNC_ACCESS=' "${MANIFEST_DIR}/config.txt" | cut -d= -f2 | tr -d '[:space:]')
_ACCESS_FILE=$(grep '^[[:space:]]*DOME_VNC_ACCESS=' "${MANIFEST_DIR}/user.txt" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]' || true)
DOME_VNC_ACCESS="${DOME_VNC_ACCESS:-${_ACCESS_FILE:-${_ACCESS_DEFAULT}}}"

PUBLIC_PORT=48210
TUNNEL_PORT=6080
NOVNC_WEB="/usr/share/novnc"

case "${DOME_VNC_ACCESS}" in
    public) BIND="0.0.0.0:${PUBLIC_PORT}" ;;
    tunnel) BIND="127.0.0.1:${TUNNEL_PORT}" ;;
    none|"")
        echo "DOME_VNC_ACCESS=none: no remote desktop configured." >&2
        echo "Set DOME_VNC_ACCESS=public or =tunnel in manifest/user.txt." >&2
        exit 1 ;;
    *)
        echo "ERROR: DOME_VNC_ACCESS='${DOME_VNC_ACCESS}' invalid (public|tunnel|none)." >&2
        exit 1 ;;
esac

for bin in vncserver websockify; do
    command -v "$bin" >/dev/null 2>&1 || {
        echo "ERROR: $bin not found. Install the desktop: set DOME_DESKTOP=vnc in" >&2
        echo "       manifest/user.txt and rerun scripts/bare-metal-base.sh." >&2
        exit 1; }
done

# Public mode must be password-protected — never expose a passwordless desktop.
if [[ "${DOME_VNC_ACCESS}" == "public" && ! -s "${HOME}/.vnc/passwd" ]]; then
    echo "ERROR: public mode needs a VNC password, but ~/.vnc/passwd is missing." >&2
    echo "       Run once:  vncpasswd   (then restart dome-vnc.service)." >&2
    exit 1
fi

# xfce startup (idempotent)
mkdir -p "${HOME}/.vnc"
if [[ ! -x "${HOME}/.vnc/xstartup" ]]; then
    cat > "${HOME}/.vnc/xstartup" <<'XS'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec startxfce4
XS
    chmod +x "${HOME}/.vnc/xstartup"
fi

echo "==> DOME_VNC_ACCESS=${DOME_VNC_ACCESS}: TigerVNC :1 (loopback) -> websockify ${BIND}"
vncserver -kill :1 >/dev/null 2>&1 || true
vncserver :1 -localhost yes -geometry 1440x900

# TLS in public mode only (F15.5). Without it noVNC is served over ws://, so
# screen contents and keystrokes cross the internet in the clear and the VNC
# challenge-response can be captured and cracked offline. Tunnel mode is
# already inside an SSH channel and gains nothing from a second wrapper.
# Self-signed is enough here: it encrypts the session and gives the origin an
# identity. The browser will warn on first visit — that is expected, and
# cloud-howto.md says so.
TLS_ARGS=()
if [[ "${DOME_VNC_ACCESS}" == "public" ]]; then
    CERT="${HOME}/.vnc/novnc.pem"
    if [[ ! -f "${CERT}" ]]; then
        echo "==> generating self-signed certificate ${CERT}"
        mkdir -p "${HOME}/.vnc"
        openssl req -x509 -nodes -newkey rsa:2048 -days 825 \
            -keyout "${CERT}" -out "${CERT}" -subj "/CN=dome-cloud" 2>/dev/null \
            || { echo "ERROR: could not generate ${CERT}" >&2; exit 1; }
        chmod 600 "${CERT}"
    fi
    TLS_ARGS=(--cert="${CERT}")
fi

echo "==> websockify ${BIND} -> localhost:5901 (noVNC web root ${NOVNC_WEB})"
exec websockify "${TLS_ARGS[@]}" --web="${NOVNC_WEB}" "${BIND}" localhost:5901
