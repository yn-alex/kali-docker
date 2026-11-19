# Kali Docker

Kali Linux in Docker, in two flavours: a command-line container (`cli`) and a full desktop (`gui`) you reach
over RDP or in the browser. Images are built for amd64 and arm64, so they run on macOS, Windows and Linux. They
build on the official `kalilinux/kali-rolling` image and are published at `ghcr.io/yn-alex/kali-docker`.

Default logins:

| Access | User | Password |
|---|---|---|
| RDP (`localhost:3389`) | `kali` | `kali` |
| Browser / noVNC (`http://localhost:6080/vnc.html`) | none | `kalikali` |
| `sudo` inside the container | `kali` | `kali` |

Change them with `KALI_PASSWORD` and `KALI_VNC_PASSWORD` in `.env` (see [Settings](#settings)). The ports listen
on `127.0.0.1` only, so with the defaults the desktop is reachable only from your own machine.

## Requirements

- macOS or Windows: Docker Desktop. Linux: Docker Engine with the compose plugin.
- git to clone this repo (or download it as a ZIP from GitHub).

```bash
git clone https://github.com/yn-alex/kali-docker.git
cd kali-docker
```

## Quick start

```bash
docker compose run --rm kali                # a Kali shell; the container is removed when you exit
docker compose --profile gui up -d          # the desktop, in the background
docker compose --profile gui down           # stop the desktop (your files stay)
docker compose --profile gui down -v        # stop and delete the home volume too
```

The first start pulls the image, which can take a while. Without cloning, use the image directly:

```bash
docker run -it --rm ghcr.io/yn-alex/kali-docker:cli
docker run -d --name kali-gui --shm-size=512m -p 127.0.0.1:3389:3389 -p 127.0.0.1:6080:6080 \
  ghcr.io/yn-alex/kali-docker:gui
```

## Connecting to the desktop

- RDP at `localhost:3389`. Windows: the built-in Remote Desktop Connection. macOS: Microsoft "Windows App"
  from the App Store. Linux: Remmina or FreeRDP. Accept the self-signed certificate warning.
- Or open `http://localhost:6080/vnc.html` in a browser (noVNC).

Log in with the [default logins](#kali-docker) above. The noVNC password is longer because the VNC server
rejects passwords shorter than 6 characters.

## Your files

- Home folder: `/home/kali` is a Docker volume (`kali-home`). It survives restarts and `down`, and is deleted
  by `down -v`.
- Work folder: `~/kali-workspace` on your computer appears as `~/work` in Kali. Use it for files you want on
  the host. Change the folder with `KALI_WORKDIR`.
- Linux only: set `KALI_UID` and `KALI_GID` (from `id -u` and `id -g`) so files in the work folder belong to
  you. Docker Desktop on macOS and Windows handles ownership itself.

## Settings

Copy `.env.example` to `.env` and edit it; every line is optional and documented there. Main variables:

| Variable | Default | Meaning |
|---|---|---|
| `KALI_WORKDIR` | `~/kali-workspace` | Host folder mounted as `~/work` |
| `KALI_UID`, `KALI_GID` | `1000` | Linux: owner of files in the work folder |
| `KALI_PASSWORD` | `kali` | Password of user `kali` |
| `KALI_VNC_PASSWORD` | `kalikali` | noVNC password (6 to 8 characters) |
| `KALI_RDP`, `KALI_NOVNC` | `127.0.0.1:3389`, `127.0.0.1:6080` | Host address and port of the desktop |
| `KALI_PULL` | `daily` | `daily`, `always`, `missing`, `never` or `build` |

## Images and tags

| Tag | Content | Download (amd64 / arm64) |
|---|---|---|
| `cli`, `latest` | Command-line Kali | 2.1 GB / 1.4 GB |
| `gui` | `cli` plus XFCE desktop, Firefox, xrdp and noVNC | 2.3 GB / 1.6 GB (includes `cli`) |
| `cli-YYYYMMDD`, `gui-YYYYMMDD` | Dated builds, for pinning |
| `cli-sha-<commit>`, `gui-sha-<commit>` | Build of one commit, for pinning | |

Unpacked on disk the `cli` image takes about 6 GB (Metasploit and Burp are the largest parts).

Kali is a rolling release, so the images are rebuilt every week. Compose pulls the published image (at most
once a day by default) and builds from the `Dockerfile` if the pull fails. `KALI_PULL=never` uses what you
have; `KALI_PULL=build` always builds locally. To pin a version, set `KALI_CLI_TAG` / `KALI_GUI_TAG` in `.env`.

## Included tools

- The Kali `kali-tools-top10` set plus beginner extras: hashcat, wordlists, gobuster, ffuf, nikto, whatweb,
  dirb, enum4linux, smbclient, netcat, tcpdump, exploitdb, dnsutils, whois.
- Basics: ip, ss, ping, ifconfig, netstat, traceroute, ssh, curl, wget, python3, git, vim, nano.
- Firefox in the `gui` image.

Install more inside the container with `sudo apt install <package>` (lost when the container is recreated), or
build your own image with a different list: set `KALI_PACKAGES` in `.env` and `KALI_PULL=build`, or
`docker build --target cli --build-arg KALI_PACKAGES="kali-tools-top10 kali-tools-web" .`
(`KALI_PACKAGES` replaces the default tool set; the basics are always installed.)

## Good to know

- Docker Desktop runs containers in a VM: there is no real host networking, and Wireshark sees only the VM's
  traffic, not your computer's.
- nmap runs as `kali` without extra rights; for SYN or OS scans add `--privileged` (or use `sudo nmap`).
- VPN clients and tools that change network settings need extra rights: uncomment the `cap_add` and
  `devices` lines in `compose.yaml`.
- Windows: if the built-in Remote Desktop already uses port 3389, set `KALI_RDP=127.0.0.1:13389` and connect to
  `localhost:13389`.
- SELinux hosts (Fedora, RHEL): uncomment the `bind:` / `selinux: z` lines in `compose.yaml` so the work folder
  is usable.
- Only expose the desktop beyond `127.0.0.1` after changing both passwords.

## Building locally and contributing

```bash
KALI_PULL=build docker compose run --rm kali      # build the image from this folder, then run it
tests/smoke.sh cli <image>                         # smoke test of a built image (cli or gui)
```

See `AGENTS.md` for how the repo is organised and its gotchas, and `CONTRIBUTING.md` for how to send changes.
Bug reports and ideas: https://github.com/yn-alex/kali-docker/issues

## License

MIT, see [LICENSE](LICENSE). Kali Linux and the tools in the images keep their own licenses.
