# TF19 Description for Feature F19

**Date Created:** 2026-09-26

Rewrite the documentation as a user cookbook: concepts and vocabulary once,
then one recipe per major mode, with no feature numbers and no project history.

Testing a document is mostly mechanical, so most steps carry a `grep`-style
check in `tests/test_f19_cookbook.sh`, in the same static style as the rest of
the suite. The things that actually matter about prose — whether it *reads*
well and whether a recipe *works* — cannot be tested that way, so TF19.9 and
TF19.10 record them as deliberate manual steps rather than pretending
otherwise.

## Ordering note — read before starting

**Write the concepts chapter (TF19.2) before any recipe (TF19.4–TF19.7).** The
recipes are forbidden from re-explaining a concept, so the chapter is what they
lean on; writing a recipe first guarantees it re-explains something and has to
be unpicked.

**Retire nothing until its replacement exists (TF19.8, near the end).** Every
current guide stays in place and linked while the cookbook is written, so the
tree never has a period with no usable instructions.

## TF19.0 — settle the open questions

**Status**: done

**Description**: Resolve the four open questions in the feature file before
writing prose, since each changes the shape of what gets written:

- **One file or five.** Recommendation on record: one concepts file plus one
  file per mode, with recipes forbidden from re-explaining a concept.
- **What the README becomes** — a short front door, or a fifth place concepts
  get half-explained.
- **How much of the cloud safety material survives**, rewritten as
  instructions rather than as findings.
- **Whether the container recipe can be written confidently at all**, given
  that `02-doc/notes.md` calls that image the least debugged part of the
  project and says to treat its behavior as unverified.

**Resolved 2026-09-26:** **five files** (concepts + one per mode, with the
no-re-explaining rule enforced by TF19.10); the **README becomes a short front
door**; **no behavior fixes** — the `DOME_TARGET=vm` mismatch becomes a chore;
and the **container recipe is marked as not recently exercised**, present tense.

*Test:* none — decisions. Recorded in the feature file.

## TF19.1 — inventory what the current guides actually contain

**Status**: done

**Description**: Before deleting anything, extract from the seven current
documents every instruction that is **still true and still needed**, and note
which ones already contradict each other. Two are known going in:
`oci-howto.md` writes `DOME_TARGET=vm` for an OCI box while `cloud-howto.md`
writes `DOME_TARGET=cloud` — the former skips the swap a small cloud shape
needs; and `oci-howto.md` describes itself as a superseded manual path.

Output is a working checklist, not prose, so that the rewrite can be checked
for **dropped** content rather than only for added content. This is the step
that stops a rewrite from quietly losing a hard-won detail.

**Status note:** done 2026-09-26. The checklist follows; TF19.9 verifies the
cookbook against it.

### Must survive — shared by every native recipe (Pi, VM, cloud)

- `manifest/user.txt` is **gitignored and must be created by hand on every
  machine**. This is the single most repeated instruction in the current docs.
- `DOME_USER` must match the existing login account, and on a Pi must match
  what was typed into Raspberry Pi Imager.
- **Open a new shell after a build.** `bare-metal-build.sh` installs
  `~/.bashrc`; the shell that ran the build does not have it. Every guide says
  this and it is the most common first stumble.
- **The build skips repos already cloned.** `git pull` + rebuild does *not*
  update repos on disk; update one with
  `git -C ~/ros2_ws/src/<repo> pull` then rebuild.
- Which script to re-run for what: `packages.txt`/`pip.txt` → base script;
  repo set → build script; udev rules → `host-setup.sh`.
- **udev rules only reach `/etc/udev/rules.d/` when `host-setup.sh` runs.** A
  plain `git pull` does not apply them.
- `host-setup.sh` prints the machine's IP addresses just before finishing.
- Reboot after `host-setup.sh`.
- The smoke test: `echo "$ROS_DISTRO"` → `kilted`, `ros2 --help`,
  `ls ~/ros2_ws/src`.

### Must survive — Pi only

