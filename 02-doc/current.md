# Current Status

**Date:** 2026-09-25

Full session-by-session log lives in `02-doc/history.md`. This file holds
only current status and open items.

## Status

F02, F03, F04, F05 all complete.

- **F06** (macOS Docker dev) — spec'd, **no tasks yet**.
- **F07** (cloud dev host) — **complete (2026-09-24).** OCI A1 (arm64) box
  provisioned via Terraform; smoke test passed (`ROS_DISTRO=kilted`, all 11
  `dome*` packages, swap active). Feature and task files moved to `done/`.
- **F08** (join a remote host to the robot's graph over Tailscale) — new,
  split out of F07. Spec only, with open questions to resolve before tasks.
- **F09** (shared internet-facing server with on-demand wake) — **deferred**
  summary in `03-features/deferred/`. Recorded for memory only; the user
  doubts they'll pursue it.

- **F10** (selectable repo cloning) — **complete (2026-09-24).** `PRIVATE_REPO`
  marker in `repos.txt` plus `DOME_CLONE_OVERRIDE` (unset = clone all,
  `PUBLIC_ONLY`, `NONE`); the cloud-init template sets `PUBLIC_ONLY`, so a cloud
  host needs no GitHub key. Verified live on OCI. Feature and task files in
  `done/`.

- **F13** (box-side dev Makefile) — **complete (2026-09-25).** The repo-root
  `Makefile` is now the on-box dev tool (`build`, `desktop`, `env`, `status`);
  the laptop OCI control plane (`start`/`stop`/`status`/`ip`/`ssh`/`vnc-*`)
  moved to `terraform/oci/Makefile`. Suite green (273 total). Files in `done/`.

- **F15** (contain the cloud box's blast radius) — **implemented 2026-09-26 on
  `f15-blast-radius`, not yet closed.** 14 of 18 tasks done; the per-box key,
  live verification and the child compartment remain (see *Pick up here*).
  Tests written and passing (71 checks).
- **F16** (key custody on the Mac) — new, split out of F15. **Spec only, no
  tasks.** Ranks above F15: two unencrypted crown-jewel private keys.
- **F17** (named repo sets via `REPOS_CONFIG`) — new. Spec **and** tasks
  written (TF17.0–TF17.10); no step started. Replaces `DOME_CLONE_OVERRIDE`.

- **F14** (per-VM VNC access) — **complete (2026-09-25).** One controllable
  TigerVNC desktop, per box either `public` (URL + VNC password, port 48210
  open, served on boot) or `tunnel` (loopback + SSH key). Dropped `x11vnc`
  and the two-mirror design; `DOME_VNC_ACCESS` flag + Terraform `vnc_access`.
  Perf validated live ("feels ok"). Suite 300 green. Files in `done/`.


## ⏭ Pick up here (next session)

**F15 is implemented but not committed**, on a new branch
**`f15-blast-radius`** (off `main`). Suite **367 green, 0 failed** — F15 adds
`tests/test_f15_blast_radius.sh` (71 checks).

Three things remain before F15 closes, all of them needing you rather than
more code:

1. **Generate the per-box key** (TF15.11). `terraform/oci/Makefile` now defaults
   `SSH_KEY` to `~/.ssh/id_dome_cloud`, **which does not exist yet**, so
   `make ssh` and `make audit` stop with a message telling you the `ssh-keygen`
   line. Until you re-key the box, override: `make ssh SSH_KEY=~/.ssh/id_ed25519`.
   Re-keying is by hand — cloud-init reads `ssh_authorized_keys` at first boot,
   so Terraform governs new boxes only. Keep a second session open.
2. **Live verification** (TF15.16) — the box is STOPPED, and the static suite
   cannot prove sshd refuses an agent or that the OCI edge refuses a stranger.
   Steps are in the feature's *How to Demo*.
3. **TF15.14 (child compartment) is deferred** — creating one is a real tenancy
   change, and the plan that would say whether the instance gets replaced needs
   the compartment to exist first. Waiting for the next rebuild, which F11 gates.

**Landed this session (2026-09-26):**

- **F15 spec re-reviewed against the code**, and amended in seven places where
  its recommendations did not survive contact with the tree — most importantly
  that nothing here manages sshd, that Terraform passes **no `user_data`**
  (`compute.tf:13`), and that a branch field cannot hold a commit SHA.
- **Third-party code is pinned and verified** — `mcfly` to a commit with a
  `sha256` that `bare-metal-base.sh` checks *before* executing (no more
  `curl | sh` as root), `rosutils` to a commit. `claude-code` turned out to
  accept `stable|latest|VERSION` and to verify its own payload, so it takes
  `args = stable`.
- **Doppler removed from the project entirely**, per explicit instruction — the
  `[doppler]` apt repo is gone, so the CLI is installed on no target and
  `rosutils`' token hook cannot resolve anything. Stronger than the written
  rule F15 originally proposed.
- **Stopped now means disarmed** — `make stop` depends on `vnc-down`, and the
  VNC units are installed but **no longer enabled at boot**. Arming is always
  `make vnc-up`.
- **The VNC port is no longer open to the internet** — `var.vnc_allowed_cidr`,
  with `vnc-up` passing your own address as a `/32` and *failing* rather than
  widening if it cannot resolve one. Public mode now serves `https://` with a
  self-signed cert.
- **`scripts/box-audit.sh` + `make audit`** fail if the box holds a Claude or
  `gh` token, `.git-credentials`, or any private key.
- **sshd hardening drop-in** (`AllowAgentForwarding no`, `X11Forwarding no`,
  `PermitRootLogin no`), installed on `cloud` targets only, validated with
  `sshd -t` before reload; `rpcbind` masked. `fail2ban` deliberately skipped —
  no stock websockify filter, and the CIDR narrowing supersedes it.

**Known gap, not closed:** the `rosutils` pin only applies to **fresh** clones.
`clone_section` skips existing directories, so the box and the robot stay on
whatever commit they already have. Enforcing a pin on an existing clone changes
the deliberate skip-existing behavior and would need its own feature/task pair.

**Candidates for next:**

- **F16** (key custody on the Mac) — spec only, **no tasks**. Higher priority
  than F15 was: both of the Mac's crown-jewel private keys are unencrypted on
  disk, and `~/.oci/oci_api_key.pem` is the whole tenancy.
- **F17** (named repo sets via `REPOS_CONFIG`) — **tasks written**
  (TF17.0–TF17.10), nothing done. Collides with F15 over `repos.txt` and the
  parser; F15 landing first means TF17.5/TF17.6 must preserve the commit-pin
  field while stripping `PRIVATE_REPO`.
- **F11** (Terraform creates the login user as `DOME_USER`) — tasks
  TF11.0–TF11.5, **awaiting approval**; one open decision (rebuild vs second
  box). Also owns the `DOME_VNC_ACCESS` cloud-init wiring F14 deferred, and now
  gates TF15.14 and any rebuild.
- **F12** (per-mode repo transport) — spec only, open questions.
- **F06** (macOS Docker dev) — spec'd, needs a task list first.
- **F08** (remote ROS graph) — five open questions before tasks. Note F15.1's
  fix is preventive *because* F08 adds the box→robot network leg.
- Open chores in `04-tasks/chores.md`.

### Live box — `dome-cloud-1`, STOPPED but armed for public VNC (2026-09-26)

`129.213.164.184` (arm64, 4 OCPU/24 GB), **STOPPED** as of end of session,
repo at `a6eeb8f`. Re-entry: `make -C terraform/oci start`, then
`make -C terraform/oci ssh`, or `ssh ubuntu@129.213.164.184`.

**Disarmed by hand on 2026-09-26** — `make -C terraform/oci vnc-down` was run,
and the security list now admits **SSH only**.

It needed doing by hand because at the time **`make stop` did not disarm**: it
issued a `SOFTSTOP` and nothing else, leaving `48210` open at the edge and both
VNC units `enabled`, so a later `make start` would silently restore a publicly
reachable desktop.

**Fixed on `f15-blast-radius` (TF15.6/TF15.7):** `stop` now runs the
`vnc_access=none` apply first, and `bare-metal-base.sh` installs the VNC units
without enabling them, so a reboot no longer re-arms the box either. *Stopped
means disarmed.* The advice to run `vnc-down` explicitly is obsolete once that
branch is merged — but **the box itself has not been reprovisioned**, so its
units are still `enabled` on disk until `bare-metal-base.sh` is rerun there.
SSH as `ubuntu` works with the default agent/key — the old `~/.ssh/id_oci` note
is **stale** (`id_oci` isn't on disk and wasn't needed to connect).

**Desktop URL:** `http://129.213.164.184:48210/vnc.html?autoconnect=true`
(VNC password was already set on the box). Verified live: both units `active`,
`Xtigervnc` on `127.0.0.1:5901`, `websockify` on `0.0.0.0:48210`, HTTP **200**
from the laptop.

It was reprovisioned **in place** — not rebuilt. A `terraform destroy`/`apply`
would have been a *regression*: `user-data.template:36` clones the GitHub
**default branch**, which does not have F13/F14, and the template writes
neither `DOME_DESKTOP` nor `DOME_VNC_ACCESS`. Rebuilding only becomes sane once
F11 teaches cloud-init the branch and those two vars.

Both `dome-vnc.service` and `dome-vnc-firewall.service` are **enabled**, so the
desktop returns on reboot. Close it with `make -C terraform/oci vnc-down`
(stops the services *and* re-applies the SSH-only security list). Port 48210 is
open to the internet with only a VNC password in front of a fully controlling
desktop — the documented `public`-mode trade-off; don't leave it up idle.

Two discrepancies found on the box while doing this:

- **`DOME_TARGET=vm`, not `cloud`** as this file previously claimed. Harmless
  in practice — swap (4G `/swapfile`) is active, and swap was the only thing
  `cloud` gated. **Left as-is** rather than silently "corrected"; reconcile
  under F11.
- **`manifest/user.txt` had `DOME_DESKTOP=vnc` twice**, which parses as
  `vncvnc` and would have made `bare-metal-base.sh` skip every `[apt-desktop]`
  package while still exiting 0. Box file rewritten; the parser bug is logged
  as a chore and is **not yet fixed**.

The `terraform/oci/Makefile` wraps start/stop/status/ssh/vnc-*; the repo-root
`Makefile` holds box-side dev targets (`make build`/`desktop`/`env`/`status`).

Decision on record: **stay on OCI A1 Always Free + Terraform** (price is the top
priority; Terraform removed the console friction). Desk mini PC stays a
"someday" idea. Follow-up: make the login username a Terraform variable
(TF07.10, not yet written — see `notes.md`).

**Money:** stop the box between sessions —
`oci compute instance action --instance-id <ocid> --action SOFTSTOP`
(the IP survives stop/start).

**Open mood/decision:** user is fed up with OCI ("sort of hate oci") — but
also says **price is a top priority**, and on price OCI A1 Always Free
(~$0, arm64) wins outright (AWS Graviton and DigitalOcean both cost real
money; DO is x86 anyway; a desk box is $300 up front). So the reason to
leave OCI is frustration, not cost — and **Terraform removes the
frustration while keeping the $0 price**. Plan: **stay on OCI A1 Always Free
+ Terraform.** Desk mini PC stays a "someday on the robot's network" idea,
not a cost play. All friction is logged, so a pivot wastes nothing.

---

### Done — F10, selectable repo cloning

`03-features/done/f10-selectable-repo-cloning.md`, tasks in
`04-tasks/done/TF10-selectable-repo-cloning.md`; tests in
`tests/test_f10_repo_cloning.sh` (47 checks, suite green).

- Task order was amended: the parser (TF10.2) had to land *before* the markers
  (TF10.0), because the old parser read `PRIVATE_REPO` as a git branch. The
  `Dockerfile` has its own `clone_section` and got the same parser change.
- **Live check found a gap:** `manifest/bashrc` sourced the private `rosutils`,
  so under `PUBLIC_ONLY` a new shell had no `ros2`. Fixed: `bashrc` sources
  `rosutils` only if present, else the ROS underlay and workspace overlay.
  Verified on OCI with a throwaway user: build succeeded, `ros2` works.
- Not covered: the Docker image itself was not rebuilt (static test only), and
  `oci-howto.md` still shows the GitHub-key step for its manual `vm`-target path.

### Done — F13, box-side dev Makefile

`03-features/done/f13-box-dev-makefile.md`, tasks in
`04-tasks/done/TF13-box-dev-makefile.md`; tests in
`tests/test_f13_makefiles.sh` (33 checks, suite green).

The root `Makefile` shipped to the box via the full-repo clone, but its
targets are laptop-only (need the `oci` CLI and Terraform state) — on the box
they were inert or wrong. **Split (option A):** root `Makefile` = box dev
targets; `terraform/oci/Makefile` = the OCI control plane, run with
`make -C terraform/oci <target>`. Side benefit: the control Makefile now sits
with the Terraform state it reads, so `make ip` no longer depends on being in
the repo root. Docs updated (`cloud-howto.md`, `current.md`, F11 spec).

### Done — F14, per-VM VNC access

`03-features/done/f14-public-vnc-access.md`, tasks in
`04-tasks/done/TF14-public-vnc-access.md`; tests in
`tests/test_f14_vnc_access.sh` (27 checks). A box picks one desktop mode via
`DOME_VNC_ACCESS`: **`public`** (single TigerVNC → websockify `0.0.0.0:48210`,
VNC password, `dome-vnc.service` + `dome-vnc-firewall.service` on boot,
Terraform `vnc_access=public` opens the one port) or **`tunnel`** (loopback,
reached over `ssh -L`; key-gated). No `x11vnc`, no second port. `[apt-desktop]`
gained a terminal (`xfce4-terminal`, `terminator`) + `mousepad`/`firefox`/
`thunar`/utilities so the desktop is usable on arrival. `make -C terraform/oci
vnc-up`/`vnc-down` kept as manual overrides.

Single-source-of-truth (Terraform writing the box's `DOME_VNC_ACCESS` via
cloud-init) is intentionally **deferred to F11**, which owns Terraform↔cloud-init.

### Housekeeping (2026-09-24)

- Deleted the stray `fakehome/` directory (held only a 17-byte
  `.statusline-usage.tsv` cache, untracked).
- Many changes on `feature/f07-cloud-dev-host` are still uncommitted
  (Terraform, `Makefile`, `cloud-howto.md`, `start-desktop.sh`, F10 files).

---

### Earlier context (pre-2026-09-23 session)

This section was an analysis pass over the Pi (Scenario 1) build path, with
one fix landed and one new feature spec'd.

### Fixed — `dome_telemetry` was never being cloned

`dome_telemetry` was missing from `manifest/repos.txt`, so it was never
cloned or built on any target. Added to `[ros_ws]` in `bc89c6f`.

It failed *silently*, which is why it survived: the only reference to the
package is a runtime `bl.include("dome_telemetry", "robot.launch.py")` in
`dome2/launch/gendrv.launch.py`, not a `package.xml` dependency. So
`rosdep install` saw no missing key and `colcon build` exited 0 on a Pi that
was missing the package — it only broke at launch time.

Not to be confused with `dome_telemetry_msgs`, which lives inside the
already-cloned `dome_vision` repo and resolves fine. That is what
`dome_control` and `dome_vision_ros` actually depend on.

### Investigated, no change needed — Docker on a native Pi

Reported symptom: a `DOME_MODE=native` Pi starts a Docker service at boot.

Audited every `apt-get` and `systemctl` call across `host-setup.sh`,
`bare-metal-base.sh`, and `bare-metal-build.sh`. All four Docker touchpoints
in `host-setup.sh` are correctly gated behind `DOME_MODE == "docker"`
(blocks `67`→`87` and `154`→`184`); there are **no ungated `systemctl
enable`/`start` calls anywhere in the repo**; and the manifest package lists
contain no `docker`/`containerd`/`compose`. Cloud-init installs only
`avahi-daemon`, `ca-certificates`, `git`.

**Conclusion: a fresh native Pi build adds no Docker. F05 already handles
this correctly, and the gate fails safe** — anything other than the exact
string `docker` takes the native path.

The Docker on the current Pi is residue from a provision predating commit
`726ce40`, which is what added the gate. Before it, `host-setup.sh`
installed Docker unconditionally on every host, including Pi. Nothing in the
current code has added Docker since.

A native-mode Docker teardown feature was drafted and then **deliberately
dropped** as over-engineering — permanent code in `host-setup.sh` to service
a one-time migration affecting a fixed, shrinking set of hosts. Per the
user: only future builds matter, and those are already correct. (The F06
number was subsequently reused for the unrelated macOS feature below.)

### Open — F06, run the Docker image on macOS

Spec'd this session as `03-features/notdone/f06-macos-docker-dev.md`. A
fourth scenario: run the existing arm64 robot image on an Apple Silicon Mac
under Docker Desktop as a headless ROS 2 dev environment — the exact image
the robot runs, with no Pi and no VM.

The image already works unmodified; everything blocking it lives in
`compose/compose.yaml`, and only `devices: /dev/dma_heap` is actually fatal.
Scope is a `compose/compose.mac.yaml` override plus a `02-doc/mac-howto.md`
guide, leaving Scenario 3's compose file and both Dockerfiles untouched.

Two decisions recorded in the feature file, both assumptions made because
they were unspecified: the container is a **self-contained sandbox** whose
ROS graph does not join the robot's, and the scenario is **selected by which
compose files are passed**, not by a new `manifest/` flag — no
`DOME_TARGET=mac`.

**Tasks not yet written.**

### Done — F07, cloud host as a remote ROS 2 dev box

`03-features/done/f07-cloud-dev-host.md`, tasks in
`04-tasks/done/TF07-cloud-dev-host.md`. Rewritten after a critique found
that following `vm-howto.md` on a real cloud host would fail.

**What breaks on a cloud host today:**

- The login user is `root` or `ubuntu`, so the repo gets cloned into the
  wrong home. `manifest/bashrc:1` hardcodes `~/provision_dome`, so
  `ROS_DISTRO` comes out empty.
- `host-setup.sh` creates the user interactively with no `authorized_keys`,
  and cloud images disable password SSH, so the new user can't log in.
- Swap is Pi-only.
- The guide copies your personal GitHub key onto an internet-facing box.

**Decisions in the rewrite:**

- **`DOME_TARGET=cloud`** now has real behavior: it gets swap.
- **A cloud-init template** (`host-file-templates/cloud/user-data.template`)
  creates the user with your key, clones the repo into the right home,
  writes `user.txt`, and runs `host-setup.sh` and `bare-metal-base.sh`.
  This is the "simplify provisioning" win.
- **A host-specific GitHub key**, revoked at teardown.
- **Access by SSH tunnel only, no Tailscale.** Foxglove first; the noVNC
  desktop is optional, and both the VNC and websockify listeners are
  loopback-only.
- **arm64 or x86_64.**

Robot-graph joining moved to F08. Provider research and pricing moved to
`02-doc/notes.md`, *Dev host options*, which was then revised:

- Costs are now priced for occasional (~40 h) and always-on use.
- Stop/snapshot lifecycle costs are included.
- The Oracle figure was corrected: its allowance was halved in June 2026,
  so the old $28 figure was wrong.
- A refurbished desk mini PC was added as an alternative.

**Decision made: OCI A1 (arm64).** arm64 matches the Pi, and DigitalOcean
has no arm shape. Working assumption — fallbacks (DigitalOcean x86_64, or a
desk mini PC on the robot's network) are in `notes.md` if OCI doesn't pan
out. The feature spec and `oci-howto.md` were updated to assume OCI.

TF07.0 (manual OCI bring-up) confirmed the predicted breakages; verdicts are
in `notes.md`. **Done 2026-09-24.**

### Open — F08, remote host joins the robot's ROS graph

`03-features/notdone/f08-remote-ros-graph.md`. Split out because it
**requires changing the robot**: Tailscale on the Pi, and unicast discovery
configured on both ends. It also depends on which RMW the native path runs,
which this repo doesn't pin (only `compose.yaml` does; `rosutils` may).

Five open questions are listed in the spec: RMW, discovery mechanism,
robot opt-in, `ROS_DOMAIN_ID` policy, and `/cmd_vel` authority. Resolve
them before writing tasks. Absorbs F06's deferred graph-joining question.

## Open

- Two chores still open in `04-tasks/chores.md`, neither blocking:
  `host-setup.sh` bypassing `manifest/lib.sh` (and the env > user.txt >
  config cascade duplicated ~9 times), and a self-defeating provenance echo
  in `bare-metal-build.sh`. Closed 2026-09-24: the `pi-howto.md`/`vm-howto.md`
  dev-cycle claim (docs now say the build only clones *new* repos; updating
  existing ones is a manual `git -C <repo> pull`), the `--symlink-install`
  recipe and `manifest-format.md` example, and the `pip.txt` numpy pin
  (a pin there wouldn't help — see the chore).

- Adding an opt-in pull pass to `bare-metal-build.sh` remains a possible
  feature (behavior change, needs a feature/task pair); not planned.

- One-off host cleanup available for the current Pi, at the user's
  convenience — `systemctl disable --now dome docker docker.socket
  containerd`, remove `/etc/systemd/system/dome.service`, `daemon-reload`.
  Not code, not tracked as a task.

- `Boston-Robot-Hackers/dome_vision` needs a fix in a **separate repo**, not
  tracked here: `dome_vision/dome_vision/pyproject.toml` (package
  `oak-roboflow`) has unpinned `numpy` and a duplicate `opencv-python` —
  `colcon build`'s per-package `pip install .` doesn't share
  `bare-metal-base.sh`'s combined resolver context, so it silently upgraded
  numpy to 2.5.1, breaking `depthai-sdk`'s hard `numpy<2.0.0` requirement,
  and installed a conflicting second OpenCV wheel. User has a fix prompt to
  run against that repo directly (pin `numpy<2`, drop `opencv-python`).

- F06 needs a task list before any implementation can begin, per
  `.claude/process.md`. Its deferred graph-joining question is now F08.

- Side observation, not tracked yet: the commented first-boot block in
  `host-file-templates/boot/firmware/user-data.template` runs
  `./host-setup.sh` from the repo root, but the script lives at
  `scripts/host-setup.sh`. It would fail if uncommented. Worth a chore.

- F07's breakage doc fixes landed in `oci-howto.md`/`cloud-howto.md` (key
  ownership and filename; explicit `-i … -o IdentitiesOnly=yes`). F10 makes
  the GitHub key unnecessary on cloud hosts and will rewrite that step.

## Blockers

None.
