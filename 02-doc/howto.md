# Howto: Dome Docker Scenarios

Scenarios for getting to a running ROS 2 environment. All read from the same
`manifest/` — single source of truth for packages, repos, and build flags.

## Which scenario?

| | 1. Raspberry Pi (microSD) | 2. VM (bare Ubuntu) | 3. Docker | 4. Cloud VM |
|---|---|---|---|---|
| Hardware | Pi 4 or 5 | VMware/Parallels/cloud VM | Pi 4 or 5 | Rented cloud VM |
| Setup starts from | Flashing a microSD | An already-installed Ubuntu 24.04 VM | Flashing a microSD | Pasting cloud-init at create time |
| ROS runs in | Natively on the Pi | Natively in the VM | Container | Natively in the VM |
| Build happens on | The Pi itself | The VM itself | Mac (cross-compile) | The cloud VM itself |
| Config | `DOME_TARGET=pi` (default) | `DOME_TARGET=vm` | n/a | `DOME_TARGET=cloud` |
| Image update | `git pull` + re-run scripts | `git pull` + re-run scripts | `docker compose pull` | `git pull` + re-run scripts |
| Best for | Pi-only, no Mac needed | Development without Pi hardware | Most users deploying to a Pi | Remote dev host, reachable from anywhere |
| Guide | [pi-howto.md](pi-howto.md) | [vm-howto.md](vm-howto.md) | [docker-howto.md](docker-howto.md) | [cloud-howto.md](cloud-howto.md) |

**Ordering note:** F06 (run the robot Docker image on macOS) also adds a
scenario. It has not landed yet; when it does, its scenario is added
alongside this one — the numbering here is not final.

Pick one guide and follow it start to finish — each is a single, self-contained
thread with no scenario switching mid-document. Scenarios 1, 2, and 4 all
install ROS natively via the same underlying scripts, differing only in
`DOME_TARGET`; scenario 3 (Docker) is Pi-only and builds the image on a Mac
instead.

## Common to scenarios 1 and 3 (Raspberry Pi)

### Flash the microSD

Use [Raspberry Pi Imager](https://www.raspberrypi.com/software/).

Settings:
- **Device:** Raspberry Pi 4 or 5
- **OS:** Ubuntu Server 24.04 LTS, 64-bit
- **Storage:** your microSD card

In the advanced settings (gear icon):
- **Hostname:** `dome`
- **Username:** same as `DOME_USER` (e.g. `pitosalas`)
- **Password:** your chosen password
- **SSH:** enabled
- **Wi-Fi:** SSID and password if using Wi-Fi

Write the image. This erases the card.

After flashing, eject and reinsert. On macOS it mounts as `/Volumes/system-boot`:

```sh
cp host-file-templates/boot/firmware/config.txt /Volumes/system-boot/config.txt
cp host-file-templates/boot/firmware/cmdline.txt /Volumes/system-boot/cmdline.txt
diskutil eject /Volumes/system-boot
```

### First boot — clone repo and configure

Insert card, power on, wait ~60 seconds, SSH in:

```sh
ssh pitosalas@dome.local
```

Install git and clone:

```sh
sudo apt update && sudo apt install -y git ca-certificates
git clone https://github.com/Boston-Robot-Hackers/provision_dome.git ~/provision_dome
cd ~/provision_dome
```

Create `manifest/user.txt` (gitignored — stays local):

```sh
printf 'DOME_USER=pitosalas\nDOCKERHUB_USERNAME=your-dockerhub-username\n' > manifest/user.txt
cat manifest/user.txt
```

