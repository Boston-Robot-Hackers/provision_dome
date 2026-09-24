# Feature description for feature F10

## F10 — Selectable repo cloning (no credentials or private clones on shared hosts)

**Priority**: High
**Done:** yes
**Tasks File Created:** yes
**Tests Written:** yes
**Test Passing:** yes

**Description**: Let a build **exclude the user's private repositories** so a
cloud or otherwise shared/untrusted host never receives a push-capable GitHub
credential and never gets clones of the user's private source. Off by default:
existing builds are unchanged.

## Why

`scripts/bare-metal-build.sh` (`clone_section`) clones **every** repo listed in
`manifest/repos.txt`. That list mixes two kinds:

- **Private, SSH URLs** (`git@github.com:…`) — `campusrover/*`,
  `Boston-Robot-Hackers/*`, `pitosalas/*`. Cloning these needs an
  **account-level GitHub key**, which also has **push** rights, and it leaves
  copies of private source on the box.

- **Public, HTTPS URLs** (`https://…`) — micro-ROS, `better_launch`, luxonis,
  etc. These need **no credential**.

On the F07 cloud host this forced a push-capable key onto an internet-facing
box and cloned all the private repos there. A viewer who reaches that host
(see the noVNC exposure work) could read the key and push to the user's repos.
This feature makes private clones and credentials **opt-out on shared hosts**.

## Hard constraint — purely additive

`pi`, `vm`, and `docker` must behave **exactly as they do today**. The override
is **unset by default**, which reproduces current behavior; only setting it
changes anything. See the `feedback-additive-features` note.

## Design

Repos are **marked**, and a single **override** decides whether the marked ones
are skipped.

### 1. Per-repo `PRIVATE_REPO` marker in `repos.txt`

A repo line may carry the bareword marker **`PRIVATE_REPO`**:

```
git@github.com:campusrover/dome.git            dome           PRIVATE_REPO
https://github.com/dfki-ric/better_launch.git  better_launch  devel
```

- Every credential-requiring repo (all current `git@…` lines) gets the marker.
- **Unmarked lines are always cloned** — so with no override set, the file
  behaves exactly as today.
- The parser recognizes `PRIVATE_REPO` **wherever it appears** on the line, so
  it never collides with the optional branch field.

### 2. Override flag `DOME_CLONE_OVERRIDE`

Resolved with the same `env > user.txt > config.txt` precedence as
`DOME_TARGET`/`DOME_DESKTOP`. **Unset by default.**

- **Unset (default)** — clone every repo line, marker ignored for selection.
  **This is today's behavior; `pi`/`vm`/`docker` are untouched.**
- **`PUBLIC_ONLY`** — skip every `PRIVATE_REPO` line; clone only repos needing
  **no credential**.
- **`NONE`** — skip cloning entirely (workspace dirs and base packages still
  set up; the user brings source themselves).

The name keeps the existing `DOME_*` convention; the planned project-wide
`dome`→`PROVISION_ROS` rename (a **separate feature**) will sweep it with the
rest.

### 3. Safety net

When the override is `PUBLIC_ONLY` (or `NONE`), the build **refuses to run any
`git@`/`ssh://` clone**, even if a repo were left unmarked — so a private repo
can never silently pull in or require the account key.

### 4. F07 integration (the actual security win)

The F07 cloud-init template sets **`DOME_CLONE_OVERRIDE=PUBLIC_ONLY`** and
**installs no GitHub key**. The shared/cloud host then carries no push-capable
credential and no private source. `cloud-howto.md` is updated to match.

## Add

- `PRIVATE_REPO` markers on every private (`git@…`) line in
  `manifest/repos.txt`.
- `DOME_CLONE_OVERRIDE` documented in `manifest/config.txt` (commented, unset
  by default), following the `DOME_TARGET`/`DOME_DESKTOP` comment style.
- Resolve `DOME_CLONE_OVERRIDE` in the build with the established precedence;
  gate `clone_section`; add the ssh-clone safety net.
- Cloud-init template + `cloud-howto.md` changes for the credential-free path
  (`PUBLIC_ONLY`, no key).
- A dedicated test file for the feature.

## Do not change

- `DOME_TARGET`, `DOME_MODE`, `DOME_DESKTOP` semantics.
- The clone behavior of `pi`, `vm`, `docker` (guaranteed by the unset default).
- Repo destinations, branches, or section layout in `repos.txt`.
- Any `dome` naming — the rename is a separate future feature; this feature
  adds no new `dome` strings beyond the consistent `DOME_CLONE_OVERRIDE` flag.

## Values (resolved)

`DOME_CLONE_OVERRIDE`: unset (default, clone all), `PUBLIC_ONLY` (skip
`PRIVATE_REPO` lines), `NONE` (clone nothing). Cloud default: `PUBLIC_ONLY`.

## How to Demo

**Setup**: a checkout with `PRIVATE_REPO` markers on the private lines.

**Steps**:

1. `DOME_CLONE_OVERRIDE` unset → `bare-metal-build.sh` clones every repo, as
   today. `pi`/`vm`/`docker` runs are unchanged.
2. `DOME_CLONE_OVERRIDE=PUBLIC_ONLY` → only `https://` repos clone; no `git@`
   clone is attempted; no GitHub key required; private source absent.
3. `DOME_CLONE_OVERRIDE=NONE` → no repos clone; workspace dirs still created.
4. On a cloud host provisioned with `PUBLIC_ONLY`: no key on the box,
   `ros2 pkg list` shows only public/base packages.

**Expected output**: identical builds for the existing modes; a cloud host with
no push-capable credential and no private clones.
