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

- A **dedicated SSH keypair for this box** — not your everyday one:

  ```sh
  ssh-keygen -t ed25519 -f ~/.ssh/id_dome_cloud -C dome-cloud-1
  ```

  Only the public half ever leaves your Mac. Your `~/.ssh/id_ed25519` is
  simultaneously your GitHub key and your robot key, so giving the box an
  identity of its own means a compromised box cannot sign as you. Point
  `ssh_public_key_path` at `~/.ssh/id_dome_cloud.pub` in
  `terraform/oci/terraform.tfvars`.

  Add a matching block to `~/.ssh/config` on the Mac:

  ```
  Host dome-cloud-1 <public-ip>
      IdentityFile ~/.ssh/id_dome_cloud
      IdentitiesOnly yes
      ForwardAgent no
  ```

  The explicit `ForwardAgent no` matters: a forwarded agent is a signing
  oracle, and a bare `Host *` block that ever gains `ForwardAgent yes` would
  otherwise reach this box too.

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

The template writes `manifest/user.txt` with `DOME_USER`,
**`DOME_TARGET=cloud`** and **`DOME_CLONE_OVERRIDE=PUBLIC_ONLY`**, so first
boot takes the non-Pi path, enables swap, and will clone **public repos
only**. It does **not** run `bare-metal-build.sh` and contains **no
credential** — the build is run by hand in Step 4, and needs no GitHub key.

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

**Pin the key.** If your Mac's `~/.ssh/config` has a broad `Host *` block
with its own `IdentityFile`, plain `ssh` can offer the wrong key and fail with
`Permission denied (publickey)`. Name the key explicitly:

```sh
ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes <DOME_USER>@<public-ip>
```

Use the private key that matches the public key you gave the instance. The
same flags apply to the tunnel commands below.

---

## Step 4: Build

This host is on the public internet, so by default it holds **no GitHub key**
and never clones your private repos: `DOME_CLONE_OVERRIDE=PUBLIC_ONLY` makes
the build skip every repo marked `PRIVATE_REPO`. Build the workspace:

```sh
cd ~/provision_dome
sudo scripts/bare-metal-build.sh
```

From the repo root, `make build` is a shortcut for this command.

The workspace then contains only the public packages, so the private `dome*`
packages will not be present.

### The rules for this box

The box is **expendable** — losing it should cost only itself. That premise is
not a property of the machine; it is a property of what you put on it, and it
stops being true the moment you log into something. So:

- **No interactive credential login on a `public`-mode box.** No `claude`
  login, no `gh auth login`, no secret-manager login of any kind. Each writes a
  live token to disk on a machine reachable from the internet.

- **Check, don't remember.** From your Mac:

  ```sh
  make -C terraform/oci audit
  ```

  It fails if the box holds a Claude or `gh` token, `.git-credentials`, or any
  private key. Run it before you arm the desktop.

- **`ubuntu ALL=(ALL) NOPASSWD:ALL` is deliberate**, not an oversight. Under
  "the box is expendable" a passwordless sudo costs nothing extra — an attacker
  who reaches the desktop already has the session. It is recorded here so it
  stays a decision.

- **`fail2ban` is deliberately not installed.** For key-only SSH it adds
  nothing, and there is no stock filter for websockify or VNC, so guarding
  48210 with it would mean authoring one. Restricting that port to your own
  address (`make vnc-up`) removes the internet from it outright, which is
  strictly better.

### Optional: a private cloud dev box

If this is **your own** box and you want the private repos, opt in
deliberately: remove `DOME_CLONE_OVERRIDE` from `manifest/user.txt` and give
the box a credential that can only read.

**Use a read-only deploy key, scoped to one repository** — github.com → the
repo → Settings → Deploy keys, with *Allow write access* left **off**:

```sh
ssh-keygen -t ed25519 -C "cloud-dome" -f ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub     # add as a deploy key on the one repo that needs it
```

It must belong to the user that runs the build (`<DOME_USER>`) under the
default name `~/.ssh/id_ed25519`; `bare-metal-build.sh` clones as that user, so
a key elsewhere fails at the first clone with `Permission denied (publickey)`.

**Never an account key.** An account key can push to every repo you can, and
the robot *executes what those repos serve* at its next build — so a box
compromise would reach the robot by way of git, without ever needing a route to
it. A deploy key without write access cannot do that. One key per repo is the
cost; revocation granularity is the payoff.

