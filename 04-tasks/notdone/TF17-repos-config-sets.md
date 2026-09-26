# TF17 Description for Feature F17

**Date Created:** 2026-09-26

Replace the `DOME_CLONE_OVERRIDE` filter with `REPOS_CONFIG`, a named repo set
that maps to its own manifest file. Each step names its test, or why one is
not feasible; real cloning needs network and root, so the suite uses the
static `grep`/parse style already used for the bare-metal scripts.

## Ordering hazard — read before starting

**TF17.5 must land before TF17.6, and they are not interchangeable.**

`manifest_parse_repo` currently treats any trailing token that is not
`PRIVATE_REPO` as a git branch. Simplify the parser while the markers are
still in the file and `PRIVATE_REPO` lands in `REPO_BRANCH`, producing
`git clone --branch PRIVATE_REPO` on 17 repos.

This is the **mirror image** of the hazard recorded in
`04-tasks/done/TF10-selectable-repo-cloning.md`, where the parser had to land
*before* the markers for the same reason in reverse. Strip first, then
simplify.

Every step is meant to leave the tree working: TF17.1–TF17.4 preserve current
behavior exactly, because the `DOME` set is the old `repos.txt` content under
a new name.

## TF17.0 — record the decisions

**Status**: not done

**Decisions (2026-09-26):** the global is **`REPOS_CONFIG`**, deliberately
without the `DOME_` prefix the other globals carry. **`NONE`** is a reserved
value meaning clone nothing, mapping to no file. Any other value is a scheme
name mapped to `manifest/repos-<name>.txt`, lowercased. **`SAFE`** is
`rosutils` + `better_launch` only. **`DOME`** is the full set and the default.
`REPOS_CONFIG` and `DOME_TARGET` stay **independent**.

**Description**: Settle and record the spec's open questions so later steps do
not re-litigate them. `DOME` as the full-set name is accepted with a noted
reservation — it reads oddly beside the `dome*` repos and `DOME_` globals —
and `FULL`/`ROBOT` remain available at the cost of one `git mv` and a default
change.

*Test:* none — a decision.

## TF17.1 — add `manifest_repos_file` to lib.sh

**Status**: not done

**Description**: Add the name→file resolver to `manifest/lib.sh`. `NONE`
returns the empty string; any other name lowercases to
`<manifest_dir>/repos-<name>.txt` and **errors naming the path** if absent.
Purely additive — nothing calls it yet, so this step cannot change behavior.

Returning `""` for `NONE` rather than a missing file keeps "clone nothing"
structurally distinct from "set not found", which is what stops a broken
config from looking like a successful empty build.

*Test:* new `tests/test_f17_repos_config.sh` — call the resolver with `SAFE`
(expect the path), `NONE` (expect empty), and `NONSENSE` (expect non-zero exit
and the path named in the message).

## TF17.2 — create the two set files, markers intact

**Status**: not done

**Description**: `git mv manifest/repos.txt manifest/repos-dome.txt`, leaving
its contents **including the `PRIVATE_REPO` markers** untouched. Create
`manifest/repos-safe.txt` with `rosutils` and `better_launch`, plus empty
`[root-pi]` and `[uros_ws]` sections so the omission reads as deliberate.

Markers stay for now; TF17.5 removes them once nothing depends on them.

*Test:* extend `test_f17_repos_config.sh` — both files parse under
`clone_section`'s exact awk extraction; `repos-safe.txt` yields exactly
`rosutils` and `better_launch` and contains no `git@`/`ssh://` URL.

## TF17.3 — switch `bare-metal-build.sh` to the resolver

**Status**: not done

**Description**: Replace the `DOME_CLONE_OVERRIDE` cascade
(`bare-metal-build.sh:28-30`) with a `REPOS_CONFIG` cascade using the same
env > `user.txt` > `config.txt` precedence — this one *has* a `config.txt`
default, so it uses `manifest_config`. Pass the resolved file to
`clone_section` and delete the `manifest_should_clone` branch at line 67 and
the override echo at line 40.

Replace the echo with a resolve-time report naming the set, the file, the repo
count, and whether a GitHub key is needed — the last **derived** from whether
any URL is `git@`/`ssh://`, so it cannot rot the way a hand-written marker
does:

```
==> REPOS_CONFIG=DOME (manifest/repos-dome.txt, 21 repos, needs a GitHub SSH key)
```

A credential *preflight* was considered and **rejected**: `ssh -T git@github.com`
exits non-zero even on success, so it needs output-matching to work, and git's
own clone error is already legible. Reporting costs nothing and guards nothing
falsely.

*Test:* extend `test_f17_repos_config.sh` — assert the cascade order, that
`clone_section` takes a file argument, that no `manifest_should_clone` call
remains, and that the report line names the set and file.

## TF17.4 — switch the `Dockerfile` to the resolver

**Status**: not done

**Description**: Add `ARG REPOS_CONFIG=DOME` and resolve the set file instead
of hardcoding `/manifest/repos.txt` (`Dockerfile:45`). The Dockerfile already
sources `lib.sh` for `manifest_parse_repo`, so the resolver is available.