- Imager settings: Pi 4/5, Ubuntu Server 24.04 LTS 64-bit, hostname `dome`,
  username matching `DOME_USER`, password, SSH enabled, Wi-Fi if needed.
- Copying `config.txt`/`cmdline.txt` to `/Volumes/system-boot` after flashing,
  then ejecting. **Only `howto.md` has this** — `pi-howto.md` omits it.
- `DOME_TARGET=pi` is the default and needs no line in `user.txt`.
- Swap: `SWAP_SIZE_MB` default 2048, guards `colcon build` OOM on a 4 GB Pi 5
  because `colcon.txt` caps no parallel jobs. Override or disable with `0`.
- Getting the GitHub key onto the Pi, `chmod 600`, `ssh -T git@github.com`,
  and loading it into an agent so `sudo` can use it.
- colcon build is slow on ARM.

### Must survive — VM only

- **Ubuntu 24.04 (noble) specifically.** Verify with `cat /etc/os-release`
  *before anything else*; another release fails midway through the base script
  with cryptic apt errors, not a clear message.
- `DOME_TARGET=vm` must be added, or Pi-hardware steps run and the ReSpeaker
  overlay build fails with `install: invalid target '/boot/firmware/...'`.
- Console or SSH both work; the console path needs no key copying.
- No camera, lidar, or motors.

### Must survive — container only

- Mac needs Docker Desktop running, a Docker Hub account, and a loaded GitHub
  agent key (`ssh-add --apple-use-keychain`).
- Two builds, and when each is needed: base (`packages.txt` or
  `Dockerfile.base` changed, slow) and overlay (code/repos changed, fast).
- `source scripts/dome-config.sh` is **required** before any compose or build
  command, or Compose falls back to placeholders and the pull fails.
- **The password is baked into the image** — do not use a sensitive one.
- `DOME_MODE=docker` is the one line that differs from the Pi recipe.
- `dome.service` auto-starts on boot; how to check and disable it.
- `install-optional-deps.sh` for torch and piper, plus the two `PIPER_*`
  exports.
- Troubleshooting worth keeping: daemon not running, IPv6-only DNS for
  `download.docker.com`, `pull access denied` (unsourced config), buildx
  `Permission denied (publickey)` and the default-builder fallback, and
  "overlay all CACHED but changes missing" → rebuild base.

### Must survive — cloud only

- A **dedicated keypair for the box**, not the everyday key, and the
  `~/.ssh/config` block with `IdentitiesOnly yes` and **`ForwardAgent no`**.
- Cloud-init runs **quietly**; verify with `cloud-init status --wait` and check
  `/var/log/cloud-init-output.log` on error. `swapon --show` confirms swap.
- Inbound firewall **SSH only**.
- `REPOS_CONFIG=SAFE` by default, and how to opt into `DOME` with a
  **read-only deploy key scoped to one repo**, never an account key, owned by
  the build user at `~/.ssh/id_ed25519`.
- The audit command, and running it before arming a desktop.
- Foxglove over an SSH tunnel (`-L 8765:localhost:8765`), no open ports.
- Desktop: `DOME_DESKTOP=vnc`, then **one** access mode — `tunnel` (loopback +
  `ssh -L 6080`) or `public` (URL, armed from the Mac).
