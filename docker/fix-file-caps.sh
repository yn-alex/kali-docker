#!/bin/sh
# Build-time step. Some Kali packages (nmap, wireshark's dumpcap, ...) set file
# capabilities in their postinst, e.g. cap_net_admin+eip. Docker's default
# capability set lacks some of them (NET_ADMIN), and execve of a binary whose
# permitted file capabilities cannot all be granted fails with EPERM for a
# non-root user: the tool then does not even print its version.
# This removes every file capability Docker does not grant by default and
# keeps the rest, so tools run as kali with no cap_add. Raw-socket features
# work through sudo, or when the user enables the cap_add lines in compose.yaml.
set -eu

# Docker's default capability set (lowercase, as getcap prints them).
ALLOWED=" cap_chown cap_dac_override cap_fowner cap_fsetid cap_kill cap_setgid cap_setuid cap_setpcap cap_net_bind_service cap_net_raw cap_sys_chroot cap_mknod cap_audit_write cap_setfcap "

command -v getcap >/dev/null || exit 0

getcap -r /usr /bin /sbin /opt /lib 2>/dev/null | while IFS= read -r line; do
    file=${line%% *}
    spec=${line#"$file"}
    spec=${spec# }
    spec=${spec#= }                       # older libcap: "file = cap_x+eip"
    list=${spec%%[=+]*}
    flags=${spec#"$list"}
    keep=""
    for cap in $(echo "$list" | tr ',' ' '); do
        case "$ALLOWED" in
            *" $cap "*) keep="${keep:+$keep,}$cap" ;;
            *) echo "fix-file-caps: dropping $cap from $file" ;;
        esac
    done
    [ "$keep" = "$list" ] && continue
    if [ -n "$keep" ]; then setcap "${keep}${flags}" "$file"; else setcap -r "$file"; fi
done
