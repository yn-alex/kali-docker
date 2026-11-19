# AGENTS.md

Notes for anyone (human or agent) changing this repo. Open work is in `TODO.md`.

## Layout
- `Dockerfile`: targets `cli` (Kali + `KALI_PACKAGES`, user `kali`) and `gui` (`FROM cli` + XFCE, xrdp, noVNC).
- `docker/`: runtime scripts; shared helpers live in `docker/common.sh` (one rule in one place).
- `compose.yaml`: the one entry point on every OS; `.env.example` documents the settings.
- `tests/smoke.sh <cli|gui> <image>`: the only test logic. CI runs it before every push; run it locally too.
- `.github/workflows/publish.yml` (triggers) calls `image.yml` (per target: native amd64/arm64 build, smoke
  test, push by digest, merge into multi-arch tags).

## Gotchas (each one broke something once)
- `--no-install-recommends` drops packages the desktop needs: `xorgxrdp` (else RDP logins get no X server),
  `xfwm4`, `xfdesktop4`. Install them explicitly.
- Never overwrite the packaged `/etc/xrdp/xrdp.ini` / `sesman.ini`; a handwritten one without the proper
  `[Xorg]` section broke every session. Only write `startwm.sh` and set `AllowRootLogin=false`.
- xrdp sessions and login shells don't inherit Docker's `ENV`; they read `/etc/default/locale`. Without
  `LANG=C.UTF-8` there, Kali's prompt shows as garbage.
- Inside the container xrdp must listen on all interfaces; Docker forwards published ports to the container
  IP. Loopback-only exposure is done on the host side in compose (`127.0.0.1:...`).
- Root must never write, chown or chmod inside the home volume or the work bind mount: `kali` controls those
  paths and can plant symlinks (that once gave `kali` ownership of `/etc/shadow`). Do such work as `kali`.
- PUID/PGID remap: change ids by editing `/etc/passwd`/`groupmod`, not `usermod -u` (it chowns everything
  under the home, including the bind mount). `-xdev` doesn't separate a bind mount on the same filesystem.
- A TCP connect to a published port always succeeds (docker-proxy); check services by protocol (the smoke test
  sends an X.224 request for RDP).
- TigerVNC rejects passwords under 6 characters (hence the `kalikali` default).
- Apt stays signed: the base image ships `kali-archive-keyring`. Never add `--allow-unauthenticated` or
  insecure-repository settings.
- Compose with both `image:` and `build:` plus `pull_policy: daily` pulls when missing or older than a day and
  builds locally if the pull fails; that's how `up` always works.
- Scripts must have LF line endings (`.gitattributes`); a CRLF checkout on Windows breaks the container start.
- Tool packages set file capabilities in their postinst when `setcap` is present (nmap:
  `cap_net_admin,cap_net_raw,...=eip`). Docker doesn't grant `NET_ADMIN` by default, and exec of such a binary
  then fails with EPERM even for `--version`. `docker/fix-file-caps.sh` drops what Docker can't grant after each
  apt layer; the smoke test fails on any leftover. Test with the full tool set: a nmap-only build hid this.
- With recommends off, `wireshark` comes without `tshark`; list it explicitly. Check the full default tool set
  (a full local `cli` build needs ~10 GB free disk incl. build cache; the shared cache can fill the disk).
- Tools exit non-zero on `--help`/`--version` (hydra 255, john 1, gobuster 3); the smoke test judges "runs" by
  exec/loader errors, not exit 0.
- hashcat in a container needs `pocl-opencl-icd` and `ocl-icd-libopencl1` for a CPU backend.
- A named volume is seeded from the image only when first created; image changes to `/home/kali` don't reach
  existing volumes.
