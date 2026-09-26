# Pi Howto: Raspberry Pi, microSD to Native ROS

Scenario 1 of 3 (see `02-doc/howto.md`) — flash a microSD, install ROS 2
natively on the Pi (`DOME_TARGET=pi`, the default). No Mac/VM build step;
everything after flashing runs on the Pi itself, over SSH from your Mac
("Primary").

---

## Prerequisites

- Raspberry Pi 4 or 5
- microSD card (16 GB or larger)
- microSD card reader (any machine for flashing)
- GitHub SSH key on your **Primary** machine (Mac) — copied to the Pi in
  Step 5, required for private repos (`rosutils`, `dome`, etc.)

---

## Step 1: Primary — Flash microSD

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

Write, insert the card into the Pi, and power it on.

---

## Step 2: Pi — First Boot

SSH in from Primary (mDNS usually resolves `dome.local`):

```sh
ssh pitosalas@dome.local
```

Clone the repo and enter it:

```sh
sudo apt update && sudo apt install -y git ca-certificates
git clone https://github.com/Boston-Robot-Hackers/provision_dome.git ~/provision_dome
cd ~/provision_dome
```

Create `manifest/user.txt` on the **Pi** — this file is gitignored and must
be created manually on every machine:

```sh
printf 'DOME_USER=pitosalas\nDOCKERHUB_USERNAME=pitosalas\n' > manifest/user.txt
cat manifest/user.txt
```

Replace `pitosalas` with your actual Linux username. `DOME_USER` must match
the username you set in Raspberry Pi Imager during flashing. All build
scripts read this file to know which user to set up. No `DOME_TARGET` line
needed — it defaults to `pi` in `manifest/config.txt`.

`bare-metal-base.sh` also sets up a swapfile on Pi targets, sized by
`SWAP_SIZE_MB` in `manifest/config.txt` (default `2048`, i.e. 2GB). This
guards against `colcon build` OOMing on 4GB Pi5 boards, since
`manifest/colcon.txt` sets no parallel-job cap and colcon defaults to using
all cores. Override in `manifest/user.txt` (`SWAP_SIZE_MB=4096` for more
headroom, `SWAP_SIZE_MB=0` to disable).

**Primary** — set these once so every later `ssh`/`scp` command below can
just reuse them instead of retyping the username and address each time:

```sh
export TARGET_USER=pitosalas   # match DOME_USER above
export TARGET_HOST=dome.local
```

---

## Step 3: Pi — Host Setup

Creates the Pi user, configures udev, sets up system services:

```sh
export DOME_PASSWORD=yourpassword
sudo --preserve-env=DOME_USER,DOME_PASSWORD scripts/host-setup.sh
```

`host-setup.sh` prints the Pi's IP addresses just before finishing. If
`TARGET_HOST` (set in Step 2) doesn't match one of them, update it now —
then reboot when complete:

> udev rules only get copied to `/etc/udev/rules.d/` when this script runs.
> If you pull changes to `host-file-templates/etc/udev/rules.d/*.rules`
> later, re-run `sudo scripts/host-setup.sh` (or manually `install` the
> file and run `sudo udevadm control --reload-rules && sudo udevadm trigger`)
> to apply them — a plain `git pull` does not.

```sh
sudo reboot
```

SSH back in from Primary:

```sh
ssh "${TARGET_USER}@${TARGET_HOST}"   # mDNS usually works for dome.local
cd ~/provision_dome
```

---

## Step 4: Pi — Install ROS And Packages

Runs as root. Reads from `manifest/` to install:
- ROS 2 apt repository and `ros-kilted-ros-base`
- All apt, ROS, and pip packages from `manifest/packages.txt` and
  `manifest/pip.txt`, including Pi-hardware packages: `raspi-config`,
  `i2c-tools`, `RPi.GPIO`, `spidev`
- Third-party apt repos (GitHub CLI, VS Code) from
  `manifest/apt-repos.txt`
- Curl-installed tools (mcfly) from `manifest/tools.txt`
- Initialises rosdep

```sh
sudo scripts/bare-metal-base.sh
```

Time varies by target hardware and network speed.

---

## Step 5: Pi — Clone Repos And Build Workspace

Runs as root. Reads from `manifest/` to:
- Create home directory structure from `manifest/dirs.txt`
- Clone all repos from `manifest/repos.txt`, including Pi-hardware repos:
  `libcamera-apps`, `seeed-linux-dtoverlays`, `mic_hat`
- Run `rosdep install` with skip-keys from `manifest/rosdep.txt`
- Run `colcon build` with flags from `manifest/colcon.txt`
- Install `manifest/bashrc` and `bru` symlink

Requires GitHub SSH key present for private repos.

**Primary** — copy your key from Mac to the Pi:

