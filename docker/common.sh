#!/bin/bash
# Shared helpers, sourced by entrypoint.sh and gui-start.sh.

KALI_USER=kali
KALI_HOME=/home/kali

log() { echo "[kali] $*"; }

# Replace the current process with a command running as kali (setpriv, no gosu).
as_kali_exec() {
    exec setpriv --reuid="$KALI_USER" --regid="$KALI_USER" --init-groups \
        env HOME="$KALI_HOME" USER="$KALI_USER" LOGNAME="$KALI_USER" \
        SHELL="$(getent passwd "$KALI_USER" | cut -d: -f7)" \
        "$@"
}

# Same, in a subshell, for background jobs and one-off commands.
as_kali() { ( as_kali_exec "$@" ); }

# shellcheck disable=SC2034  # used by gui-start.sh, which sources this file
KALI_DEFAULT_VNC_PASSWORD=kalikali

# PUID/PGID remap. Ids are changed in /etc/passwd and /etc/group directly:
# usermod -u would chown every file under the home owned by the old uid,
# including the work bind mount. The home is chowned by find, which does not
# follow symlinks and prunes the work mount, and only when its owner differs.
remap_user() {
    local puid="${PUID:-1000}" pgid="${PGID:-1000}"
    if ! [[ $puid =~ ^[0-9]+$ && $pgid =~ ^[0-9]+$ ]] || [ "$puid" -eq 0 ] || [ "$pgid" -eq 0 ]; then
        log "PUID/PGID must be numbers other than 0; keeping the current ids."
        return 0
    fi
    if [ "$(id -g "$KALI_USER")" != "$pgid" ]; then groupmod -o -g "$pgid" "$KALI_USER"; fi
    if [ "$(id -u "$KALI_USER")" != "$puid" ] || [ "$(id -g "$KALI_USER")" != "$pgid" ]; then
        sed -i -E "s/^($KALI_USER:[^:]*:)[0-9]+:[0-9]+:/\\1$puid:$pgid:/" /etc/passwd
    fi
    if [ "$(stat -c %u "$KALI_HOME")" != "$puid" ] || [ "$(stat -c %g "$KALI_HOME")" != "$pgid" ]; then
        find "$KALI_HOME" -path "$KALI_HOME/work" -prune -o -exec chown -h "$puid:$pgid" {} +
    fi
}

# A bind source that Docker created is root-owned: fix that one directory only
# (never through a symlink).
fix_work_dir() {
    local dir="$KALI_HOME/work"
    if [ -d "$dir" ] && [ ! -L "$dir" ] && [ "$(stat -c %u "$dir")" = 0 ]; then
        chown -h "$(id -u "$KALI_USER"):$(id -g "$KALI_USER")" "$dir" \
            || log "Could not chown $dir (the host filesystem may not allow it)."
    fi
}

# Never prints the password. KALI_PASSWORD_CUSTOM is only a flag for the banner.
set_password() {
    export KALI_PASSWORD_CUSTOM=
    if [ -n "${KALI_PASSWORD:-}" ]; then
        printf '%s:%s\n' "$KALI_USER" "$KALI_PASSWORD" | chpasswd
        KALI_PASSWORD_CUSTOM=1
    fi
    unset KALI_PASSWORD
}

prepare_user() {
    remap_user
    fix_work_dir
    set_password
}
