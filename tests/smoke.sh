#!/usr/bin/env bash
# Smoke test for a built image. The only test logic; CI and local use call it.
#   tests/smoke.sh <cli|gui> <image>
# Needs only docker and curl on the host. Cleans up after itself.
set -euo pipefail

TARGET=${1:-}
IMAGE=${2:-}
if [[ ! $TARGET =~ ^(cli|gui)$ || -z $IMAGE ]]; then
    echo "usage: $0 <cli|gui> <image>" >&2
    exit 2
fi

NAME="kali-smoke-$$"
TMPDIR_SMOKE=$(mktemp -d)
SMOKE_PW="smoke-$RANDOM-$RANDOM"

# Root helper on the temp dir: tests create files owned by other uids, which
# the host user could not remove (or create) without root.
root_sh() { docker run --rm --entrypoint sh -v "$TMPDIR_SMOKE:/t" "$IMAGE" -c "$1"; }
owner_of() { stat -c '%u:%g' "$1" 2>/dev/null || stat -f '%u:%g' "$1"; }

cleanup() {
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    root_sh 'rm -rf /t/* /t/.[!.]*' >/dev/null 2>&1 || true
    rm -rf "$TMPDIR_SMOKE"
}
trap cleanup EXIT

pass() { echo "ok   $*"; }
fail() { echo "FAIL $*" >&2; exit 1; }

check() { # check <description> <command...>
    local desc=$1
    shift
    if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
}

run() { docker run --rm "$@"; }

