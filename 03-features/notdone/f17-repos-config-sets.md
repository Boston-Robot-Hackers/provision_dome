# Feature description for feature F17

## F17 — Named repo sets via REPOS_CONFIG

**Priority**: Medium

**Done:** no

**Tasks File Created:** yes

**Tests Written:** no

**Test Passing:** no

**Description**: Replace the `DOME_CLONE_OVERRIDE` filter with a **named repo
set**. A single global, `REPOS_CONFIG`, holds a word — `SAFE`, `DOME`,
and others later — and each word names **its own manifest file** listing
exactly the repos that set clones.

The current scheme asks a *filter* question ("of everything in `repos.txt`,
which should be skipped?"), answered by a `PRIVATE_REPO` marker per line plus
a three-valued override. The new scheme asks a *selection* question ("which
set of repos is this host building?"), answered by one word and one file. What
a host clones becomes readable from a single file instead of being computed
from markers and a flag.

### Naming and value semantics

**The global is `REPOS_CONFIG`** — decided 2026-09-26. This is a **deliberate
exception** to the `DOME_` prefix carried by every other global in
`manifest/config.txt` (`DOME_USER`, `DOME_TARGET`, `DOME_MODE`,
`DOME_DESKTOP`, `DOME_VNC_ACCESS`). Recorded here so it reads as a decision
rather than an oversight, and so nobody "corrects" it later.

The value is one of two kinds:

- **`NONE`** — a **reserved word**: clone nothing at all. It maps to no file,
  and `manifest/repos-none.txt` must never be created. Carried over from
  `DOME_CLONE_OVERRIDE=NONE`, so that behavior survives the migration.

- **Any other word** — a **scheme name**, mapped to exactly one file:
  `SAFE` → `manifest/repos-safe.txt`. Value uppercase, filename lowercase.

An unknown name — not `NONE`, and no matching file — is a **hard error naming
the path it looked for**. Never a silent fallback to a default set, and never
an empty clone, which would look like success. An unset `REPOS_CONFIG` takes
the `config.txt` default rather than being treated as `NONE`.

---

## The sets

### `SAFE` — a minimal ROS 2 dev environment

**Two repos, both public, no GitHub key required.**

```
[root]
https://github.com/campusrover/rosutils.git rosutils

[ros_ws]
https://github.com/dfki-ric/better_launch.git better_launch devel
```

`[root-pi]` and `[uros_ws]` are present but empty, so the file documents that
the omission is intentional rather than forgotten.

Deliberately **excluded**, and the reasoning, since "safe" is otherwise
ambiguous:

- **All `dome*`, `j3`, `explore`, `metawtf`, `ros2diag`, `status_panel`** —
  private, and the point of the set.
- **`linorobot2`, `linorobot2_hardware`** — named by the user.
- **`micro-ROS-Agent`, `micro_ros_msgs`** — named by the user. Note these are
  *third-party*, which is what establishes that SAFE means "minimal", not
  merely "nothing of mine."
- **`depthai-python`, `ldlidar_stl_ros2`** — third-party, but hardware
  drivers, and SAFE targets hosts with no hardware.
- **`seeed-linux-dtoverlays`, `libcamera-apps`, `mic_hat`** — Pi peripherals.

### `DOME` — the full robot set

Everything currently in `manifest/repos.txt`, unchanged, with the
`PRIVATE_REPO` markers stripped. **This is the default**, so a Pi build
behaves exactly as it does today.

### Adding a set later

Drop in `manifest/repos-<name>.txt` and use the name. No code change — which
is the main win over the current scheme, where a new selection rule means new
logic in `manifest_should_clone`.

---

## What is deleted

Per the decision to replace rather than layer, one mechanism survives, not
two:

- **`DOME_CLONE_OVERRIDE`** — the flag, its cascade in
  `bare-metal-build.sh:28-30`, and its `config.txt` documentation.
- **`manifest_should_clone`** and **`manifest_validate_clone_override`** in
  `manifest/lib.sh`.
- **The `PRIVATE_REPO` marker** on all 17 lines, and the parse support for it
  in `manifest_parse_repo`.
- **`manifest/repos.txt`**, renamed to `manifest/repos-dome.txt`.

This supersedes **F10**'s mechanism. F10's feature and task files stay in
`done/` as history — they record why the marker existed, which is worth
keeping even though the marker does not.

### The one guard worth replacing

`manifest_should_clone` had a genuinely useful error path: an SSH URL *not*
marked `PRIVATE_REPO` was refused rather than attempted, so a mis-marked line
could not silently demand a key. Deleting markers deletes that guard.

Replace it with something cheaper and stronger, **derived rather than
declared**: before cloning, if the selected set contains any `git@` or
`ssh://` URL, verify the credential once and fail immediately with a clear
message. A set of all-HTTPS URLs — which `SAFE` is by construction — needs no
key and no check. This is one boundary check, replacing a per-line marker
nobody can forget to write.

---

## Consumers to change

The flag reaches further than it looks. Collected so the task list is not
discovered halfway through:

- **`scripts/bare-metal-build.sh`** — resolve `REPOS_CONFIG`, select the
  file, drop the `manifest_should_clone` call in `clone_section` (line 67) and
  the provenance echo (line 40).
- **`manifest/lib.sh`** — delete the two functions; add a resolver that maps
  a set name to a path and errors if it is missing.
- **`manifest/config.txt`** — replace the `DOME_CLONE_OVERRIDE` block with
  `REPOS_CONFIG=DOME`.
- **`Dockerfile:45`** — reads `/manifest/repos.txt` with its own inline `awk`,
  bypassing `lib.sh` entirely. **It must take the set too, or the Docker image
  silently keeps cloning the full list.** This is the same split-brain that
  bit F10 (`current.md`: "the `Dockerfile` has its own `clone_section`").
- **`host-file-templates/cloud/user-data.template:44`** —
  `DOME_CLONE_OVERRIDE=PUBLIC_ONLY` becomes `REPOS_CONFIG=SAFE`.
- **Docs** — `cloud-howto.md` (Step 4 and the "private cloud dev box"
  section), `pi-howto.md`, `vm-howto.md`, `docker-howto.md`, `README.md:90`,
  and `manifest-format.md`.
- **Tests** — `tests/test_f10_repo_cloning.sh` (47 checks) is written against
  the old mechanism and needs rewriting as the F17 suite.
  `tests/test_f01_manifest.sh:140` asserts every section extracts **> 0**
  entries, which SAFE's empty `[root-pi]`/`[uros_ws]` would fail.

**Checked, no change needed:** `clone_section uros_ws` runs unconditionally
but only `ros2_ws` is built by colcon, so SAFE's empty `uros_ws` just creates
an empty directory.

---

## Design risk: drift between set files

Worth stating plainly, because it is the cost of the approach and it has
already bitten this repo twice.

Separate files **duplicate entries**. `micro-ROS-Agent` and `micro_ros_msgs`
already appear twice *within* `repos.txt` (`[ros_ws]` and `[uros_ws]`); across
several sets, any repo in more than one set is written more than once, and the
copies can drift in URL, dest or branch. Two chores in `04-tasks/chores.md`
record silent breakage from exactly this class of hand-edit — the `[ros_ws]`
indentation that zeroed a whole section, and `dome_telemetry` missing for
months.

**Mitigation, and it should be a task rather than an afterthought:** a test
that parses every `manifest/repos-*.txt` and asserts that any `dest` appearing
in more than one set has an identical URL, dest and branch everywhere. That
catches drift at test time without adding runtime machinery, and keeps the
plain-file simplicity that motivated the design.

---

## Open decisions

**Resolved 2026-09-26:** the global is `REPOS_CONFIG` (no `DOME_` prefix), and
`NONE` is a reserved value meaning clone nothing. See *Naming and value
semantics*.

Still open:

1. **Is `DOME` the right name for the full set?** **Accepted as `DOME` for
   now** (2026-09-26) — it is the word used in the original request. The
   reservation stands: it reads oddly next to the `dome*` repos and the
   `DOME_` globals, where "dome" means the project rather than a subset, and
   it is the only name-shaped value besides reserved `NONE`, so it sets the
   convention for every set added later. `FULL` or `ROBOT` remain available
   at the cost of one `git mv` and a default change.
2. **Does a set imply a target?** `SAFE` on a Pi would clone no Pi peripheral
   repos. Assumed correct — `DOME_TARGET` and `REPOS_CONFIG` stay
   independent — but it means two flags can disagree sensibly and should be
   confirmed.
3. **Migrate the live box.** `dome-cloud-1` has `DOME_CLONE_OVERRIDE=PUBLIC_ONLY`
   in its `manifest/user.txt`, which stops meaning anything. It needs
   `REPOS_CONFIG=SAFE`, or it falls back to the `DOME` default and starts
   demanding a GitHub key.

## How to Demo

**Setup**: a clean checkout; no repos cloned yet.

**Steps**:

1. Set `REPOS_CONFIG=SAFE` in `manifest/user.txt` and run
   `sudo scripts/bare-metal-build.sh` on a host with **no GitHub key**.
2. Inspect `~/` and `~/ros2_ws/src`.
3. Set `REPOS_CONFIG=DOME` on the Pi and run the same script.
4. Set `REPOS_CONFIG=NONE` and run it.
5. Set `REPOS_CONFIG=NONSENSE` and run it.
6. `touch manifest/repos-none.txt`, set `REPOS_CONFIG=NONE`, run it.
7. `grep -rn 'DOME_CLONE_OVERRIDE\|PRIVATE_REPO' scripts/ manifest/ Dockerfile*`

**Expected output**:

1. Completes with no credential prompt and no failure.
2. Exactly `rosutils` and `better_launch` are present; no `dome*`, no
   `linorobot*`, no `micro_ros*`.
3. The full set clones, identical to today's behavior.
4. Clones nothing, and **says so** — the reserved value is reported, not
   mistaken for an empty or missing set.
5. Fails immediately, naming `manifest/repos-nonsense.txt` as not found — no
   silent fallback to a default set, and no empty clone that would read as
   success.
6. Still clones nothing: `NONE` is reserved, so a file of that name is
   ignored rather than silently shadowing the reserved meaning.
7. No matches: one mechanism, not two.