---

## Step 5: Smoke Test

`bare-metal-build.sh` installed `manifest/bashrc` as `~/.bashrc`. Open a
**new** SSH session:

```sh
echo "$ROS_DISTRO"            # kilted
ros2 pkg list | grep -E 'better_launch|micro_ros'
```

With the default `PUBLIC_ONLY` setup those public packages are what you get.
On the optional private setup, `ros2 pkg list | grep dome` lists the `dome*`
packages too.

Because `rosutils` (which normally sets up your shell) is a private repo, a
`PUBLIC_ONLY` host does not have it. `~/.bashrc` then sources the ROS install
and your workspace directly.

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

For tools needing a real X display, install the xfce desktop by setting
`DOME_DESKTOP=vnc` and re-running the base setup:

```sh
printf 'DOME_DESKTOP=vnc\n' >> manifest/user.txt
sudo scripts/bare-metal-base.sh
```

Then choose **one** access mode per box with `DOME_VNC_ACCESS` (F14). It is a
single controllable TigerVNC desktop either way — the modes differ only in who
can reach it and how.

### Mode A — `tunnel` (key-gated, private)

Loopback only, reached over an SSH tunnel by a user whose key is on the box.
Nothing is exposed to the internet.

```sh
printf 'DOME_VNC_ACCESS=tunnel\n' >> manifest/user.txt
sudo scripts/bare-metal-base.sh          # installs + enables dome-vnc.service
```

From your Mac:

```sh
ssh -L 6080:localhost:6080 <DOME_USER>@<public-ip>
```

Then browse `http://localhost:6080`. (`make desktop` on the box runs the same
server in the foreground if you would rather not use the service.)

### Mode B — `public` (URL + VNC password)

A controllable desktop anyone can reach at a URL, protected by a VNC password.
Understood trade-off: whoever has the URL and password controls **that box**
(and only that box).

```sh
printf 'DOME_VNC_ACCESS=public\n' >> manifest/user.txt
sudo scripts/bare-metal-base.sh          # installs the units; does NOT enable them
vncpasswd                                # set the VNC password once
```

**The VNC password is silently truncated to 8 characters** by the protocol, so
a long passphrase buys you nothing. Pick 8 random characters and treat them as
the whole of the secret.

Arm it from your Mac with `make -C terraform/oci vnc-up`. That opens the OCI
edge **to your own address only** and starts the desktop; the units are not
enabled at boot, so a reboot leaves the box closed until you arm it again.

```
https://<public-ip>:48210/vnc.html?autoconnect=true
```

The certificate is self-signed, so **the browser will warn on the first
visit** — expected. What it buys is that the session is encrypted: without it,
the screen, every keystroke, and the crackable VNC challenge-response all cross
the internet in the clear.

If your address changes, re-run `vnc-up`, or pass a range:
`make -C terraform/oci vnc-up CIDR=1.2.3.0/24`.

Close it again with `make -C terraform/oci vnc-down`, which stops the service
and re-applies the SSH-only security list. **`make stop` now does this for
you** — stopped means disarmed.

#### Treat that browser tab as hostile

The desktop is served by a machine you have decided is expendable, which means
its noVNC page is untrusted JavaScript running in *your* browser.

- Open it in a **separate browser profile with no signed-in sessions.**
- **Never type Mac, GitHub, or any other credential** into anything that page
  shows you.
- Keep **XQuartz off the Mac.** It is absent today, which is what makes
  `ssh -X` to this box a non-issue; the box's sshd also sets
  `X11Forwarding no`.

**Software GL only.** `rviz2` on llvmpipe is usable; Gazebo is not pleasant.
Prefer Foxglove.

---

## Step 8: Teardown

- **Destroy the instance** in the provider console (on OCI, *terminate* — a
  stopped instance can still incur storage cost; see `oci-howto.md` Step 9
  for the stop-vs-terminate distinction).

- **If you used the optional private setup,** revoke the `cloud-dome` key at
  github.com → Settings → SSH keys. With the default `PUBLIC_ONLY` there is
  no key to revoke.

---

## Known Limitations

- **No hardware.** No camera, lidar, ESP32, or GPIO.

- **Software GL only.** See Step 7.

- **Self-contained graph.** This host's ROS graph does not see the robot's.
  Joining the robot's graph over Tailscale is **F08**
  (`03-features/notdone/f08-remote-ros-graph.md`).
