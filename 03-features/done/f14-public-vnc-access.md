# Feature description for feature F14

## F14 — per-VM VNC access mode: public-password vs key-tunnel

**Priority**: Medium

**Done:** yes

**Tasks File Created:** yes

**Tests Written:** yes

**Test Passing:** yes

**Description**:

Give a cloud dev host **one** VNC access model, chosen per box, and make the
public one reachable by anyone with the URL — no operator Mac in the loop. A
single controllable TigerVNC desktop either way; the modes differ only in
*who can reach it and how*.

### The two modes (mutually exclusive per VM)

- **`public`** — TigerVNC on `:1`, bridged by websockify to `0.0.0.0:<port>`,
  with the firewall port open and a **VNC password**. Person X opens
  `http://<public-ip>:<port>/vnc.html`, enters the password, and gets a
  **controllable** desktop. Understood blast radius: whoever has the password
  can do anything **on that box**, and only that box. No SSH, no tunnel, no
  Mac.

- **`tunnel`** — no public VNC port. We add Person X's **SSH public key** to
  the box; they reach the loopback desktop directly over `ssh -L` (today's
  `scripts/start-desktop.sh` path). Access is gated by their key.

A box is provisioned as one or the other. Never both at once.

### Why

The current temporary public test (`make vnc-up`) was built for two
simultaneous feeds — a passwordless view-only mirror **and** a
password-protected control mirror — which is why it layers **`x11vnc`** on top
of TigerVNC and opens **two** ports (48210/48211). We do not need two feeds:
one controllable desktop is enough. Dropping the dual-mirror design removes
`x11vnc` (never in the manifest — a live gap), the second port, and most of the
`vnc-up`/`vnc-down` complexity.

The public test is also **Mac-orchestrated**: `make vnc-up` SSHes in to start
the services and flips a temporary Terraform flag to open the ports. The goal
here is that a viewer needs **only the URL** — so `public` mode serves on boot
and its port is open in steady state, not behind an operator command.

### Scope

- **Single TigerVNC server** for both modes; **remove `x11vnc`** and the
  two-mirror machinery from `make vnc-up`.

- **One public port** (drop the second; pick one canonical port — a task
  decision).

- **A per-VM mode selector.** A manifest/config flag (e.g.
  `DOME_VNC_ACCESS=public|tunnel|none`) that both the box (which service to
  run) and Terraform (whether to open the port) can read. The split between
  box-side config and Terraform is an open question below.

- **`public` mode serves on boot** — a systemd unit runs TigerVNC + websockify
  on `0.0.0.0:<port>` at startup, so the URL works whenever the box is powered
  on. Password comes from `~/.vnc/passwd` (set once with `vncpasswd`).

- **`tunnel` mode** keeps `start-desktop.sh` (loopback only) and opens no port.

- **Desktop app completeness.** `[apt-desktop]` must yield a *usable* desktop:
  the `xfce4` metapackage does not guarantee a terminal emulator (a fresh box
  errors `Failed to execute default Terminal Emulator / Input/output error`).
  Add a terminal and the agreed application set (list below) so no hand-install
  is needed.

### Applications on the desktop — decided (2026-09-25)

Added to `manifest/packages.txt` `[apt-desktop]` so a `vnc` desktop is usable
on arrival:

- **Terminals:** `xfce4-terminal` (the missing piece found live) and
  `terminator`.
- **Editors:** `mousepad` (light GUI). VS Code (`code`) is already provisioned
  via `manifest/apt-repos.txt` — kept, not re-added here.
- **Browser:** `firefox` — Foxglove web app and docs.
- **Files/utilities:** `thunar`, `xfce4-taskmanager`, `xfce4-screenshooter`,
  `htop`.

**Not this pass:** ROS GUI tools (`rqt`/`plotjuggler`) and media viewers
(`ristretto`/`evince`) — deferred; `rviz2` already ships with ROS.

**"notepad" resolved (2026-09-25):** `mousepad` covers it; `notepadqq` not
added. App list is final.

### Live validation (2026-09-25)

A hand-run preview of `public` mode (single TigerVNC + one websockify on
`0.0.0.0:48210`, VNC password, **no `x11vnc`**) was stood up on the live OCI
box and reached from a browser over the public internet. **Performance on
llvmpipe to Ashburn: usable ("feels ok").** Two gaps surfaced and are folded
in: `xfce4-terminal` missing from the manifest, and this box predating
`tigervnc-tools` (`a218d0f`) so the password binary was absent until installed
by hand.

### Out of scope

- Joining the robot's ROS graph (F08). This is desktop access only.
- Per-viewer sessions / multi-seat. `public` mode is a single shared `:1`
  session; concurrent viewers share one desktop and its control.
- TLS / HTTPS on the noVNC endpoint. Plain `http://` for now; note it in
  Known Limitations. (A reverse proxy is a later feature if wanted.)

### Open questions (resolve before tasks)

- **Where the mode lives, and the box/Terraform split.** The box needs it to
  decide which service to run; Terraform needs it to decide whether to open the
  port. Options: a single Terraform var that also writes the box config, or a
  manifest flag plus a matching Terraform var the operator sets once. Avoid a
  split-brain where the port is open but nothing serves it (or vice versa).

- **The canonical public port.** Reuse `48210`, or pick a cleaner single port.
  Whatever it is, only *one* opens.

- **Steady-state firewall vs. the existing `vnc_test` flag.** In `public` mode
  the port is open in normal operation; does `vnc_test` go away, or become the
  `public`-mode signal?

- **Password provisioning.** `~/.vnc/passwd` is set by hand today. Should
  first-boot/`bare-metal-base.sh` prompt or accept a password for `public`
  mode, or stay a manual `vncpasswd` step documented in the guide?

- **Do `make vnc-up`/`vnc-down` survive** as manual overrides once `public`
  mode serves on boot, or are they removed in favor of the service?

## How to Demo

**Setup**: a cloud box provisioned in `public` mode with a VNC password set,
powered on. A second box (or the same one reprovisioned) in `tunnel` mode with
a tester's public key added.

**Steps**:

1. From a machine that is **not** the operator's Mac, open
   `http://<public-ip>:<port>/vnc.html` on the `public` box.
2. Enter the VNC password; move a window / open a terminal on the desktop.
3. On the `tunnel` box, confirm `http://<public-ip>:<port>/vnc.html` does **not**
   connect (no open port), and that the keyed tester reaches the desktop over
   `ssh -L`.

**Expected output**: step 1–2 — a controllable desktop in the browser, no Mac
and no SSH involved; step 3 — the public URL is refused on the `tunnel` box,
and only key + tunnel gets in. `x11vnc` is installed nowhere; only one port is
ever open on the `public` box.