```sh
scp ~/.ssh/id_ed25519 "${TARGET_USER}@${TARGET_HOST}:~/.ssh/id_ed25519"
scp ~/.ssh/id_ed25519.pub "${TARGET_USER}@${TARGET_HOST}:~/.ssh/id_ed25519.pub"
```

**Pi** — set permissions and verify GitHub access:

```sh
chmod 600 ~/.ssh/id_ed25519
ssh -T git@github.com   # expect: "Hi <user>! You've successfully authenticated"
```

**Pi** — load the key into the agent:

```sh
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

**Pi** — then build:

```sh
sudo scripts/bare-metal-build.sh
```

colcon build is slow on ARM; time varies a lot by target CPU.

---

## Step 6: Pi — Smoke Test

`bare-metal-build.sh` installed `.bashrc` so ROS and the workspace overlay
are sourced automatically in every new shell — **open a new terminal / SSH
session** (don't reuse the one `bare-metal-build.sh` ran in) and run:

```sh
echo "$ROS_DISTRO"
ros2 --help
ls ~/ros2_ws/src
```

Expected: `kilted`, ros2 usage, list of cloned repos.

---

## Development Cycle

All commands below run on the **Pi**.

**Update provision_dome and rebuild:**

```sh
cd ~/provision_dome
git pull
sudo scripts/bare-metal-build.sh   # clones newly added repos, rebuilds workspace
```

The build script **skips any repo that is already cloned**, so this does not
update the ROS repos already on disk. To update one, pull it by hand, then
rebuild:

```sh
git -C ~/ros2_ws/src/<repo> pull
sudo ~/provision_dome/scripts/bare-metal-build.sh
```

Open a new terminal / SSH session afterward to pick up the rebuilt workspace
overlay.

**Add a package** — edit `manifest/packages.txt` or `manifest/pip.txt`, then:

```sh
sudo scripts/bare-metal-base.sh    # reinstalls packages (idempotent)
```

**Add a repo** — edit `manifest/repos.txt`, then:

```sh
sudo scripts/bare-metal-build.sh   # clones new repo, rebuilds
```

---

## Migrating A Pi Set Up Before The Repo Rename

This repo was renamed from `dome-docker` to `provision_dome`. A Pi
provisioned under the old name needs two manual steps — **a `git pull` alone
is not enough and will break your shell**.

Rename the checkout and pull:

```sh
cd ~ && mv dome-docker provision_dome
cd ~/provision_dome && git pull
```

Then refresh `~/.bashrc`. This is the step people miss: `manifest/bashrc` is
a *template* that only reaches `~/.bashrc` when `bare-metal-build.sh` copies
it, so pulling updates the template and leaves your actual shell config
pointing at the old path:

```sh
cp ~/provision_dome/manifest/bashrc ~/.bashrc
```

Verify in a **new** SSH session:

```sh
echo "$ROS_DISTRO"          # expect: kilted
ros2 pkg list | grep -c dome
```

`cp` overwrites wholesale, matching what `bare-metal-build.sh` does. If you
hand-edited `~/.bashrc` on this Pi, diff it first — the repo path should be
the only difference.

---

## Troubleshooting

All commands below run on the **Pi** unless noted.

**New shells fail with `/opt/ros//setup.bash: No such file or directory`**
(note the empty path segment) — `~/.bashrc` points at a directory that no
longer exists, almost always because this Pi predates the `dome-docker` →
`provision_dome` rename. See *Migrating A Pi Set Up Before The Repo Rename*
above.

**`bare-metal-base.sh` fails on apt-get** — network issue or stale cache:
```sh
sudo apt-get update
sudo scripts/bare-metal-base.sh
```

**`host-setup.sh` fails: "Network is not ready: no route to the internet."**
— wlan0 DHCP not up yet at boot (race condition right after `sudo reboot` /
fresh flash). Wait a few seconds, verify, then re-run:
```sh
ip route get 1.1.1.1   # should print a route, not an error
sudo --preserve-env=DOME_USER,DOME_PASSWORD scripts/host-setup.sh
```

**`ERROR: failed to clone <private-repo>`** — SSH key not available to sudo:
```sh
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
ssh -T git@github.com          # confirm: "Hi <user>! You've successfully authenticated"
sudo scripts/bare-metal-build.sh
```

**colcon build fails** — rosdep may be missing a dependency:
```sh
cd ~/ros2_ws
rosdep update
rosdep install --from-paths src --ignore-src -r -y --skip-keys="ament_python gazebo_ros_pkgs"
colcon build --packages-skip depthai_rospi
```

**`ERROR: 'X' not set in manifest/config.txt`** — required field missing from manifest:
```sh
cat manifest/config.txt   # verify ROS_DISTRO, UBUNTU_CODENAME, DOME_USER present
```
