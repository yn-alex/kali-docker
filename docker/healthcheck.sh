#!/bin/sh
# Healthy when xrdp, xrdp-sesman, Xvnc and websockify are all running.
pgrep -x xrdp >/dev/null &&
pgrep -x xrdp-sesman >/dev/null &&
pgrep -f 'Xtigervnc|Xvnc' >/dev/null &&
pgrep -f websockify >/dev/null
