# Feature description for feature F13

## F13 — box-side dev-host Makefile (split from the laptop control Makefile)

**Priority**: Low

**Done:** yes

**Tasks File Created:** yes

**Tests Written:** yes

**Test Passing:** yes

**Description**:

Give the cloud dev host its own `Makefile` with targets that are meaningful
**on the box** (build the workspace, start the desktop, show the ROS/env
state), and stop the laptop-only OCI control Makefile from landing on the box
where every one of its targets is inert or wrong.

### Why

The root `Makefile` today is a **laptop control-plane tool**: `start`, `stop`,
`status`, `ip`, `ssh`, `vnc-up`/`vnc-down`. It drives the remote OCI instance
through the `oci` CLI and the Terraform state in `terraform/oci`.

Provisioning clones the whole repo into `~/provision_dome` on the box
(`host-file-templates/cloud/user-data.template`), so the box gets the **same**
`Makefile`. But on the box none of it works:

- `oci` is not installed → `make start`/`stop` fail with `command not found`.
- `terraform.tfstate` and `terraform.tfvars` are gitignored, so they never
  reach the box → `make ip`/`make status` print empty.
- `make ssh`/`vnc-up` would SSH from the box into a blank host — nonsensical,
  since the box *is* the target.

So a developer on the box who runs `make` gets a menu of broken laptop
commands and nothing useful for actual dev work.

### The naming tension (key decision)

Both users naturally run `make` from the repo root: the box user from
`~/provision_dome`, the laptop user from the repo checkout. A single root
`Makefile` cannot serve both.

**Recommended resolution:** the **root `Makefile` becomes the box-side dev
tool**, and the **laptop OCI control targets move to `terraform/oci/Makefile`**,
run as `make -C terraform/oci <target>` (or from within that directory, which
is where the operator already is when touching Terraform).

This has two payoffs beyond the split:

- The control Makefile lives **next to the Terraform state it reads**, so its
  relative `TF_DIR` problem disappears — no more "`make ip` only works from the
  repo root."
- The box's root `Makefile` is all box-relevant targets, nothing broken.

**Open decision for the user:** this relocates a laptop habit — `make start`
from the repo root becomes `make -C terraform/oci start`. Accept the
relocation, or keep the laptop control at the root and disambiguate some other
way (e.g. one environment-dispatched Makefile that shows box targets when
`DOME_TARGET=cloud` and control targets otherwise). Resolve before TF13.1.

### Scope

Box-side (root) `Makefile` targets, thin wrappers over existing scripts —
**no new provisioning logic**:

- **`make build`** — `sudo scripts/bare-metal-build.sh` (clone any new repos,
  colcon-build the workspace).
- **`make desktop`** — `scripts/start-desktop.sh` (the loopback noVNC desktop).
- **`make env`** — print the resolved `DOME_USER` / `DOME_TARGET` /
  `ROS_DISTRO` and whether the workspace overlay is sourced, so a fresh shell's
  state is legible at a glance.
- **`make status`** — quick ROS health: `ros2 pkg list | wc -l` and whether
  `~/ros2_ws/install/setup.bash` exists / is current.
- **`make help`** — the default target; lists the above.

Laptop `terraform/oci/Makefile` keeps the current targets verbatim
(`start`/`stop`/`status`/`ip`/`ssh`/`vnc-up`/`vnc-down`), with `TF_DIR`
re-anchored to `.` (it now lives inside `terraform/oci`).

### Out of scope

- Any change to what provisioning installs or clones. This feature only
  reorganizes `make` entrypoints over scripts that already exist.
- New desktop/VNC behavior — `vnc-up`/`vnc-down` move unchanged.
- Removing the repo clone or making it sparse; the whole repo still lands on
  the box, it just no longer offers broken laptop targets there.

### Open questions (resolve before tasks)

- **The relocation decision above** (root = box vs. environment-dispatched
  single file). Everything else follows from it.

- **Does `make build` need `sudo`?** `bare-metal-build.sh` runs as root today;
  the target should match how the guide invokes it, not silently change it.

- **Do the docs that say `make start`/`make ssh`/`make ip`** (`cloud-howto.md`,
  `oci-howto.md`, `02-doc/current.md`, `Makefile` help text) all get updated to
  the new `-C terraform/oci` form? Assume yes; enumerate them in a task.

## How to Demo

**Setup**: a checkout of the repo (laptop) and a provisioned cloud box with the
repo cloned at `~/provision_dome`.

**Steps**:

1. On the box, from `~/provision_dome`, run `make` (or `make help`).
2. On the box, run `make env`.
3. On the laptop, from `terraform/oci`, run `make ip`.

**Expected output**: step 1 lists the box-side dev targets (build, desktop,
env, status) — no `start`/`stop`/`ssh` and nothing that shells out to `oci`;
step 2 prints the resolved `DOME_USER`/`DOME_TARGET`/`ROS_DISTRO` and overlay
state; step 3 prints the current public IP with no repo-root dependence.
