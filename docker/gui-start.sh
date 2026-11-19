#!/bin/bash
# GUI supervisor (PID 1 behind tini, started by entrypoint.sh as root after
# prepare_user): dbus, xrdp, and one persistent XFCE desktop on Xvnc :1 for
# noVNC. Restarts what dies; stops everything on SIGTERM.
set -u
# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"

DISPLAY_NUM=1
VNC_PORT=$((5900 + DISPLAY_NUM))
NOVNC_PORT=6080
GEOMETRY="${KALI_GEOMETRY:-1440x900}"
VNC_PASSWORD_CUSTOM=

# TigerVNC rejects passwords under 6 characters; only the first 8 count.
# The file is written by kali (umask 077, temp file, mv replaces a planted
# symlink instead of following it): root never writes inside the home volume.
setup_vnc_password() {
    local pw="${KALI_VNC_PASSWORD:-$KALI_DEFAULT_VNC_PASSWORD}"
    [ -n "${KALI_VNC_PASSWORD:-}" ] && VNC_PASSWORD_CUSTOM=1
    unset KALI_VNC_PASSWORD
    if [ "${#pw}" -lt 6 ]; then
        log "KALI_VNC_PASSWORD is shorter than 6 characters; using the default."
        pw=$KALI_DEFAULT_VNC_PASSWORD
        VNC_PASSWORD_CUSTOM=
    fi
    # shellcheck disable=SC2016  # $HOME must expand in the kali shell, not here
    printf '%s\n' "$pw" | as_kali sh -c '
        umask 077
        mkdir -p "$HOME/.vnc" &&
        tigervncpasswd -f > "$HOME/.vnc/passwd.new" &&
        mv -f "$HOME/.vnc/passwd.new" "$HOME/.vnc/passwd"' \
        || log "Could not write the VNC password file; noVNC login will not work."
}

start_dbus() {
    rm -f /run/dbus/pid
    mkdir -p /run/dbus
    dbus-daemon --system --fork
}

start_xrdp() {
    pgrep -x xrdp-sesman >/dev/null || { rm -f /var/run/xrdp/xrdp-sesman.pid; /usr/sbin/xrdp-sesman; }
    pgrep -x xrdp >/dev/null || { rm -f /var/run/xrdp/xrdp.pid; /usr/sbin/xrdp; }
}

start_xfce() {
    as_kali env DISPLAY=":${DISPLAY_NUM}" startxfce4 >/dev/null 2>&1 &
    XFCE_PID=$!
}

start_vnc_desktop() {
    rm -f "/tmp/.X${DISPLAY_NUM}-lock" "/tmp/.X11-unix/X${DISPLAY_NUM}"
    as_kali Xvnc ":${DISPLAY_NUM}" -geometry "$GEOMETRY" -depth 24 \
        -rfbport "$VNC_PORT" -rfbauth "$KALI_HOME/.vnc/passwd" \
        -SecurityTypes VncAuth -localhost >/dev/null 2>&1 &
    XVNC_PID=$!

    for _ in $(seq 1 50); do
        [ -S "/tmp/.X11-unix/X${DISPLAY_NUM}" ] && break
        sleep 0.2
    done
    start_xfce
}

start_websockify() {
    as_kali websockify --web /usr/share/novnc "$NOVNC_PORT" "localhost:${VNC_PORT}" >/dev/null 2>&1 &
    WEBSOCKIFY_PID=$!
}

alive() { [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null; }

stop_all() {
    log "Stopping."
    local pid
    for pid in "${WEBSOCKIFY_PID:-}" "${XFCE_PID:-}" "${XVNC_PID:-}"; do
        if alive "$pid"; then kill "$pid" 2>/dev/null; fi
    done
    pkill -x xrdp 2>/dev/null
    pkill -x xrdp-sesman 2>/dev/null
    exit 0
}

banner() {
    echo "=================================================="
    echo "Kali desktop is running (user: $KALI_USER)"
    echo "  RDP    port 3389"
    echo "  noVNC  port 6080, open /vnc.html"
    if [ -z "${KALI_PASSWORD_CUSTOM:-}" ]; then
        echo "  Login password is the default; set KALI_PASSWORD to change it."
    fi
    if [ -z "$VNC_PASSWORD_CUSTOM" ]; then
        echo "  VNC password is the default; set KALI_VNC_PASSWORD to change it."
    fi
    echo "=================================================="
}

trap stop_all TERM INT
setup_vnc_password
start_dbus
start_xrdp
start_vnc_desktop
start_websockify
banner

while true; do
    sleep 5 &
    wait $!
    start_xrdp
    if ! alive "${XVNC_PID:-}"; then
        log "Xvnc stopped, restarting."
        if alive "${XFCE_PID:-}"; then kill "$XFCE_PID" 2>/dev/null; fi
        start_vnc_desktop
    elif ! alive "${XFCE_PID:-}"; then
        log "XFCE (noVNC desktop) stopped, restarting."
        start_xfce
    fi
    alive "${WEBSOCKIFY_PID:-}" || { log "websockify stopped, restarting."; start_websockify; }
done
