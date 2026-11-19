# Kali Linux in Docker, two targets:
#   cli  Kali + a tool set, non-root user, no X      docker build --target cli .
#   gui  cli + XFCE desktop over RDP (xrdp) and the browser (noVNC)
# Tool set: --build-arg KALI_PACKAGES="nmap hydra" replaces the default set below
# (any Kali metapackage or tool list). Leave it empty for the default.

FROM kalilinux/kali-rolling AS cli

# The default tool set (one list, one place): the Kali top 10 plus beginner tools.
# hashcat needs an OpenCL device: pocl-opencl-icd is a CPU backend and
# ocl-icd-libopencl1 the loader hashcat opens (not a dependency of pocl).
ARG KALI_DEFAULT_PACKAGES="kali-tools-top10 \
    hashcat pocl-opencl-icd ocl-icd-libopencl1 wordlists gobuster ffuf nikto whatweb dirb enum4linux \
    smbclient netcat-traditional tcpdump exploitdb dnsutils whois tshark"
ARG KALI_PACKAGES=""
# Always installed, whatever KALI_PACKAGES says: everyday command line tools.
ARG KALI_BASICS="iproute2 iputils-ping net-tools traceroute openssh-client curl wget \
    unzip file less python3 git vim nano"
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8

# Plain signed apt: the base image ships kali-archive-keyring, so no key
# handling, no apt-key, no unauthenticated installs.
#
# Layer 1 (system): --no-install-recommends. First what the entrypoint and a
# usable shell need (sudo, setpriv from util-linux, usermod from passwd, procps
# for pgrep, libcap2-bin for the capability fix below, tini as PID 1 to reap zombies and forward signals), hardcoded here
# so a KALI_PACKAGES override cannot break the image; then KALI_BASICS.
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        sudo util-linux passwd procps tini ca-certificates zsh libcap2-bin ${KALI_BASICS} \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Layer 2 (tools): --no-install-recommends as well. Recommends of the Kali
# metapackages mostly pull GUI front ends and docs, which the cli target does
# not need and which would add hundreds of MB. Tools keep their hard
# dependencies. CI smoke-tests the result; if a tool misses an optional
# helper, add it to the list instead of enabling recommends globally.
# The file records whether the default set was used; tests/smoke.sh reads it
# so it only checks the default tools on default builds.
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends ${KALI_PACKAGES:-$KALI_DEFAULT_PACKAGES} \
    && mkdir -p /usr/local/share/kali-docker \
    && if [ -n "$KALI_PACKAGES" ]; then echo custom; else echo default; fi \
        > /usr/local/share/kali-docker/toolset \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Tool packages may set file capabilities that Docker's default capability set
# cannot grant, which makes the tool fail to start as kali (see the script).
# Copied here, not with the rest of docker/, so script edits keep the tool layer cached.
COPY docker/fix-file-caps.sh /usr/local/lib/kali-docker/
RUN sh /usr/local/lib/kali-docker/fix-file-caps.sh

# Login shells and xrdp sessions do not inherit Docker's ENV; they read this.
RUN echo "LANG=$LANG" > /etc/default/locale

# Login shell zsh (installed above), default password kali.
# Override the password at run time with KALI_PASSWORD.
RUN groupadd -g 1000 kali \
    && useradd -m -u 1000 -g 1000 -s /usr/bin/zsh -G sudo kali \
    && echo "kali:kali" | chpasswd \
    && mkdir -p /home/kali/work && touch /home/kali/.hushlogin \
    && chown kali:kali /home/kali/work /home/kali/.hushlogin

COPY docker/ /usr/local/lib/kali-docker/
RUN chmod 755 /usr/local/lib/kali-docker/*.sh

WORKDIR /home/kali
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/lib/kali-docker/entrypoint.sh"]
CMD ["sh", "-c", "exec \"$SHELL\" -l"]


FROM cli AS gui

# Recommends matter here: xfwm4 and xfdesktop4 are only Recommends of the
# XFCE packages and xorgxrdp only of xrdp (without it RDP logins get no X
# server), so they are named explicitly under --no-install-recommends.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        xfce4-session xfce4-panel xfwm4 xfdesktop4 xfce4-terminal thunar \
        xrdp xorgxrdp dbus dbus-x11 \
        tigervnc-standalone-server tigervnc-tools novnc websockify \
        firefox-esr \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && adduser xrdp ssl-cert \
    && sh /usr/local/lib/kali-docker/fix-file-caps.sh

# Keep the packaged xrdp.ini and sesman.ini (a handwritten one broke every
# session); only start XFCE from startwm.sh and refuse root logins.
RUN sed -i 's/^AllowRootLogin=.*/AllowRootLogin=false/' /etc/xrdp/sesman.ini \
    && printf '%s\n' \
        '#!/bin/sh' \
        'if [ -r /etc/default/locale ]; then' \
        '  . /etc/default/locale' \
        '  export LANG LANGUAGE' \
        'fi' \
        'startxfce4' > /etc/xrdp/startwm.sh \
    && chmod 755 /etc/xrdp/startwm.sh \
    && mkdir -p /var/run/dbus /var/run/xrdp

ENV KALI_TARGET=gui
EXPOSE 3389 6080
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD ["/usr/local/lib/kali-docker/healthcheck.sh"]
CMD ["/usr/local/lib/kali-docker/gui-start.sh"]
