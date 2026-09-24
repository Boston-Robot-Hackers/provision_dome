# TF10 Description for Feature F10

**Date Created:** 2026-09-24

Feature: selectable repo cloning via a `PRIVATE_REPO` marker in
`manifest/repos.txt` and a `DOME_CLONE_OVERRIDE` flag. Purely additive —
unset default reproduces today's behavior, so `pi`/`vm`/`docker` are unchanged.

**Execution order: TF10.2 first, then TF10.0.** The existing parser
(`read -r repo dest branch`) would read `PRIVATE_REPO` as a branch and run
`git clone --branch PRIVATE_REPO`, so the markers must not land until every
parser tolerates them. Two parsers exist: `bare-metal-build.sh` and the
`Dockerfile` (`clone_section` is duplicated in both). Both use one shared
helper in `manifest/lib.sh`.

## TF10.0 — Mark private repos in repos.txt
**Status**: done
**Description**: Append the bareword marker `PRIVATE_REPO` to every
credential-requiring line in `manifest/repos.txt` — i.e. every `git@github.com:`
(SSH) line across all sections (`campusrover/*`, `Boston-Robot-Hackers/*`,
`pitosalas/*`). Leave every `https://` line unmarked. Do not change URLs,
destinations, branches, or section order.

**Do this after TF10.2.** Once every parser tolerates the marker this is data
only; behavior does not change until the gate lands (TF10.3), and never
changes with the override unset.

Test: in `tests/test_f10_repo_cloning.sh`, assert every `git@` line in
`repos.txt` ends with / contains `PRIVATE_REPO`, and no `https://` line does.

## TF10.1 — Resolve DOME_CLONE_OVERRIDE (unset by default)
**Status**: done
**Description**: Document `DOME_CLONE_OVERRIDE` in `manifest/config.txt` as a
**commented** entry (unset by default), in the comment style of `DOME_TARGET`/
`DOME_DESKTOP`, listing values `PUBLIC_ONLY` and `NONE` and stating that unset
= clone everything.

In `bare-metal-build.sh`, resolve it with the established precedence **but
tolerating absence** (it has no config default): `env > user.txt > empty`. Use
the same `grep … || true` pattern as the `DOME_TARGET` user.txt read — not
`manifest_config`, which errors on a missing key. Echo the resolved value like
the other vars.

Test: stub-resolve in the test suite — env wins over user.txt; user.txt used
when env unset; empty when neither present; an unrecognized value is treated as
unset-equivalent only if TF10.3 says so (see there).

## TF10.2 — Parse the PRIVATE_REPO marker (order-independent)
**Status**: done
**Description**: Add `manifest_parse_repo` to `manifest/lib.sh` and use it in
**both** `clone_section` copies — `scripts/bare-metal-build.sh` and the
`Dockerfile` (which sources `/manifest/lib.sh`). In the Dockerfile the marker
is tolerated but never acted on, so image behavior is unchanged. Change
`clone_section` so it recognizes `PRIVATE_REPO`
**wherever it appears** on a line and still resolves the optional branch. Read
the trailing fields, detect the marker token, and treat the remaining non-marker
token (if any) as the branch. Must keep working for existing lines:
`url dest`, `url dest branch` (e.g. `better_launch … devel`), and now
`url dest PRIVATE_REPO` and `url dest branch PRIVATE_REPO`.

Test: feed the parser fixture lines covering all four shapes; assert correct
`(repo, dest, branch, is_private)` for each.

## TF10.3 — Gate clone_section on the override
**Status**: done
**Description**: Apply `DOME_CLONE_OVERRIDE` in `bare-metal-build.sh`:

- **unset** → clone every line (today's behavior).
- **`PUBLIC_ONLY`** → skip lines carrying `PRIVATE_REPO`.
- **`NONE`** → skip all cloning (still create workspace dirs; `clone_section`
  becomes a no-op). Print a clear skip line, matching the swap/desktop skip
  style.

Fail with a clear error on an unrecognized value rather than guessing (per the
style guide's "report, don't guess").

Test: fixture-based, like `tests/test_f05_dome_mode.sh` — with a stub `git`,
assert: unset clones all; `PUBLIC_ONLY` clones only unmarked; `NONE` clones
none; an unrecognized value exits non-zero.

## TF10.4 — SSH-clone safety net
**Status**: done
**Description**: When the override is `PUBLIC_ONLY` or `NONE`, the build must
**never invoke a `git@`/`ssh://` clone**, even for a line left unmarked by
mistake. Before cloning under those modes, if a to-be-cloned URL is SSH, stop
with an error naming the repo (so a mistagged private repo can't silently
require or expose the account key). Under the unset default this check is
inert.

Test: under `PUBLIC_ONLY`, a fixture with an **unmarked** `git@` line causes a
non-zero exit with a message naming that repo, and no clone is attempted.

## TF10.5 — F07 cloud-init + cloud-howto integration
**Status**: done
**Description**: Make the cloud host credential-free by default:

- `host-file-templates/cloud/user-data.template` writes
  `DOME_CLONE_OVERRIDE=PUBLIC_ONLY` into `manifest/user.txt` alongside
  `DOME_USER`/`DOME_TARGET=cloud`.
- `02-doc/cloud-howto.md`: state that the cloud host clones **public repos
  only** and needs **no GitHub key**; adjust/remove the host-GitHub-key step
  accordingly, and note how to switch to full private access deliberately
  (`DOME_CLONE_OVERRIDE` unset + a key) if the user wants their own private
  cloud dev box.

Depends on TF10.1–TF10.3. Coordinate wording with the F07 close-out.

**Found and fixed during the live check (2026-09-24):** `manifest/bashrc`
sourced the private `rosutils`, so under `PUBLIC_ONLY` a new shell had no
`ros2`. `bashrc` now sources `rosutils` only if present, else the ROS underlay
and `~/ros2_ws` overlay. Verified on OCI: a `PUBLIC_ONLY` build as a fresh
user succeeded (4 public packages, 1m18s) and `ros2` works in a new shell.

Test: assert the template sets `DOME_CLONE_OVERRIDE=PUBLIC_ONLY` and contains
no private-key material; assert `cloud-howto.md` mentions `PUBLIC_ONLY` and
"no GitHub key". Full first-boot behavior stays a manual test in TF07.0's style.

## TF10.6 — F10 test suite + regression check
**Status**: done
**Description**: Consolidate TF10.0–TF10.5's checks into
`tests/test_f10_repo_cloning.sh`, following `tests/test_f05_dome_mode.sh`'s
`pass`/`fail` helpers and headings. Runs on the Mac with no cloud instance;
stub `git`. Include an explicit **regression assertion** that with the override
unset, the set of repos `clone_section` would clone equals the full
`repos.txt` set for `pi`, `vm`, and `docker` — proving the additive guarantee.

Confirm the whole suite — all `tests/test_f0*.sh` plus this one — passes before
F10 is closed.
