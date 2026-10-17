# Feature description for feature F19

## F19 — A user cookbook to replace the guide set

**Priority**: Medium

**Done:** no

**Tasks File Created:** yes

**Tests Written:** no

**Test Passing:** no

**Description**: Replace the current guide set with a **cookbook written for
the person using this tool**, not for the person who built it. It explains the
concepts and the vocabulary once, up front, then gives one clean recipe per
major mode. It mentions **no feature numbers, no task numbers, no history, and
nothing about why the code became what it is**.

Numbered **F19**, not F18: `02-doc/current.md` already reserves F18 for the
proposed *summary target*. Leaving that number free avoids a collision.

### Why this is a feature and not a chore

It changes what the documentation *is*, not just its wording: files are
retired, the reader's entry point moves, and the split between "how to use it"
and "why it is like this" becomes a rule rather than an accident. That is a
behavior change for every reader, so it gets a spec.

---

## The problem, concretely

**The guides carry project history the reader has no use for.** `oci-howto.md`
names features or tasks **12 times** and opens by explaining that it documents
a *superseded* manual path, with its own workarounds, that "folds into
`cloud-howto.md`". A reader following it is following a historical record.
`cloud-howto.md` names features 3 times; `howto.md` carries an *"Ordering
note"* about an unlanded feature and its scenario numbering.

**Two cloud guides overlap and disagree.** `cloud-howto.md` (336 lines) and
`oci-howto.md` (263 lines) both go from a rented cloud VM to native ROS.
They disagree on a value that matters: `oci-howto.md` writes
`DOME_TARGET=vm` for an OCI box, which **skips the swap** that a small cloud
shape needs, while `cloud-howto.md` uses `DOME_TARGET=cloud`. Nothing tells the
reader which to follow.

**The concepts are never explained in one place.** A reader meets
`DOME_TARGET`, `DOME_MODE`, `DOME_DESKTOP`, `DOME_VNC_ACCESS` and
`REPOS_CONFIG` scattered through whichever guide they picked, each explained
just enough for that guide. The manifest-as-single-source-of-truth idea — the
thing that makes the whole tool comprehensible — lives in `spec.md`, a
document written for a builder.

**"Scenario 1..4" is builder vocabulary.** It requires a lookup table. Worse,
the project has **two** four-item vocabularies that do not line up, and
`notes.md` names them both: the four **hosts** are *the box, the robot, the
Mac, the VM*; the four **modes** are *Pi, VM, Docker, Cloud*. The Mac is a host
but not a mode; Docker is a mode but not a host. The cookbook must not inherit
this collision — it is the single most likely thing to confuse a reader.

**Parallel guides have drifted.** `pi-howto.md` (314 lines) and
`vm-howto.md` (315 lines) are near-duplicates differing mainly by
`DOME_TARGET`, so a fix to a shared step lands in one and not the other. This
already happened twice to `manifest/repos.txt` guidance.

---

## Scope

### The four modes, in the reader's words

Named by **what the reader has in front of them**, with the internal setting
given once as a fact and then not belaboured:

1. **A Raspberry Pi** — a real robot. `DOME_TARGET=pi`.
2. **A virtual machine on your own computer** — development, no hardware.
   `DOME_TARGET=vm`.
3. **A container image on a Pi** — built on a Mac, pulled and run.
   `DOME_MODE=docker`.
4. **A rented cloud machine** — remote dev host, reachable from anywhere.
   `DOME_TARGET=cloud`.

Each recipe is followed top to bottom with no jumping between them, which is
the one property of the current guides worth keeping.

### A concepts chapter, read once

Before the recipes, in this order:

- **What this tool does**, in a paragraph: you supply a blank machine, it
  supplies a working ROS 2 workspace.
- **The manifest is the source of truth.** Lists of packages and repos live in
  `manifest/`; the scripts only execute them. This is what "add a package" and
  "add a repo" mean later.
- **`config.txt` vs `user.txt`.** Project defaults versus your local,
  untracked overrides, and the order they resolve in.
- **The five settings**, each in one or two sentences: `DOME_TARGET`,
  `DOME_MODE`, `DOME_DESKTOP`, `DOME_VNC_ACCESS`, `REPOS_CONFIG`.
- **Repo sets.** `REPOS_CONFIG` names a set; `DOME` is the whole robot and
  needs a GitHub key, `SAFE` is a minimal environment and needs none.
- **The three scripts and what each one owns** — `host-setup.sh` (the user
  and the host), `bare-metal-base.sh` (packages), `bare-metal-build.sh`
  (repos, then the workspace build). Knowing which to re-run is most of
  day-to-day use.
- **The two Makefiles**, which are genuinely confusing today: the repo-root
  one runs **on the machine you built**, and `terraform/oci/Makefile` runs
  **on your own computer** to control a cloud machine.
- **Workspace and shell** — `~/ros2_ws`, why a new terminal is needed after a
  build, what `bru` is.

### A words-we-use section

Short, and it must **resolve the host/mode collision explicitly** rather than
pretend it isn't there. Also: overlay and underlay, `rosdep`, `colcon`, native
versus container, and *the box* as shorthand for a cloud machine.

### Everyday recipes

One short chapter, task-titled, not concept-titled: get the latest code, add a
system package, add a Python package, add a repo, rebuild after a change,
switch repo sets, start and stop a cloud machine, reach a desktop.

