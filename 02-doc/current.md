# Current Status

**Date:** 2026-09-24

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

- **F10** (selectable repo cloning) — **spec'd, tasks TF10.0–TF10.6 written,
  none started.** Adds a `PRIVATE_REPO` marker in `manifest/repos.txt` and a
  `DOME_CLONE_OVERRIDE` flag (unset = clone all; `PUBLIC_ONLY`; `NONE`), so a
  cloud host carries **no push-capable GitHub key and no private clones**.
  Purely additive: `pi`/`vm`/`docker` unchanged. See below.

F10's TF10.5 edits the F07 cloud-init template and `cloud-howto.md`.

## ⏭ Next session — pick the next feature

F07 is closed. Candidates:

- **F10** (selectable repo cloning) — tasks written, none started; removes the
  push-capable GitHub key from the cloud host. Suggested next: TF10.0/TF10.1.
- **F06** (macOS Docker dev) — spec'd, needs a task list first.
- **F08** (remote graph) — five open questions to resolve before tasks.

The branch `feature/f07-cloud-dev-host` has many **uncommitted** changes
(Terraform, `Makefile`, `cloud-howto.md`, F10 files, F07 close-out) — commit
when asked.

**Box:** `dome-cloud-1` at `129.213.124.37` (arm64, 4 OCPU/24 GB). Re-entry:
`make ssh`, or `ssh -i ~/.ssh/id_oci -o IdentitiesOnly=yes ubuntu@129.213.124.37`.
Login key note: `~/.ssh/id_oci.pub` is the durable key on the box (the original
`~/.ssh/id_ed25519` went missing from disk). The `Makefile` wraps
start/stop/status/ssh.

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

### Open — F10, selectable repo cloning

`03-features/notdone/f10-selectable-repo-cloning.md`, tasks in
`04-tasks/notdone/TF10-selectable-repo-cloning.md`. Motivated by F07: the
cloud host needed a push-capable account GitHub key just to clone the private
`git@` repos in `repos.txt`, and left private source on an internet-facing box.

- TF10.0 mark private repos, TF10.1 resolve the flag, TF10.2 order-independent
  marker parser, TF10.3 gate `clone_section`, TF10.4 refuse `git@`/`ssh://`
  clones under `PUBLIC_ONLY`/`NONE`, TF10.5 cloud-init + `cloud-howto.md`
  integration, TF10.6 test suite and regression check.
- Not started. Per process, switching from F07 to F10 needs permission first.
- Suggested order: close F07 TF07.0 first, then F10.

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

- F07's breakage findings imply doc fixes to `oci-howto.md`/`cloud-howto.md`
  (host GitHub key must be the `DOME_USER`'s, default filename; explicit
  `-i … -o IdentitiesOnly=yes` ssh form). F10 makes the key unnecessary on
  cloud hosts.

## Blockers

None.
