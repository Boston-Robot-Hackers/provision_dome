# VM Howto: Bare Ubuntu VM to Native ROS

Scenario 2 of 3 (see `02-doc/howto.md`) — a generic Ubuntu 24.04 (noble) VM
(VMware, Parallels, cloud), no Pi hardware needed. Install ROS 2 natively in
the VM (`DOME_TARGET=vm`). Same scripts as the Pi path, run inside the VM
itself (over SSH from your Mac "Primary", or directly in the VM console).

---

## Prerequisites

Must be **Ubuntu 24.04 (noble)** specifically — matching
`UBUNTU_CODENAME=noble` in `manifest/config.txt` and the ROS 2 apt repo the
scripts configure. A different Ubuntu release (older or newer) has mismatched
system library versions and will fail with cryptic `apt` dependency errors
partway through `bare-metal-base.sh`, not with a clear "wrong OS" message.

Verify before doing anything else:

```sh
cat /etc/os-release   # VERSION_CODENAME must be "noble"
```

Reachable over SSH, with a known IP address (or work directly in the VM's
console window — no SSH required).

GitHub SSH key on your **Primary** machine — copied to the VM in Step 4,
required for private repos (`rosutils`, `dome`, etc.), unless you're working
directly in the console and prefer to `ssh-keygen` there instead.

---

## Step 1: Boot The VM

Create or boot the VM with Ubuntu 24.04 (noble) already installed. No
flashing step — this replaces it.

---

## Step 2: VM — First Boot

Run the following either in the VM's console window directly, or over SSH
from Primary (`ssh pitosalas@<vm-ip>` — note the IP first):

```sh
sudo apt update && sudo apt install -y git ca-certificates
git clone https://github.com/Boston-Robot-Hackers/provision_dome.git ~/provision_dome
cd ~/provision_dome
```

Create `manifest/user.txt` on the **VM** — this file is gitignored and must
be created manually on every machine:

```sh
printf 'DOME_USER=pitosalas\nDOCKERHUB_USERNAME=pitosalas\n' > manifest/user.txt
cat manifest/user.txt
```

Replace `pitosalas` with your actual Linux username. `DOME_USER` must match
the user account on the VM. All build scripts read this file to know which
user to set up.

Add `DOME_TARGET=vm` — without it, every script below installs
Pi-hardware-only packages/repos and the ReSpeaker overlay build fails (no
`/boot/firmware` on a VM):

```sh
printf 'DOME_TARGET=vm\n' >> manifest/user.txt
```

**Primary** (only if accessing over SSH) — set these once so every later
`ssh`/`scp` command below can just reuse them instead of retyping the
username and address each time:

```sh
export TARGET_USER=pitosalas   # match DOME_USER above
export TARGET_HOST=<vm-ip>     # mDNS often unavailable for VMs
```

---

## Step 3: VM — Host Setup

Identical to the Pi path. Creates the VM user, configures udev, sets up
system services (Pi-hardware-only steps, e.g. the ReSpeaker overlay build,
are skipped automatically because of `DOME_TARGET=vm`):

```sh
export DOME_PASSWORD=yourpassword
sudo --preserve-env=DOME_USER,DOME_PASSWORD scripts/host-setup.sh
```

`host-setup.sh` prints the VM's IP addresses just before finishing. If
`TARGET_HOST` (set in Step 2) doesn't match one of them, update it now —
then reboot when complete:

```sh
sudo reboot
```

If you're working directly in the VM's console window, no SSH needed — just
wait for the reboot and continue there:

```sh
cd ~/provision_dome
```

Only reconnect over SSH if you're accessing the VM remotely from Primary:

```sh
ssh "${TARGET_USER}@${TARGET_HOST}"
cd ~/provision_dome
```

---

## Step 4: VM — Install ROS And Packages

Runs as root. Reads from `manifest/` to install:
- ROS 2 apt repository and `ros-kilted-ros-base`
- All apt, ROS, and pip packages from `manifest/packages.txt` and
  `manifest/pip.txt` (Pi-only packages `raspi-config`, `i2c-tools`,
  `RPi.GPIO`, `spidev` are skipped because `DOME_TARGET=vm`)
- Third-party apt repos (Doppler, GitHub CLI, VS Code) from
  `manifest/apt-repos.txt`
- Curl-installed tools (mcfly) from `manifest/tools.txt`
- Initialises rosdep

```sh
sudo scripts/bare-metal-base.sh
```

Time varies by VM resources and network speed.

---

## Step 5: VM — Clone Repos And Build Workspace

Runs as root. Reads from `manifest/` to:
- Create home directory structure from `manifest/dirs.txt`
- Clone all repos from `manifest/repos.txt` (Pi-only repos
  `libcamera-apps`, `seeed-linux-dtoverlays`, `mic_hat` are skipped because
  `DOME_TARGET=vm`)
- Run `rosdep install` with skip-keys from `manifest/rosdep.txt`
- Run `colcon build` with flags from `manifest/colcon.txt`
- Install `manifest/bashrc` as `~/.bashrc`, and the `bru` symlink. This is
  where `ROS_DISTRO` (read from `manifest/config.txt`) actually takes
  effect: `manifest/bashrc` exports it and sources the ROS/workspace setup,
  and this step is what copies that file to `~/.bashrc` so every *new*
  shell picks it up (see Step 6)

Requires GitHub SSH key present for private repos.

**Primary** — copy your key from Mac to the VM:

```sh
scp ~/.ssh/id_ed25519 "${TARGET_USER}@${TARGET_HOST}:~/.ssh/id_ed25519"
scp ~/.ssh/id_ed25519.pub "${TARGET_USER}@${TARGET_HOST}:~/.ssh/id_ed25519.pub"
```

(Working directly in the console instead? Generate a key there with
`ssh-keygen` and add the public key to GitHub, or `scp` as above over the
VM's IP.)

**VM** — set permissions and verify GitHub access:

```sh
chmod 600 ~/.ssh/id_ed25519
ssh -T git@github.com   # expect: "Hi <user>! You've successfully authenticated"
```

**VM** — load the key into the agent:

```sh
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

**VM** — then build:

```sh
sudo scripts/bare-metal-build.sh
```

---

## Step 6: VM — Smoke Test

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

All commands below run on the **VM**.

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

## Migrating A VM Set Up Before The Repo Rename

This repo was renamed from `dome-docker` to `provision_dome`. A VM
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

Verify in a **new** shell or SSH session:

```sh
echo "$ROS_DISTRO"          # expect: kilted
ros2 pkg list | grep -c dome
```

`cp` overwrites wholesale, matching what `bare-metal-build.sh` does. If you
hand-edited `~/.bashrc` on this VM, diff it first — the repo path should be
the only difference.

---

## Troubleshooting

All commands below run on the **VM** unless noted.

**New shells fail with `/opt/ros//setup.bash: No such file or directory`**
(note the empty path segment) — `~/.bashrc` points at a directory that no
longer exists, almost always because this VM predates the `dome-docker` →
`provision_dome` rename. See *Migrating A VM Set Up Before The Repo Rename*
above.

**`bare-metal-base.sh` fails on apt-get** — network issue or stale cache:
```sh
sudo apt-get update
sudo scripts/bare-metal-base.sh
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

**`install: invalid target '/boot/firmware/overlays/...'`** — `DOME_TARGET=vm`
missing from `manifest/user.txt` (Step 2). Add it, then rerun the failing script.