### Troubleshooting by symptom

Keyed on **what the reader sees**, not on the subsystem at fault: `ros2` not
found in a new shell; a build that stops at the first clone asking for a
GitHub key; a desktop URL that does not load; an unreachable cloud machine.

---

## What is retired

- **`oci-howto.md`** — superseded by its own admission, and the source of most
  feature references and the `DOME_TARGET` disagreement. Its still-useful
  parts (OCI account signup, OCIDs, capacity errors) move into the cloud
  recipe or its troubleshooting; the rest goes to `archive/`.
- **`howto.md`** — its comparison table becomes the cookbook's *which mode do
  I want* section. The scenario numbering and ordering note do not survive.
- **`pi-howto.md`, `vm-howto.md`, `docker-howto.md`, `cloud-howto.md`** —
  replaced by the four recipes. Whether the cookbook is one file or five is a
  task-phase decision; see *Open questions*.

**Kept, and explicitly out of scope:** `spec.md`, `notes.md`, `current.md`,
`history.md`, `manifest-format.md`. These are builder documents and the
history has to live *somewhere* — the point is that it stops living in the
reader's path. `manifest-format.md` stays as the reference the cookbook links
to for exact file syntax.

---

## Constraints

- **No feature or task numbers, and no `FNN`/`TFNN` strings**, anywhere in the
  cookbook. This is mechanically checkable and should be a test.
- **No history, no rationale-by-archaeology, no "this used to be".** If a
  reader would act identically without the sentence, it does not belong.
- Every command block is copy-pasteable, with commands on their own lines.
- Every setting named in a recipe is defined in the concepts chapter, once.
- No claim of a verified time; the README's existing wording on this is right.

---

## Deliberately not in scope

- **No script, manifest or behavior changes.** If the rewrite exposes a real
  defect — and the `oci-howto.md` `DOME_TARGET=vm` mismatch suggests it will —
  it is logged as a chore or an issue, not fixed here. A documentation feature
  that quietly changes behavior is unreviewable.
- **No new mode.** Running the container image on a Mac is a separate,
  unlanded piece of work; the cookbook documents four modes, and gains a fifth
  when there is one.

---

## Decisions (2026-09-26)

All four resolved by the user before writing began.

1. **Five files.** A concepts file plus one per mode. The drift risk is real —
   it is what the current guides demonstrate — so the recipes are held to the
   rule mechanically: TF19.10 asserts that every setting a recipe names is
   defined in the concepts chapter.
2. **The README becomes a short front door.** It points at the cookbook instead
   of half-explaining concepts itself, so it stops being a fifth place a
   concept is partly defined.
3. **No behavior fixes here.** The `oci-howto.md` `DOME_TARGET=vm` mismatch is
   logged as a chore, not fixed, so the documentation rewrite stays reviewable
   as a documentation rewrite.
4. **The container recipe is marked as not recently exercised**, in the present
   tense, as a fact about the path's current state rather than a history note.
   The other three recipes carry no such mark, which is what makes it
   informative.

## Original open questions (resolved above)

1. **One file or five?** A single `02-doc/cookbook.md` guarantees the concepts
   are read once and cannot drift, but becomes long. Five files — concepts plus
   four recipes — reads better and risks re-drifting, which is the failure the
   current guides already demonstrate. **Recommendation: one concepts file plus
   one file per mode, with the recipes forbidden from re-explaining a concept.**
2. **Does the README shrink or grow?** It already does a decent job of *which
   setup do I want*. It should probably become a short front door pointing at
   the cookbook, rather than a fifth place where concepts are half-explained.
3. **How much of the cloud recipe's safety material survives?**
   `cloud-howto.md` has a well-earned section on treating a public desktop as
   hostile. It is not history and it is not feature talk, so it should stay —
   but it needs rewriting as instructions rather than as findings.
4. **Is `docker-howto.md`'s recipe trustworthy enough to publish?**
   `notes.md` calls the container image the least debugged part of the project
   and says to treat its behavior as unverified. Writing a confident recipe for
   it may overstate reality. Options: verify it first, or mark that recipe as
   the one path not recently exercised — which is a fact about now, not history.

---

## How to Demo

**Setup**: a clean checkout, and a reader who has not seen this project.

**Steps**:

1. Open the cookbook's entry point and read the concepts chapter.
2. Pick the Raspberry Pi recipe and follow it top to bottom without opening
   any other file.
3. `grep -rnE '\b(F[0-9]{2}|TF[0-9]{2})\b'` across the cookbook files.
4. `grep -rn 'Scenario [0-9]'` across the cookbook files.
5. Look for `oci-howto.md` in `02-doc/`.
6. Ask what `REPOS_CONFIG=SAFE` does, and where `DOME_TARGET` is set, having
   read only the concepts chapter.
7. From the cookbook alone, determine which Makefile to run on which machine.

**Expected output**:

1. The five settings, the manifest idea, the two Makefiles and the host/mode
   vocabulary are all explained, with no feature numbers and no history.
2. The recipe is self-contained: every command runnable in order, every
   setting it names already defined.
3. No matches.
4. No matches — the modes are named by what the reader has, not numbered.
5. Not there; it is in `archive/`, and nothing in the reader's path links to it.
6. Both answerable from the concepts chapter alone.
7. Answerable without guessing: root Makefile on the built machine,
   `terraform/oci/Makefile` on your own computer.
