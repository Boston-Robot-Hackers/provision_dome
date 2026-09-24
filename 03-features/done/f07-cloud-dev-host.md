# Feature description for feature F07

## F07 — Cloud host as a remote ROS 2 development box

**Priority**: Medium
**Done:** yes
**Tasks File Created:** yes
**Tests Written:** yes
**Test Passing:** yes
**Description**: Provision a rented cloud VM as a self-contained ROS 2
development host, with as little hand work as possible, reachable from the
Mac over SSH. Visualization is via Foxglove or an optional browser desktop,
both reached through an SSH tunnel.

Joining the robot's ROS graph is **out of scope** — that is F08.

## Why this is mostly already built

Every Pi-specific gate in `host-setup.sh`, `bare-metal-base.sh`, and
`bare-metal-build.sh` tests `== "pi"`, so any other `DOME_TARGET` already
takes the non-Pi path. The ROS and third-party apt repos resolve
architecture with `dpkg --print-architecture`. A stock Ubuntu 24.04 cloud
image runs the existing scripts nearly unchanged.

*Nearly* is the point of this feature. The existing guide assumes a local
VM whose installer created your user and whose disk you trust. A cloud host
breaks those assumptions in three concrete places — see below.

## What breaks on a cloud host today

- **Wrong login user, wrong repo location.** Cloud images log you in as
  `root` (DigitalOcean) or `ubuntu` (OCI), not as `DOME_USER`. Following
  `vm-howto.md` clones into that user's home, but `manifest/bashrc:1`
  hardcodes `~/provision_dome` *in `DOME_USER`'s home*. Result: empty
  `ROS_DISTRO` and `/opt/ros//setup.bash` in every new shell.

- **New user is unreachable.** `host-setup.sh:57` runs an interactive
  `adduser` and never installs `authorized_keys`. Cloud images disable
  password SSH, so you cannot log in as the user just created.

- **No swap.** `bare-metal-base.sh:35` creates swap only for `pi`. Small
  cloud shapes have no swap by default, so `colcon build` can OOM.

A fourth issue is not a breakage but a risk: `vm-howto.md` Step 5 copies
your personal GitHub private key onto the host. Acceptable on a laptop VM;
**not on an internet-facing box**.

## Scope

**Decision — `DOME_TARGET=cloud` is a new value, distinct from `vm`.** Per
the user, even though the two overlap. It now carries real behavior:
swap is enabled for `cloud` as for `pi`. Everything else about `cloud`
follows the non-Pi path unchanged.

**Decision — cloud-init owns first boot.** A user-data template, pasted into
the provider's "create instance" form, creates `DOME_USER` with your SSH
public key and passwordless sudo, clones `provision_dome` into
`/home/<DOME_USER>/`, writes `manifest/user.txt`, and runs `host-setup.sh`
and `bare-metal-base.sh` unattended. This fixes the login-user, repo-location,
and unreachable-user problems **without changing `host-setup.sh`'s user
logic** — the existing `id "${USERNAME}"` check simply finds the user
already present. It is also the "simplify provisioning" win: the operator
pastes one file, waits, and SSHes in as themselves.

`bare-metal-build.sh` is **not** run by cloud-init, because it needs GitHub
credentials for private repos and those must not be baked into user-data.

**Decision — a host-specific GitHub key, never your personal one.** The
guide has you generate a key *on the cloud host*, add it to GitHub, and
revoke it when the box is destroyed. Doc-only; no script change.

**Decision — access is by SSH tunnel; no Tailscale in F07.** Everything
listens on `127.0.0.1` only and is reached with `ssh -L`. Same security
model as a VPN-bound listener, with nothing extra to install or
authenticate. Tailscale becomes necessary only for F08.

**Decision — Foxglove first, desktop optional.** `foxglove-bridge` is
already in `manifest/packages.txt` `[ros]` and needs no GUI stack, so
`ssh -L 8765:localhost:8765` plus Foxglove on the Mac is the primary
visualization path. The noVNC desktop (`DOME_DESKTOP=vnc`) is kept for
tools that need a real X display, like `rviz2`, but is off by default.

**Decision — arm64 on OCI A1.** F07 targets arm64, the Pi's architecture,
so the build validated on the cloud host is the one the robot runs and
arm-only build failures surface before the Pi hits them. The code stays
arch-neutral — nothing in the native path is arm64-only, and
`manifest/bashrc:4`'s `aarch64` library path is harmless on x86 — so a
fallback to an x86_64 provider needs no code change. TF07.0 runs on arm64.

**Decision — single user.** Unchanged from the original spec.

**Decision — no systemd unit for the desktop in v1.** Started by script;
revisit if missed.

## Add

- `cloud` in the `DOME_TARGET` comment in `manifest/config.txt`.
- Swap for `DOME_TARGET=cloud` in `bare-metal-base.sh`; update the
  `SWAP_SIZE_MB` comment, which currently says Pi-only.
