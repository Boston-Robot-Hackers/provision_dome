# Current Status

**Date:** 2026-09-22

Full session-by-session log lives in `02-doc/history.md`. This file holds
only current status and open items.

## Status

F02, F03, F04, F05 all complete.

- **F06** (macOS Docker dev) — spec'd, **no tasks yet**.
- **F07** (cloud dev host) — spec'd and tasked, 9 tasks in
  `04-tasks/notdone/TF07-cloud-dev-host.md`, none started. **Rewritten
  2026-09-22 after a critique**; see below.
- **F08** (join a remote host to the robot's graph over Tailscale) — new,
  split out of F07. Spec only, with open questions to resolve before tasks.
- **F09** (shared internet-facing server with on-demand wake) — **deferred**
  summary in `03-features/deferred/`. Recorded for memory only; the user
  doubts they'll pursue it.

F07's T08 has an ordering dependency on F06 (both add a scenario row).

This session was an analysis pass over the Pi (Scenario 1) build path, with
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

### Open — F07, cloud host as a remote ROS 2 dev box

`03-features/notdone/f07-cloud-dev-host.md`, tasks in
`04-tasks/notdone/TF07-cloud-dev-host.md`. Rewritten after a critique found
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

**Open decision before T01: cloud host or desk box.** A desk box on the
robot's network would make most of F07 and F08 unnecessary.

T01 is a manual cloud bring-up that must confirm the predicted breakages
before any code. **Not started.**

### Open — F08, remote host joins the robot's ROS graph

`03-features/notdone/f08-remote-ros-graph.md`. Split out because it
**requires changing the robot**: Tailscale on the Pi, and unicast discovery
configured on both ends. It also depends on which RMW the native path runs,
which this repo doesn't pin (only `compose.yaml` does; `rosutils` may).

Five open questions are listed in the spec: RMW, discovery mechanism,
robot opt-in, `ROS_DOMAIN_ID` policy, and `/cmd_vel` authority. Resolve
them before writing tasks. Absorbs F06's deferred graph-joining question.

## Open

- Five chores logged in `04-tasks/chores.md`, none blocking: `pi-howto.md`'s
  false "re-clones changed repos" dev-cycle claim; its `--symlink-install`
  troubleshooting recipe contradicting the deliberate empty `colcon` flags;
  `host-setup.sh` bypassing `manifest/lib.sh`; a self-defeating provenance
  echo in `bare-metal-build.sh`; unpinned `numpy` in `pip.txt`.

- The `pi-howto.md` dev-cycle item is the one worth a decision rather than a
  quick edit — `clone_section` deliberately skips existing dirs, so
  re-running `bare-metal-build.sh` never updates already-cloned repos.
  Fixing the *doc* is a chore; adding a pull pass is a behavior change
  needing a feature/task pair.

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

- F07 has a full task list and is ready to start; T01 (validating the
  existing vm path on a real cloud instance) is the natural next step and is
  a manual provisioning run, not code. T07 (scenario-table/README updates)
  should wait until F06's status/wording is settled to avoid rework.

## Blockers

None.
