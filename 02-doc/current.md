# Current Status

**Date:** 2026-10-17

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

- **F15** (contain the cloud box's blast radius) — **complete (2026-09-26).**
  Verified live on `dome-cloud-1`, not just statically: `ssh -A` gets no agent
  and cannot reach GitHub, `rosutils` is detached at its pinned commit, 48210
  admits one `/32` and is closed by `stop`, plaintext on 48210 is refused, the
  audit is clean. Doppler removed from the project entirely. One finding
  deferred (F15.6, child compartment) and one half deferred (the Terraform key
  wiring) — both to the F11 rebuild, both recorded in the feature file. Files in
  `done/`.
- **F19** (a user cookbook to replace the guide set) — new, **in progress.**
  TF19.0–TF19.3 done; TF19.4–TF19.10 not started. Replaces `howto.md` and the
  four `*-howto.md` guides with a concepts chapter plus one recipe per mode;
  retires `oci-howto.md` to `archive/`. Numbered F19 because F18 is reserved for
  the summary target below.
- **F16** (key custody on the Mac) — new, split out of F15. **Spec only, no
  tasks.** Ranks above F15: two unencrypted crown-jewel private keys.
- **F17** (named repo sets via `REPOS_CONFIG`) — **complete (2026-10-17).**
  TF17.10 done: `dome-cloud-1`'s `user.txt` now says `REPOS_CONFIG=SAFE` and a
  live build resolved 2 repos, no key, exit 0. Files in `done/`. Suite **395
  green**.

- **F14** (per-VM VNC access) — **complete (2026-09-25).** One controllable
  TigerVNC desktop, per box either `public` (URL + VNC password, port 48210
  open, served on boot) or `tunnel` (loopback + SSH key). Dropped `x11vnc`
  and the two-mirror design; `DOME_VNC_ACCESS` flag + Terraform `vnc_access`.
  Perf validated live ("feels ok"). Suite 300 green. Files in `done/`.


## ⏭ Pick up here (next session)

Branch **`main`**, suite **395 green, 0 failed**, working tree clean, pushed.
`f15-blast-radius` is merged (`3409e6a`) and no longer needed for anything; the
box now tracks `main` too.

### What happened 2026-10-17

- **Committed and merged** F17 (`d4b83e0`) and F19-in-progress (`b1604d4`)
  as separate commits, then merged the branch to `main` with `--no-ff`.
- **F17 closed.** TF17.10 ran live: the box's `user.txt` now says
  `REPOS_CONFIG=SAFE`, and a build resolved 2 repos, needed no key, exit 0.
  Files in `done/`.
- **Doppler hook removed from `rosutils`** (`campusrover/rosutils@2febc36`,
  directly on the old pin `1e0fbeb`), and both repo sets now pin `2febc36`.
  This repo had no Doppler code left on any path.
- **Native VNC viewer documented** in `cloud-howto.md` Step 7: TigerVNC Viewer
  over `ssh -N -L 5901:localhost:5901`, because noVNC's clipboard is painful.
  Added to F19's must-survive checklist so the cloud recipe keeps it.

### Next

**F19, TF19.4 — the Pi recipe.** Then TF19.5 VM, TF19.6 container, TF19.7
cloud, TF19.8 retire the old guides, TF19.9 newcomer read-through, TF19.10
`tests/test_f19_cookbook.sh`.

**Read the TF19.1 must-survive checklist before writing any recipe.** It is
what stops the rewrite silently dropping a hard-won detail. TF19.8's ordering
hazard is gone now that F17 is committed.

**The rule the recipes are held to:** a recipe may not re-explain a concept.
TF19.10 enforces it mechanically — every `DOME_*`/`REPOS_CONFIG` token used in
any recipe must be defined in `cookbook-concepts.md`.

**F19's four decisions** (in the feature file): five files; README becomes a
short front door; no behavior fixes inside F19; the container recipe is marked
"not recently exercised".

### Small and ready: the rosdep chore

Found during TF17.10. `bare-metal-build.sh` runs `rosdep install` under
`sudo -u … bash -c`, which drops `ROS_DISTRO`, so rosdep resolves **no** keys,
and `-r` lets the build report success anyway. Fix: `--rosdistro` and drop `-r`;
check the `Dockerfile` for the same gap; grep-style regression test. Full entry
in `chores.md`.

### Open chores

**Ten** in `04-tasks/chores.md`. The ones that matter most:

- **Uninstall the Doppler CLI from the robot** — it was provisioned long
  before F15 and won't be rebuilt. Three manual commands, in the chore.
- **Existing hosts don't follow pin bumps.** The build skips already-cloned
  repos, so the robot's `~/rosutils` needs a manual
  `git -C ~/rosutils fetch` then `checkout --detach 2febc36…`.
- The rosdep bug above, and the duplicate-key concatenation bug in the
  config cascade.
- Three doc defects F19 will absorb (`oci-howto.md`'s `DOME_TARGET=vm`, the
  missing Pi boot-file step, `docker-howto.md` delegating to `howto.md`).

### Queued, not spec'd

- **F18, a Mac-side summary target** (number reserved): one command reporting
  IP, lifecycle, armed/disarmed, actual ingress rules, effective `DOME_*` and
  `REPOS_CONFIG` from the box, key in use, audit result.
- **`manifest/` should hold only manifests** (a chore): move `lib.sh` to
  `scripts/`, `bashrc` under `host-file-templates/`. Moving `bashrc` changes
  what `bare-metal-build.sh` installs — a stale `~/.bashrc` already caused one
  live failure.
- **`micro-ROS-Agent`/`micro_ros_msgs` listed twice** in `repos-dome.txt` —
  undecided; F17 pins the pair as the only allowed duplicates.
- **Maybe retire the public noVNC path.** If the native viewer over the tunnel
  becomes the only way in, port 48210, the self-signed cert and `vnc-up` could
  go — a feature that shrinks the attack surface.

### Candidates after F19

- **F16** (key custody on the Mac) — spec only. Ranks high: two unencrypted
  crown-jewel private keys; `~/.oci/oci_api_key.pem` is the whole tenancy.
- **F11** (Terraform creates the login user as `DOME_USER`) — tasks
  TF11.0–TF11.5 **awaiting approval**. Gates F15.6, the Terraform key wiring,
  and any rebuild. Its *Do not change* list still names `DOME_CLONE_OVERRIDE`;
  should read `REPOS_CONFIG`.
- **F12** (per-mode repo transport) — spec only. Much of its design is **moot
  after F17**: separate set files can already carry different urls for the same
  repo. Reread its premise before writing tasks.
- **F06** (macOS Docker dev) — needs a task list.
- **F08** (remote ROS graph) — five open questions.

### Live box — `dome-cloud-1` (2026-10-17)

`129.213.164.184` (arm64, 4 OCPU/24 GB). Left **running, desktop armed** by
`vnc-up` this session unless stopped since — `make -C terraform/oci stop`
disarms and stops it.

```
make -C terraform/oci start
make -C terraform/oci ssh          # or: ssh dome-cloud-1
```

**State on the box:**

- `~/provision_dome` on **`main`**; `~/rosutils` detached at **`2febc36`**
  (no Doppler hook).
- `manifest/user.txt`: `DOME_USER=ubuntu`, `DOME_TARGET=cloud`,
  `DOME_DESKTOP=vnc`, `DOME_VNC_ACCESS=public`, `REPOS_CONFIG=SAFE`. Previous
  copy at `/tmp/user.txt.bak-tf1710`.
- Hardened per F15: sshd refuses agent forwarding, X11 and root login;
  `rpcbind` masked; Doppler CLI uninstalled; `mcfly` from a verified pin.
- **No `dome*` code** — `SAFE` is two repos. The 8 incidental public repos from
  the old `PUBLIC_ONLY` run are still in `ros2_ws/src` until removed by hand.

**Own SSH key**: `~/.ssh/id_dome_cloud`, passphrase-protected; the Mac's
`~/.ssh/config` has a `dome-cloud-1` block with `ForwardAgent no`. The instance
metadata still holds the old shared public key (changing it forces
replacement) — re-check `authorized_keys` after any reboot.

**Desktop, preferred:** TigerVNC Viewer → `ssh -N -L 5901:localhost:5901
dome-cloud-1`, connect to `localhost:5901`. Display `:1`, loopback only,
TigerVNC 1.13.1. Needs no open port.

**Desktop, browser:** `make -C terraform/oci vnc-up` **from the Mac** (on the
box it fails, and would pick the box's own IP), then
`https://129.213.164.184:48210/vnc.html?autoconnect=true`. Self-signed cert,
fingerprint `22:75:32:AD:5C:89:14:84:30:12:E8:0F:5D:18:6E:B5:51:D1:66:96:EF:56:
D5:DC:23:2E:92:D2:30:B3:B6:08`; 48210 admits one `/32`. Not enabled at boot; `make stop` disarms.

**Seen this session, not yet explained:** `systemctl` warned that
`dome-vnc.service` changed on disk since it was loaded. Nothing in `vnc-up`
writes that file. If it recurs after a reboot, something is rewriting it.

**Don't `terraform destroy`/`apply`** until F11: cloud-init clones the default
branch and writes neither `DOME_DESKTOP` nor `DOME_VNC_ACCESS` (nor
`REPOS_CONFIG`), and a destroy risks losing A1 capacity.

**Decision on record:** stay on OCI A1 Always Free + Terraform. Price is the
top priority and Terraform removed the console friction; the desk mini PC stays
a "someday on the robot's network" idea.

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