- `host-setup.sh:151` prints the actual `DOME_TARGET` instead of the
  hardcoded string `DOME_TARGET=vm`.
- `host-file-templates/cloud/user-data.template` — the first-boot template,
  following the existing Pi template
  (`host-file-templates/boot/firmware/user-data.template`): same
  `REPLACE_WITH_...` placeholder convention, here for `DOME_USER` and the
  SSH public key.
- `DOME_DESKTOP=none|vnc` in `manifest/config.txt` (default `none`) and an
  `[apt-desktop]` section in `manifest/packages.txt` (`xfce4`,
  `tigervnc-standalone-server`, `novnc`, `websockify`, `dbus-x11`),
  installed by `bare-metal-base.sh` only when the value is exactly `vnc`.
- `scripts/start-desktop.sh` — starts TigerVNC with `-localhost yes` and
  websockify bound to `127.0.0.1`. **Both** listeners must be loopback-only;
  constraining only websockify would leave raw VNC on port 5901 public.
- `02-doc/cloud-howto.md` — the self-contained guide.

## Do not change

- `Dockerfile`, `Dockerfile.base`, `compose/` — native-only feature.
- `host-setup.sh`'s user-creation logic — cloud-init makes it a no-op.
- `DOME_TARGET=pi` and `DOME_TARGET=vm` behavior, and `DOME_MODE`.
- `manifest/bashrc` — no DDS or networking settings; that is F08.

## Provider choice — OCI A1 (arm64)

**Decision: F07 targets Oracle Cloud (OCI) A1 Ampere — arm64,
pay-as-you-go, stopped between sessions** (about $0 for occasional use).
arm64 is the Pi's architecture, so the build validated here is the one the
robot runs; the cost is OCI's fiddly console and occasional A1 capacity
shortages. Pricing and the alternatives are in `02-doc/notes.md`, *Dev host
options*.

**This is a working assumption — if OCI doesn't work out** (capacity,
console, billing), the fallbacks are recorded in `notes.md`: DigitalOcean
(x86_64, simplest console) or a refurbished mini PC on the robot's home
network (plain Scenario 2 via `vm-howto.md`, and it joins the robot's graph
without F08). Revisit then. The provisioning code (`DOME_TARGET=cloud`,
swap, the cloud-init template) is architecture- and provider-neutral, so a
switch is a docs change, not a code rewrite.

Scripted `up`/`down` (OCI stop/start) is a likely later addition to scope.

**OCI runbook:** `02-doc/oci-howto.md` provisions the A1 instance and is how
you run TF07.0. Once TF07.0 validates the breakages, that runbook adopts
F07's cloud-init flow and `DOME_TARGET=cloud`, and folds into
`cloud-howto.md` (TF07.6).

## Known limitations

- **No hardware.** No camera, lidar, ESP32, or GPIO.
- **Software GL only.** `rviz2` on llvmpipe is usable; Gazebo is not
  pleasant. Prefer Foxglove.
- **Self-contained graph.** The cloud host's ROS graph does not see the
  robot's until F08.
- **cloud-init failures are quiet.** Errors land in
  `/var/log/cloud-init-output.log`, not on your terminal; the guide must
  say to check `cloud-init status --wait` before continuing.

## How to Demo

**Setup**: A DigitalOcean or OCI account; your SSH public key; a filled-in
copy of `host-file-templates/cloud/user-data.template` with `DOME_USER` and
the key.

**Steps**:

1. Create an Ubuntu 24.04 instance, pasting the user-data into the
   provider's cloud-init / user-data field.
2. `ssh <DOME_USER>@<public-ip>` → logs in as `DOME_USER` directly, no
   password prompt.
3. `cloud-init status --wait` → `status: done`; `swapon --show` lists
   `/swapfile`.
4. Generate a host GitHub key, add it to GitHub, then
   `sudo scripts/bare-metal-build.sh` from `~/provision_dome`.
5. New shell: `echo "$ROS_DISTRO"` → `kilted`;
   `ros2 pkg list | grep dome` lists workspace packages.
6. Run `foxglove_bridge`; on the Mac,
   `ssh -L 8765:localhost:8765 <DOME_USER>@<public-ip>` and connect
   Foxglove to `ws://localhost:8765` → topics visible.
7. Optional desktop: with `DOME_DESKTOP=vnc`, run
   `scripts/start-desktop.sh`, tunnel `-L 6080:localhost:6080`, browse to
   `http://localhost:6080` → xfce desktop; `rviz2` renders.
8. Control: from the Mac, `nc -z <public-ip> 5901` and
   `nc -z <public-ip> 6080` → both refused.

**Expected output**: a user-reachable ROS 2 workspace on a cloud host with
one paste and one build command; visualization over SSH only; no desktop
or VNC port reachable from the internet; no personal key on the host.
