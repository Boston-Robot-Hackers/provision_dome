# Feature description for feature F12

## F12 — per-mode repo transport (SSH for full builds, HTTPS under PUBLIC_ONLY)

**Priority**: Low

**Done:** no

**Tasks File Created:** no

**Tests Written:** no

**Test Passing:** no

**Description**:

Let a single repo clone over **SSH (read-write) on a full build** and over
**HTTPS (read-only) under `DOME_CLONE_OVERRIDE=PUBLIC_ONLY`**, instead of
forcing one transport for all targets.

### Why

Today `manifest/repos.txt` carries **one URL per repo line**, and F10's
`DOME_CLONE_OVERRIDE` only decides *whether* a line is cloned — it never
rewrites the transport. So a repo is either SSH everywhere or HTTPS
everywhere.

`rosutils` exposed the gap. It is a public, campusrover-shared tool we
*consume*. To keep the internet-facing OCI dev host credential-free, it was
switched to a plain HTTPS URL (commit `bc83acf`), which also made it
read-only on the Pi, VM, and local Docker builds — where an SSH clone
previously allowed `git push`. That trade was accepted for now, but the
general shape recurs: a repo that should be **pushable on trusted targets**
yet **credential-free and read-only on an untrusted cloud box**.

### Scope

- A repo entry can declare *both* a read-write SSH URL and a read-only HTTPS
  URL (exact manifest syntax is a task-phase decision — e.g. a paired field
  or a `PUBLIC_HTTPS=<url>` marker on a `PRIVATE_REPO` line).

- Selection is driven by the existing `DOME_CLONE_OVERRIDE`: **unset →** SSH
  URL; **`PUBLIC_ONLY` →** HTTPS URL (cloned, not skipped); **`NONE` →**
  still nothing.

- The `manifest_should_clone` / `manifest_parse_repo` helpers in
  `manifest/lib.sh` own the choice, so the Dockerfile and
  `bare-metal-build.sh` inherit it unchanged.

### Out of scope

- Changing which repos are public. This feature is about *transport
  selection*, not visibility.

- Rewriting arbitrary SSH URLs to guessed HTTPS equivalents. A repo opts in
  by declaring its HTTPS URL explicitly; the helper never invents one.

- Any change to the credential-free guarantee: under `PUBLIC_ONLY` the build
  must still never require or touch a GitHub key.

### Open questions (resolve before tasks)

- **Manifest syntax:** second URL field vs. `PUBLIC_HTTPS=<url>` marker vs. a
  paired line. Whatever is chosen must keep the current single-URL lines
  valid (no forced migration of every entry).

- **A private repo with no HTTPS URL under `PUBLIC_ONLY`:** skip it (current
  behavior) or error. Leaning skip, to preserve today's semantics.

- **`rosutils` specifically:** once this lands, does it move back to an
  SSH+HTTPS pair (pushable on Pi/VM again), or stay HTTPS-only? Decide with
  the user — it drove the feature but may be fine as-is.

## How to Demo

**Setup**: a `manifest/repos.txt` with one repo declaring both an SSH and an
HTTPS URL; run the repo-parsing path (or `bare-metal-build.sh`'s
`clone_section`) with `DOME_CLONE_OVERRIDE` set two ways.

**Steps**:

1. With `DOME_CLONE_OVERRIDE` unset, resolve that repo's clone URL.
2. With `DOME_CLONE_OVERRIDE=PUBLIC_ONLY`, resolve it again.

**Expected output**: step 1 yields the `git@…` SSH URL (read-write); step 2
yields the `https://…` URL (read-only) and the repo is cloned, not skipped;
`NONE` still clones nothing; and no plain single-URL entry's behavior
changes.
