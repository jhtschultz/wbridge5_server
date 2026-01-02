#!/bin/bash
set -euo pipefail

export DISPLAY="${DISPLAY:-:0}"
export NOVNC_LISTEN="${NOVNC_LISTEN:-6080}"
export TTYD_PORT="${TTYD_PORT:-7681}"
export WINEPREFIX="${WINEPREFIX:-/opt/wbridge5/wineprefix}"
export WINEARCH="${WINEARCH:-win64}"
export PATH="/usr/games:${PATH}"

WB5_EXE="${WINEPREFIX}/drive_c/Wbridge5/Wbridge5.exe"

if [[ ! -f "$WB5_EXE" ]]; then
    echo "WBridge5 executable not found at ${WB5_EXE}" >&2
    exit 1
fi

trap 'kill 0' EXIT

mkdir -p /var/log/nginx

# Use a resolution that fits WBridge5 well
Xvfb "$DISPLAY" -screen 0 1024x768x24 &
sleep 2

fluxbox &
sleep 1

wbridge_start() {
    # Use wine64 to avoid 32-bit loader (gVisor forbids i386 binaries)
    env WINEPREFIX="$WINEPREFIX" WINEARCH="$WINEARCH" wine64 start /unix "$WB5_EXE"
}

wbridge_start &

# Wait for WBridge5 window to appear, then maximize it
(
    sleep 5
    # Try to find and maximize the WBridge5 window
    for i in {1..10}; do
        if wmctrl -l | grep -i "wbridge5\|bridge"; then
            wmctrl -r "Wbridge5" -b add,maximized_vert,maximized_horz 2>/dev/null || \
            wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
            break
        fi
        sleep 1
    done
) &

x11vnc -display "$DISPLAY" -localhost -shared -forever -rfbport 5900 -nopw &

# Use standalone websockify (Debian's novnc_proxy is incompatible)
websockify "$NOVNC_LISTEN" localhost:5900 &

ttyd -p "$TTYD_PORT" -i 0.0.0.0 --check-origin bash &

nginx -g "daemon off;"
