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

- **F15** (contain the cloud box's blast radius) — **complete (2026-09-26).**
  Verified live on `dome-cloud-1`, not just statically: `ssh -A` gets no agent
  and cannot reach GitHub, `rosutils` is detached at its pinned commit, 48210
  admits one `/32` and is closed by `stop`, plaintext on 48210 is refused, the
  audit is clean. Doppler removed from the project entirely. One finding
  deferred (F15.6, child compartment) and one half deferred (the Terraform key
  wiring) — both to the F11 rebuild, both recorded in the feature file. Files in
  `done/`.
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

**F15 is closed and committed** on branch **`f15-blast-radius`** (`0e47af5`,
`4c30c28`, plus the closeout commit). Suite **368 green, 0 failed**. The branch
is pushed and tracking. **Not merged to `main`.**

Nothing is in progress. The user's decision (2026-09-26): **F17 next**, because
inspecting the box showed the repo problem it solves is real — see below.

**Why F17 moved up.** Under `DOME_CLONE_OVERRIDE=PUBLIC_ONLY` the box has
**none** of the `dome*` code — all 15 private repos are skipped — but it does
have the 8 incidental public ones: `depthai-python`, `linorobot2_hardware`,
`ldlidar_stl_ros2`, `micro-ROS-Agent` and `micro_ros_msgs` (the last two cloned
**twice**, into both `ros2_ws/src` and `uros_ws/src`). So the cloud box is a ROS
workspace full of a robot's dependencies with the robot missing. F17's `SAFE`
set — a deliberate `rosutils` + `better_launch` — is exactly the fix, and its
tasks TF17.0–TF17.10 are already written.

**Ordering note carried over from F15:** F15 landed first, so **TF17.5/TF17.6
must preserve the commit-pin field** while stripping `PRIVATE_REPO`. A 40-hex
third field is now a commit pin, not a branch — see `manifest_parse_repo`.

**Also queued, from the user's notes (2026-09-26), neither spec'd yet:**

- **A summary target** (proposed F18): one Mac-side command reporting live
  state — IP, lifecycle, armed/disarmed, actual OCI ingress rules, effective
  `DOME_*` config from the box, key in use, audit result. Motivated by real
  confusion this session (private `10.0.1.235` vs the public IP, `http` vs
  `https`, armed vs disarmed). `make env` on the box reports only three keys and
  omits `DOME_DESKTOP`/`DOME_VNC_ACCESS`/the clone override.
- **`manifest/` should hold only manifests** (a chore, no behavior change):
  `lib.sh` is shell code and belongs in `scripts/`; `bashrc` is an installed
  template and belongs under `host-file-templates/`. 22 files reference
  `lib.sh`, 17 reference `bashrc`, though most are docs and historical task
  files to leave as record. Hazard: moving `bashrc` changes what
  `bare-metal-build.sh` installs, and a stale `~/.bashrc` already caused one
  live failure during the repo rename (see `chores.md`).
- **`micro-ROS-Agent`/`micro_ros_msgs` listed twice** in `repos.txt` — decide
  whether the duplication is deliberate.

**Open chores:** six in `04-tasks/chores.md`, including the new one to uninstall
the Doppler CLI from hosts provisioned before F15 — **the robot is the one that
matters**, since it won't be rebuilt.

**Candidates after F17:**

- **F16** (key custody on the Mac) — spec only, **no tasks**. Ranks high: both
  crown-jewel private keys unencrypted on disk, and `~/.oci/oci_api_key.pem` is
  the whole tenancy. F15's own spec says F16 outranks it.
- **F11** (Terraform creates the login user as `DOME_USER`) — tasks
  TF11.0–TF11.5, **awaiting approval**. Now also gates F15.6, the Terraform key
  wiring, and any rebuild.
- **F12** (per-mode repo transport) — spec only, open questions.
- **F06** (macOS Docker dev) — spec'd, needs a task list.
- **F08** (remote ROS graph) — five open questions. Note F15.1 was preventive
  *because* F08 adds the box→robot network leg.

### Live box — `dome-cloud-1`, RUNNING and armed (2026-09-26, end of F15 session)

`129.213.164.184` (arm64, 4 OCPU/24 GB), **RUNNING**, desktop **armed**, repo on
branch `f15-blast-radius`. Re-entry from the Mac:

```
make -C terraform/oci start
make -C terraform/oci ssh          # or: ssh dome-cloud-1
```

**It now has its own SSH key.** `~/.ssh/id_dome_cloud`
(`SHA256:V1A2xPZoG8k2DgzC813bq6FXVrx5ucGIH0+l19AoZo8`), passphrase-protected, and
the shared `id_ed25519` was **removed** from the box's `authorized_keys`. The
Mac's `~/.ssh/config` has a `dome-cloud-1` block above `Host *` carrying
`ForwardAgent no`, so `ssh dome-cloud-1` needs no flags. Backup of the previous
config: `~/.ssh/config.bak-20260926-130319`.

Note the **instance metadata still holds the old public key** — changing it is
force-replacement, so it stays until the F11 rebuild. Cloud-init did **not**
re-add it across a stop/start (verified), but re-check `authorized_keys` after
any future reboot.

**`DOME_TARGET` is now `cloud`**, corrected this session — it had been `vm`,
which would have silently skipped F15's sshd hardening. `DOME_DESKTOP=vnc`
appears once (the earlier `vncvnc` duplicate is fixed). Effective config: the
`user.txt` overrides above plus `ROS_DISTRO=kilted`, `UBUNTU_CODENAME=noble`,
`DOME_MODE=native`, `SWAP_SIZE_MB=2048` from `config.txt`.

**Hardened and verified** (see the F15 feature file for full results): sshd
refuses agent forwarding, X11 and root login while keeping `AllowTcpForwarding`;
`rpcbind` masked; Doppler CLI uninstalled; `mcfly 0.9.4` from a verified pin;
`rosutils` detached at its pinned commit.

**Desktop URL — note `https`, not `http`:**
`https://129.213.164.184:48210/vnc.html?autoconnect=true`

Plaintext is refused (`--ssl-only`), the cert is self-signed so the browser will
warn, and its fingerprint is `22:75:32:AD:5C:89:14:84:30:12:E8:0F:5D:18:6E:B5:
51:D1:66:96:EF:56:D5:DC:23:2E:92:D2:30:B3:B6:08`. Ingress on 48210 is limited to
**one `/32`** — whatever address `make vnc-up` saw — so re-run `vnc-up` if your
address changes. Open the page in a **separate browser profile** with no
signed-in sessions.

**The VNC units are no longer enabled at boot.** A reboot or a `make start`
leaves the box closed until an explicit `make vnc-up`. And **`make stop` now
disarms**: it closes 48210 at the edge before the `SOFTSTOP`, so the old advice
to remember `vnc-down` is obsolete.

It has only ever been reprovisioned **in place**, never rebuilt. A
`terraform destroy`/`apply` would still be a regression:
`user-data.template:36` clones the GitHub **default branch** (which has none of
F13/F14/F15) and the template writes neither `DOME_DESKTOP` nor
`DOME_VNC_ACCESS`. Rebuilding becomes sane only once F11 teaches cloud-init the
branch and those vars — and a destroy also risks not getting A1 capacity back.

**What the box does *not* have: any `dome*` code.** `PUBLIC_ONLY` skips all 15
private repos, so `ros2_ws/src` holds only public dependencies. F17 is the fix.

The `terraform/oci/Makefile` wraps start/stop/status/ssh/audit/vnc-*; the
repo-root `Makefile` holds box-side dev targets
(`make build`/`desktop`/`env`/`status`).

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