- **Recommended client: a native TigerVNC viewer** (`brew install --cask
  tigervnc-viewer`) over `ssh -N -L 5901:localhost:5901`, connecting to
  `localhost:5901`. Clipboard syncs both ways (unlike noVNC's side panel), no
  cert warning, works in `public` mode too without opening 48210. Avoid macOS
  Screen Sharing. Browser/noVNC is the fallback. (Added 2026-10-17, verified
  live on `dome-cloud-1`.)
- **The VNC password is silently truncated to 8 characters.**
- `https`, not `http`, on the public URL; the self-signed cert warning is
  expected; what the encryption buys.
- Treat the desktop tab as hostile: separate browser profile, no credentials
  typed into it, XQuartz kept off the Mac.
- Software GL only — `rviz2` usable, Gazebo not; prefer Foxglove.
- Arming and disarming (`vnc-up`/`vnc-down`), that a reboot leaves it closed,
  and that stopping the box disarms it.
- Stop the box between sessions to save money; stop vs terminate differ.
- No hardware; the ROS graph is self-contained.

### Retire — history, not instruction

- **"Migrating a … set up before the repo rename"**, in both `pi-howto.md` and
  `vm-howto.md`. One-time migration for a shrinking set of hosts. The
  *symptom* is already in both troubleshooting sections
  (`/opt/ros//setup.bash: No such file or directory`, note the empty segment),
  and that symptom-keyed entry is the cookbook-appropriate form. Keep the fix
  (`cp ~/provision_dome/manifest/bashrc ~/.bashrc`) under the symptom; drop the
  standalone chapter.
- **`oci-howto.md`'s framing** — it documents a superseded manual path and says
  so. Its account signup, OCID and capacity content moves; the rest goes.
- **Scenario numbering** and `howto.md`'s ordering note about unlanded work.
- **"Primary"** as a name for the Mac. Two vocabularies for one machine; the
  cookbook says *your own computer* or *the Mac*.
- Cross-references to `notes.md` for provider pricing, and to feature files.

### Defects found while inventorying — chores, not fixed here

1. **`oci-howto.md` writes `DOME_TARGET=vm` for an OCI box**, which skips the
   swap a small cloud shape needs. `cloud-howto.md` uses `cloud`.
2. **`howto.md`/`pi-howto.md` disagree on flashing**: the `config.txt` and
   `cmdline.txt` copy step exists only in `howto.md`, so a reader following
   `pi-howto.md` alone never does it.
3. **`docker-howto.md` Steps 3 and 4 delegate to `howto.md`**, so the "each
   guide is self-contained" promise is already broken for that path.

*Test:* none directly — it produces the checklist TF19.9 verifies against.

## TF19.2 — write the concepts chapter

**Status**: done

**Description**: The chapter every recipe leans on, in the order given in the
feature file: what the tool does, the manifest as source of truth,
`config.txt` vs `user.txt` and their resolution order, the five settings
(`DOME_TARGET`, `DOME_MODE`, `DOME_DESKTOP`, `DOME_VNC_ACCESS`,
`REPOS_CONFIG`), repo sets and which needs a GitHub key, the three scripts and
what each owns, the two Makefiles and which machine each runs on, and the
workspace/shell model.

**Done 2026-09-26** as `02-doc/cookbook-concepts.md` (298 lines). Covers what
the tool does, a which-one-do-I-want table, the manifest table,
`config.txt` vs `user.txt` with the resolution order and the duplicate-line
hazard, the five settings, repo sets with the key-needed column, the three
scripts plus a *what you changed → what to re-run* table and the
already-cloned limit, the two Makefiles and which machine each runs on, the
workspace and why a new terminal is needed, and the vocabulary (TF19.3).

*Test:* `tests/test_f19_cookbook.sh` — every one of the five settings and all
three script names appear in the concepts file; it contains no `FNN`/`TFNN`
string; it states both Makefile locations. **Not yet written** (TF19.10).

## TF19.3 — write the vocabulary section

**Status**: done

**Description**: Short definitions, and it must **resolve the host/mode
collision explicitly** instead of leaving it implicit. `02-doc/notes.md` names
four *hosts* — the box, the robot, the Mac, the VM — while the cookbook names
four *modes* — Pi, VM, Docker, cloud. The Mac is a host but not a mode; Docker
is a mode but not a host. A reader who meets both lists without being told they
are different axes will conflate them.

Also: overlay and underlay, `rosdep`, `colcon`, native versus container, and
*the box* as shorthand for a cloud machine.

**Done 2026-09-26** as the *Words we use* section of
`02-doc/cookbook-concepts.md` rather than a separate file — it is short, and
splitting it would have meant a reader meeting a term before its definition.

*Test:* `tests/test_f19_cookbook.sh` — the vocabulary section defines each
term, and says in so many words that hosts and modes are different axes.
**Not yet written** (TF19.10).

## TF19.4 — the Raspberry Pi recipe

**Status**: not done

**Description**: Blank microSD to a working robot, top to bottom, self
contained. Absorbs the shared flashing and first-boot steps currently stranded
in `howto.md`. Names `DOME_TARGET=pi` once as a fact and moves on.

*Test:* `tests/test_f19_cookbook.sh` — the recipe names no setting that the
concepts chapter does not define; contains no `FNN`/`TFNN`; contains no
`Scenario N`; its command blocks put each command on its own line.

## TF19.5 — the virtual machine recipe

**Status**: not done

**Description**: An installed Ubuntu 24.04 guest to a working dev environment.
Must keep the one hard prerequisite the current guide is right to shout about:
**24.04 specifically**, because other releases fail partway through with
confusing package errors. States plainly what a VM does not have — no camera,
lidar, or motors.

*Test:* same shape as TF19.4, plus: the recipe states the 24.04 requirement.

## TF19.6 — the container-on-a-Pi recipe

**Status**: not done

**Description**: Build on a Mac, push, pull and run on a Pi. Scope depends on
TF19.0's fourth decision: if the image is not verified, the recipe says so as a
present-tense fact ("this path has not been exercised recently") rather than
implying the same confidence as the other three.

*Test:* same shape as TF19.4. If the recipe carries an unverified note, assert
it is present, so removing it later is a deliberate act.

## TF19.7 — the rented cloud machine recipe

**Status**: not done

**Description**: Cloud-init template to a working remote dev host, built on
`cloud-howto.md` and absorbing the parts of `oci-howto.md` still worth having:
account signup, OCIDs, and the capacity error a reader will actually hit. Uses
`DOME_TARGET=cloud` and `REPOS_CONFIG=SAFE`, and keeps the public-desktop
safety material rewritten as instructions rather than as findings.

**Do not silently propagate `oci-howto.md`'s `DOME_TARGET=vm`.** Per the
feature's scope this is not fixed here — log it as a chore.

*Test:* same shape as TF19.4, plus: the recipe writes `DOME_TARGET=cloud`, and
`DOME_TARGET=vm` appears nowhere in it.

## TF19.8 — retire the old guides

**Status**: not done

**Description**: Move `oci-howto.md` to `archive/`. Remove `howto.md`,
`pi-howto.md`, `vm-howto.md`, `docker-howto.md` and `cloud-howto.md` once the
recipes replace them. Repoint `README.md` per TF19.0's second decision, and fix
every surviving inbound link.

`spec.md`, `notes.md`, `current.md`, `history.md` and `manifest-format.md`
stay — they are builder documents, and the history has to live somewhere. The
point is that it stops living in the reader's path.

*Test:* `tests/test_f19_cookbook.sh` — no retired filename is referenced from
`README.md` or any cookbook file, and no cookbook file links to `archive/`.
A repo-wide link check for the removed names, allowing historical mentions in
`current.md`, `history.md`, `chores.md` and the feature/task files.

## TF19.9 — read it as a newcomer would

**Status**: not done

**Description**: Read the cookbook start to finish against TF19.1's checklist
and confirm nothing still-needed was dropped. Then follow one recipe — the VM
one is cheapest — on a genuinely fresh machine, changing nothing, and note
every place a reader would have to guess or look elsewhere.

*Test:* manual, and deliberately so: whether prose reads well and whether a
recipe actually works cannot be established by `grep`. Record the command run,
the setup, what was expected and what actually happened, per the repo's manual
test convention.

## TF19.10 — the F19 test suite

**Status**: not done

**Description**: Finalize `tests/test_f19_cookbook.sh`. Beyond the per-step
assertions, two checks over every cookbook file at once:

- **No project archaeology.** No `FNN`/`TFNN` string, no `Scenario N`, and no
  link into `03-features/`, `04-tasks/` or `05-issues/`.
- **No orphaned settings.** Collect every `DOME_*`/`REPOS_CONFIG` token used
  in any recipe and assert each is defined in the concepts chapter. This is the
  mechanical form of the rule the recipes exist under, and the one most likely
  to rot as recipes get edited.

*Test:* this task is the test.
