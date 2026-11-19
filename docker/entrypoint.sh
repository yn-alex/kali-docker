#!/bin/bash
# Starts as root: prepares the kali user, then hands over to the GUI
# supervisor (gui, still root) or drops privileges and runs the command (cli).
set -eu
# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"

prepare_user

case "${1:-}" in
    */gui-start.sh) exec "$@" ;;
esac

unset KALI_VNC_PASSWORD
cd "$KALI_HOME"
as_kali_exec "$@"