**Note a pre-existing divergence while here:** the Dockerfile's clone loop
never called `manifest_should_clone` at all, so the Docker image has silently
ignored `DOME_CLONE_OVERRIDE` since F10 shipped. This step is what finally
makes the two clone paths agree. Log the divergence as a chore so the history
is not lost.

*Test:* static `grep` in `test_f17_repos_config.sh` — the Dockerfile declares
the arg and references no literal `repos.txt`. A real image build is out of
scope for the suite, consistent with every other Dockerfile check.

## TF17.5 — strip the `PRIVATE_REPO` markers

**Status**: not done

**Description**: Remove the trailing `PRIVATE_REPO` token from all 17 lines in
`manifest/repos-dome.txt`. Nothing reads it by this point: TF17.3 and TF17.4
removed the only consumers.

**Must precede TF17.6** — see *Ordering hazard*.

*Test:* extend `test_f17_repos_config.sh` — no `PRIVATE_REPO` anywhere under
`manifest/`, and `repos-dome.txt` still yields the same repo count and dests
as before the strip.

## TF17.6 — simplify the parser, delete the dead functions

**Status**: not done

**Description**: Reduce `manifest_parse_repo` to
`read -r REPO_URL REPO_DEST REPO_BRANCH` and drop `REPO_IS_PRIVATE`. Delete
`manifest_should_clone` and `manifest_validate_clone_override` from
`manifest/lib.sh`.

**Only after TF17.5.** Running this first turns `PRIVATE_REPO` into a branch
name on 17 repos.

*Test:* extend `test_f17_repos_config.sh` — parse a two-field and a
three-field line and assert `REPO_BRANCH` is empty then set; assert both
deleted functions are absent from `lib.sh`.

## TF17.7 — `config.txt` default and the cloud-init template

**Status**: not done

**Description**: Replace the `DOME_CLONE_OVERRIDE` block in
`manifest/config.txt` with `REPOS_CONFIG=DOME`, documenting the `NONE`
reserved value and the `repos-<name>.txt` mapping inline.

In `host-file-templates/cloud/user-data.template:44`, replace
`DOME_CLONE_OVERRIDE=PUBLIC_ONLY` with `REPOS_CONFIG=SAFE`, preserving the
property that a cloud host needs no GitHub key — now by construction, since
`SAFE` holds only HTTPS URLs.

*Test:* extend `test_f17_repos_config.sh` — `manifest_config` reads the
default; the template writes `REPOS_CONFIG=SAFE` and no longer mentions
`DOME_CLONE_OVERRIDE`.

## TF17.8 — documentation

**Status**: not done

**Description**: Update `02-doc/cloud-howto.md` (Step 4 and the "private cloud
dev box" section), `pi-howto.md`, `vm-howto.md`, `docker-howto.md`,
`README.md:90`, and `manifest-format.md`. The cloud guide's optional-private
path changes shape: instead of *removing* `DOME_CLONE_OVERRIDE`, the reader
switches `REPOS_CONFIG` to `DOME`.

*Test:* extend `test_f17_repos_config.sh` — no doc mentions
`DOME_CLONE_OVERRIDE` or `PRIVATE_REPO` as live mechanisms, and
`cloud-howto.md` documents `REPOS_CONFIG=SAFE`. Historical mentions in
`chores.md`, `current.md`, `history.md` and the F10 files are left alone as
record.

## TF17.9 — the F17 test suite

**Status**: not done

**Description**: Finalize `tests/test_f17_repos_config.sh` as the feature's
dedicated suite and delete `tests/test_f10_repo_cloning.sh`, whose 47 checks
are written entirely against the removed mechanism.

Two checks beyond the per-step assertions above:

- **Drift guard.** Parse every `manifest/repos-*.txt` and assert that any
  `dest` appearing in more than one set has an identical URL, dest and branch
  in all of them. This is the mitigation for the design's one real cost —
  duplicated entries across files — and `chores.md` already records two
  silent breakages from hand-editing `repos.txt`.
- **Fix `test_f01_manifest.sh:140`.** It asserts every section extracts **> 0**
  entries, which `repos-safe.txt`'s intentionally empty `[root-pi]` and
  `[uros_ws]` would fail. Assert instead that sections parse and that at least
  one section is non-empty per file.

*Test:* this task is the test.

## TF17.10 — migrate the live box, log the chore

**Status**: not done

**Description**: `dome-cloud-1`'s `manifest/user.txt` still carries
`DOME_CLONE_OVERRIDE=PUBLIC_ONLY`, which becomes meaningless — leaving it to
fall back to the `DOME` default and start demanding a GitHub key it does not
have. Replace it with `REPOS_CONFIG=SAFE`.

Also log the TF17.4 chore: the Dockerfile's clone path never honored
`DOME_CLONE_OVERRIDE`, so Scenario 3 images were always full-set regardless of
the flag.

*Test:* none — an operational change on a live host plus a chore entry. Verify
by hand with a `bare-metal-build.sh` rerun on the box once it is next started.
