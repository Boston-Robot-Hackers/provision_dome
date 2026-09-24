# Cloud Howto: Rented Cloud VM to Native ROS

Scenario 4 (see `02-doc/howto.md`) — provision a rented cloud VM as a
self-contained ROS 2 development host, reachable from your Mac over SSH.

The whole point is **as little hand work as possible**: you paste one
cloud-init file into the provider's create-instance form, wait, then SSH in
as yourself and run a single build command. First boot creates your user,
clones the repo, and runs the base setup unattended.

**Joining the robot's ROS graph is out of scope** — that is F08. This host's
ROS graph is self-contained.

---

## Prerequisites

- A **DigitalOcean or Oracle Cloud (OCI)** account. Provider trade-offs and
  pricing are in `02-doc/notes.md`, *Dev host options* — this guide does not
  duplicate them.

- Your SSH **public** key (`~/.ssh/id_ed25519.pub`). Only the public half
  ever leaves your Mac.

- An **Ubuntu 24.04 (noble)** image. A different release fails partway
  through `bare-metal-base.sh` with cryptic apt errors, not a clear "wrong
  OS" message.

**arm64 or x86_64 both work.** Prefer **arm64** when the price is
comparable — it catches arm-only build failures before the Pi does.

---

## Step 1: Fill In The Cloud-Init Template

Copy `host-file-templates/cloud/user-data.template` and replace the two
placeholders:

- `REPLACE_WITH_HOST_USER` — the login user to create (e.g. `pitosalas`).
- `REPLACE_WITH_SSH_PUBLIC_KEY` — the full contents of
  `~/.ssh/id_ed25519.pub`.

The template writes `manifest/user.txt` with `DOME_USER` and
**`DOME_TARGET=cloud`**, so first boot takes the non-Pi path and enables
swap. It does **not** run `bare-metal-build.sh` and contains **no
credential** — that step needs GitHub access and is done by hand in Step 4.

---

## Step 2: Create The Instance

Create an Ubuntu 24.04 instance on your chosen provider and architecture.
Paste the filled-in template into the provider's **user data** / cloud-init
field.

- **DigitalOcean:** the "Add Initialization scripts (free)" box on the
  droplet create page.
- **OCI:** *Advanced options → Management → cloud-init script*. For OCI,
  `02-doc/oci-howto.md` covers account, VCN, and capacity details.

Keep inbound firewall to **SSH (port 22) only**. Everything else is reached
over SSH tunnels.

---

## Step 3: First Login And Verify Provisioning

cloud-init runs first boot **unattended and quietly** — its output goes to
`/var/log/cloud-init-output.log`, not your terminal. Always confirm it
finished before continuing:

```sh
ssh <DOME_USER>@<public-ip>     # logs in directly, no password prompt
cloud-init status --wait        # wait for: status: done
swapon --show                   # lists /swapfile
```

If `cloud-init status` reports `error`, read
`/var/log/cloud-init-output.log` to see which step failed.

---

## Step 4: GitHub Key And Build

**Generate a host-specific GitHub key on the cloud host. Do NOT copy your
personal key here** — this box is on the public internet.

```sh
ssh-keygen -t ed25519 -C "cloud-dome" -f ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub     # add at github.com → Settings → SSH keys, named "cloud-dome"
ssh -T git@github.com         # expect "Hi <you>!"
```

Then build the workspace:

```sh
cd ~/provision_dome
sudo scripts/bare-metal-build.sh
```

---

## Step 5: Smoke Test

`bare-metal-build.sh` installed `manifest/bashrc` as `~/.bashrc`. Open a
**new** SSH session:

```sh
echo "$ROS_DISTRO"            # kilted
ros2 pkg list | grep dome
```

---

## Step 6: Visualize With Foxglove

`foxglove-bridge` is already installed and needs no GUI. No ports are
opened — everything goes through an SSH tunnel. On the Mac:

```sh
ssh -L 8765:localhost:8765 <DOME_USER>@<public-ip>
```

In that session, on the host:

```sh
ros2 launch foxglove_bridge foxglove_bridge_launch.xml
```

Connect the Foxglove app on the Mac to `ws://localhost:8765`.

---

## Step 7: Optional Desktop (rviz2)

For tools needing a real X display, install the desktop by setting
`DOME_DESKTOP=vnc` and re-running the base setup:

```sh
printf 'DOME_DESKTOP=vnc\n' >> manifest/user.txt
sudo scripts/bare-metal-base.sh
scripts/start-desktop.sh
```

`start-desktop.sh` binds **both** the VNC server and websockify to loopback
only. Reach it over an SSH tunnel:

```sh
ssh -L 6080:localhost:6080 <DOME_USER>@<public-ip>
```

Then browse to `http://localhost:6080`.

**Software GL only.** `rviz2` on llvmpipe is usable; Gazebo is not pleasant.
Prefer Foxglove.

---

## Step 8: Teardown

- **Destroy the instance** in the provider console (on OCI, *terminate* — a
  stopped instance can still incur storage cost; see `oci-howto.md` Step 9
  for the stop-vs-terminate distinction).

- **Revoke the `cloud-dome` key** at github.com → Settings → SSH keys.

---

## Known Limitations

- **No hardware.** No camera, lidar, ESP32, or GPIO.

- **Software GL only.** See Step 7.

- **Self-contained graph.** This host's ROS graph does not see the robot's.
  Joining the robot's graph over Tailscale is **F08**
  (`03-features/notdone/f08-remote-ros-graph.md`).
