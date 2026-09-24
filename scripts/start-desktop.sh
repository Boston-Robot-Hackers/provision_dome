#!/usr/bin/env bash
# Start the optional noVNC desktop for a cloud dev host (F07, DOME_DESKTOP=vnc).
# TigerVNC serves display :1 on loopback only; websockify/noVNC bridges it to
# 127.0.0.1:6080. Reach it from the Mac with: ssh -L 6080:localhost:6080 ...
# Both listeners are loopback-only by design — nothing here may bind a public
# address, so raw VNC on 5901 is never exposed.
set -euo pipefail

if ! command -v vncserver >/dev/null 2>&1; then
    echo "ERROR: vncserver not found. Install the desktop with DOME_DESKTOP=vnc" >&2
    echo "       (set it in manifest/user.txt and rerun bare-metal-base.sh)." >&2
    exit 1
fi

if ! command -v websockify >/dev/null 2>&1; then
    echo "ERROR: websockify not found. Install the desktop with DOME_DESKTOP=vnc" >&2
    echo "       (set it in manifest/user.txt and rerun bare-metal-base.sh)." >&2
    exit 1
fi

NOVNC_WEB="/usr/share/novnc"

echo "==> Starting TigerVNC on :1 (loopback only)"
vncserver -kill :1 >/dev/null 2>&1 || true
vncserver :1 -localhost yes

echo "==> Starting websockify/noVNC on 127.0.0.1:6080 -> localhost:5901"
websockify --web="${NOVNC_WEB}" 127.0.0.1:6080 localhost:5901