# A command "runs" when it starts as kali. Not running: exit 126/127 (not
# executable, not found, missing shared library), death by signal (129-159),
# or, for a non-zero exit, output showing an exec or loader error. Other
# non-zero codes are fine (hydra -h exits 255).
runs() {
    run "$IMAGE" sh -c "out=\$($1 2>&1 </dev/null); r=\$?
        bad=
        [ \$r -eq 126 ] || [ \$r -eq 127 ] || { [ \$r -gt 128 ] && [ \$r -lt 160 ]; } && bad=1
        [ \$r -ne 0 ] && echo \"\$out\" | grep -qiE 'operation not permitted|not found|error while loading shared libraries|cannot execute' && bad=1
        [ -z \"\$bad\" ] || { echo \"exit \$r: \$out\" | head -c 400; exit 1; }"
}

# check_cmds <label> <command>...: runs every command, reports all failures.
check_cmds() {
    local label=$1 c out failed=0
    shift
    for c in "$@"; do
        if ! out=$(runs "$c"); then
            echo "FAIL $label does not run as kali: $c ($out)" >&2
            failed=1
        fi
    done
    [[ $failed == 0 ]] || exit 1
    pass "$label run as kali"
}

# Commands only; the package lists live in the Dockerfile. The basics are in
# every image, the tools only when the default tool set was built (recorded in
# a file by the Dockerfile), so custom local builds do not fail.
BASIC_CMDS=("ip -V" "ss -V" "ping -V" "curl --version" "wget --version" "python3 --version"
    "git --version" "vim --version" "nano --version" "unzip -v" "file --version" "less --version"
    "traceroute --version" "ssh -V" "netstat -V")
TOOL_CMDS=("nmap --version" "hydra -h" "john --version" "sqlmap --version" "hashcat --version"
    "tshark --version" "gobuster version" "ffuf -V" "nikto -Version" "whatweb --version" "dirb"
    "enum4linux -h" "smbclient --version" "nc -h" "tcpdump --version" "searchsploit -h"
    "dig -v" "whois --version")

test_tools() {
    local toolset out
    check_cmds "basic commands" "${BASIC_CMDS[@]}"
    out=$(run --entrypoint sh "$IMAGE" -c 'getcap -r /usr /bin /sbin /opt /lib 2>/dev/null | grep cap_net_admin || true')
    [[ -z $out ]] || fail "file capabilities Docker does not grant by default: $out"
    pass "no file capabilities beyond Docker's default set"
    toolset=$(run --entrypoint cat "$IMAGE" /usr/local/share/kali-docker/toolset)
    if [[ $toolset != default ]]; then
        echo "skip default tool checks (custom KALI_PACKAGES build)"
        return 0
    fi
    check_cmds "default tools" "${TOOL_CMDS[@]}"
    run "$IMAGE" sh -c 'hashcat -I 2>&1 | grep -q "Backend Device ID"' || fail "hashcat lists no OpenCL device"
    pass "hashcat has a device"
    run "$IMAGE" test -d /usr/share/wordlists || fail "no /usr/share/wordlists"
    pass "wordlists present"
}

test_cli() {
    local out
    out=$(run "$IMAGE" sh -c 'id -un; id -u')
    [[ $out == $'kali\n1000' ]] || fail "default user is kali (1000), got: $out"
    pass "runs as kali (1000)"

    test_tools

    out=$(run "$IMAGE" apt-config dump)
    if grep -Eiq '(AllowUnauthenticated|AllowInsecureRepositories|AllowDowngradeToInsecureRepositories)[^;]*"true"' <<<"$out"; then
        fail "apt allows unauthenticated or insecure repositories"
    fi
    pass "apt-config has no insecure settings"
    out=$(run "$IMAGE" ls /etc/apt/apt.conf.d)
    if grep -Eiq 'insecure|allow' <<<"$out"; then fail "insecure apt.conf.d file present"; fi
    pass "no insecure file in apt.conf.d"

    test_puid
}

# PUID/PGID remap must keep existing owners in the bind mount, and a
# root-owned bind source must become writable without recursion.
test_puid() {
    local work="$TMPDIR_SMOKE/work" out
    root_sh 'mkdir -p /t/work/sub && touch /t/work/rootfile /t/work/sub/otherfile &&
        chown 4321:4321 /t/work/sub/otherfile && chmod -R 777 /t/work'
    touch "$work/mine"
    local mine_owner
    mine_owner=$(owner_of "$work/mine")
    out=$(run -e PUID=1234 -e PGID=1234 -v "$work:/home/kali/work" "$IMAGE" \
        sh -c 'id -u; touch /home/kali/work/probe')
    [[ $out == 1234 ]] || fail "PUID remap: container uid is 1234, got: $out"
    [[ $(owner_of "$work/probe") == 1234:1234 ]] || fail "PUID remap: new file is not 1234:1234"
    [[ $(owner_of "$work/rootfile") == 0:0 ]] || fail "PUID remap changed a root-owned file in the bind mount"
    [[ $(owner_of "$work/sub/otherfile") == 4321:4321 ]] || fail "PUID remap changed a foreign-owned file in the bind mount"
    [[ $(owner_of "$work/mine") == "$mine_owner" ]] || fail "PUID remap changed the host user's file in the bind mount"
    pass "PUID/PGID remap leaves bind-mount owners alone"

    root_sh 'mkdir /t/rootwork && ln -s /t/work/rootfile /t/rootwork/link'
    out=$(run -v "$TMPDIR_SMOKE/rootwork:/home/kali/work" "$IMAGE" \
        sh -c 'touch /home/kali/work/f && stat -c %u /home/kali/work')
    [[ $out == 1000 ]] || fail "root-owned work dir was not handed to kali, got: $out"
    [[ $(owner_of "$TMPDIR_SMOKE/rootwork/link") == 0:0 ]] || fail "work dir chown was recursive"
    pass "root-owned work dir fixed, top directory only"
}

wait_healthy() {
    local status
    for _ in $(seq 1 60); do
        status=$(docker inspect -f '{{.State.Health.Status}}' "$NAME" 2>/dev/null || echo gone)
        [[ $status == healthy ]] && return 0
        [[ $status == gone ]] && return 1
        sleep 3
    done
    return 1
}

host_port() { docker port "$NAME" "$1/tcp" | head -n1 | sed 's/.*://'; }

test_gui() {
    test_tools
    docker run -d --name "$NAME" --shm-size 512m -e "KALI_PASSWORD=$SMOKE_PW" \
        -p 127.0.0.1::3389 -p 127.0.0.1::6080 "$IMAGE" >/dev/null
    if ! wait_healthy; then
        docker logs "$NAME" 2>&1 | tail -n 30 >&2
        fail "container did not become healthy"
    fi
    pass "container healthy"

    if docker logs "$NAME" 2>&1 | grep -qF "$SMOKE_PW"; then fail "password printed in logs"; fi
    pass "password not in logs"

    # A real desktop session: starts Xorg (xorgxrdp) and XFCE as kali.
    echo "$SMOKE_PW" | docker exec -i "$NAME" xrdp-sesrun -F 0 kali >/dev/null 2>&1 \
        || fail "xrdp-sesrun could not start a session"
    # Each xfwm4 prints "<display> <LANG>". The noVNC desktop on :1 runs one
    # too; the xrdp session is the one on another display.
    local sessions="" xrdp_lang=""
    for _ in $(seq 1 30); do
        sessions=$(docker exec -u kali "$NAME" sh -c '
            for p in $(pgrep -u kali -x xfwm4); do
                tr "\0" "\n" < /proc/$p/environ |
                    awk -F= "/^DISPLAY=/{d=\$2} /^LANG=/{l=\$2} END{print d, l}"
            done') || true
        xrdp_lang=$(awk '$1 != ":1" && $1 != "" {print $2}' <<<"$sessions" | head -n1)
        [[ -n $sessions && $(wc -l <<<"$sessions") -ge 2 && -n $xrdp_lang ]] && break
        sleep 2
    done
    [[ -n $xrdp_lang ]] || fail "no xfwm4 on the xrdp session display (got: $sessions)"
    pass "RDP session runs xfwm4 as kali"
    [[ -z $(awk '$2 != "C.UTF-8"' <<<"$sessions") ]] \
        || fail "a desktop session lacks LANG=C.UTF-8 (got: $sessions)"
    pass "RDP and noVNC sessions have LANG=C.UTF-8"
    check "firefox-esr is installed" docker exec -u kali "$NAME" firefox-esr --version

    local novnc rdp code reply
    novnc=$(host_port 6080)
    rdp=$(host_port 3389)
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://127.0.0.1:${novnc}/vnc.html" || true)
    [[ $code == 200 ]] || fail "noVNC /vnc.html returned $code"
    pass "noVNC page 200"

    # docker-proxy accepts TCP even with nothing behind it, so send an X.224
    # Connection Request and require a TPKT reply (first byte 0x03).
    # shellcheck disable=SC2016  # $1 is for the inner bash
    reply=$(timeout 10 bash -c '
        exec 3<>"/dev/tcp/127.0.0.1/$1" || exit 1
        printf "\x03\x00\x00\x13\x0e\xe0\x00\x00\x00\x00\x00\x01\x00\x08\x00\x03\x00\x00\x00" >&3
        head -c1 <&3 | od -An -tx1' _ "$rdp" 2>/dev/null | tr -d ' \n') || true
    [[ $reply == 03 ]] || fail "RDP port ${rdp} did not answer an RDP connection request (got: '$reply')"
    pass "RDP answers a connection request"

    test_root_never_follows_home_links
}

# Root-run startup code must not follow links planted by kali in the home
# volume (a symlinked ~/.vnc/passwd once turned /etc/shadow into kali's file).
stat_in_container() { docker exec "$NAME" stat -c '%U:%G:%a' "$@"; }

# Restart, then wait until the supervisor has run all its root-side startup
# code (it prints the banner last) or the container has exited, whichever
# comes first. Logs survive a restart, so count banners instead of grepping.
banner_count() { docker logs "$NAME" 2>&1 | grep -c 'Kali desktop is running' || true; }

restart_and_wait_for_startup() {
    local before
    before=$(banner_count)
    docker restart -t 10 "$NAME" >/dev/null
    for _ in $(seq 1 120); do
        [[ $(banner_count) -gt $before ]] && return 0
        [[ $(docker inspect -f '{{.State.Running}}' "$NAME") == true ]] || return 0
        sleep 0.5
    done
    fail "no startup banner within 60 s after restart"
}

test_root_never_follows_home_links() {
    local shadow etc
    shadow=$(stat_in_container /etc/shadow)
    etc=$(stat_in_container /etc)

    docker exec -u kali "$NAME" sh -c 'mkdir -p ~/.vnc && ln -sf /etc/shadow ~/.vnc/passwd'
    docker restart -t 10 "$NAME" >/dev/null
    wait_healthy || fail "container not healthy after restart with a symlinked ~/.vnc/passwd"
    [[ $(stat_in_container /etc/shadow) == "$shadow" ]] || fail "/etc/shadow changed through ~/.vnc/passwd symlink"
    pass "symlinked ~/.vnc/passwd does not touch /etc/shadow"

    docker exec -u kali "$NAME" sh -c 'rm -rf ~/.vnc && ln -s /etc ~/.vnc'
    restart_and_wait_for_startup  # startup may fail here (kali cannot write /etc); only ownership matters
    [[ $(stat_in_container /etc) == "$etc" ]] || fail "/etc changed through ~/.vnc symlink"
    [[ $(stat_in_container /etc/shadow) == "$shadow" ]] || fail "/etc/shadow changed through ~/.vnc symlink"
    pass "symlinked ~/.vnc does not touch /etc"
}

"test_$TARGET"
echo "smoke test passed ($TARGET, $IMAGE)"
