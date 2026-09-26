# TF13 Description for Feature F13

**Date Created:** 2026-09-25

Box-side dev-host `Makefile`, split from the laptop OCI control Makefile.
Each step names its test, or why one is not feasible. Tests follow the static
`grep`/parse style already used in `tests/` for shell and config artifacts
(real `make` runs need a live box or the `oci` CLI, consistent with the other
bare-metal script checks in the suite).

## TF13.0 — resolve the relocation decision

**Status**: done

**Description**: Confirm with the user the key decision from the feature spec:
root `Makefile` becomes the box-side tool and the laptop control targets move
to `terraform/oci/Makefile` (recommended), **or** keep one root Makefile that
dispatches by `DOME_TARGET`. All later steps assume the recommended split;
revise them if the user picks dispatch.

*Test:* none — a decision, not code.

## TF13.1 — move laptop control targets to `terraform/oci/Makefile`

**Status**: done

**Description**: Create `terraform/oci/Makefile` containing the current
`start`/`stop`/`status`/`ip`/`ssh`/`vnc-up`/`vnc-down` targets, with `TF_DIR`
re-anchored to `.` (the Makefile now lives inside `terraform/oci`). Verify the
targets behave identically when run as `make -C terraform/oci <target>`.

*Test:* `tests/test_f13_makefiles.sh` — assert `terraform/oci/Makefile` exists,
declares each control target in `.PHONY`, and no longer uses a `terraform/oci`
sub-path in `TF_DIR`.

## TF13.2 — replace the root `Makefile` with box-side targets

**Status**: done

**Description**: Rewrite the root `Makefile` to expose `help` (default),
`build`, `desktop`, `env`, `status` as thin wrappers over
`scripts/bare-metal-build.sh`, `scripts/start-desktop.sh`, and the config
cascade. Remove the OCI control targets (now in `terraform/oci/Makefile`).
Match `make build`'s privilege (sudo or not) to how the guide invokes
`bare-metal-build.sh` — decided in TF13.0's follow-up open question.

*Test:* extend `tests/test_f13_makefiles.sh` — assert the root `Makefile`
declares `build`/`desktop`/`env`/`status`, references the expected scripts, and
contains **no** `oci ` invocation and none of the control target names.

## TF13.3 — `make env` / `make status` resolve state correctly

**Status**: done

**Description**: `make env` prints `DOME_USER`/`DOME_TARGET`/`ROS_DISTRO` using
the same env > `user.txt` > `config.txt` precedence the scripts use, and
reports whether `~/ros2_ws/install/setup.bash` is sourced/present. `make
status` prints the built-package count and overlay presence. Neither errors on
a box where the workspace has not been built yet (report "not built", exit 0).

*Test:* extend `tests/test_f13_makefiles.sh` — static asserts that `env`/`status`
read the config cascade keys and guard the not-yet-built case; a live run needs
a provisioned box (noted, consistent with the suite).

## TF13.4 — update docs and firstboot references

**Status**: done

**Description**: Update every reference to the moved control targets to the
`make -C terraform/oci <target>` form: `02-doc/cloud-howto.md`,
`02-doc/oci-howto.md`, `02-doc/current.md` re-entry note, and the `help` text.
Confirm `host-file-templates/cloud/user-data.template` needs no change (it does
not invoke `make`); note the box now has useful `make` targets in
`cloud-howto.md`'s post-login section.

*Test:* extend `tests/test_f13_makefiles.sh` — assert the howtos no longer show
a repo-root `make start`/`make ssh` and do show the `-C terraform/oci` form.

## TF13.5 — write the test suite and run it green

**Status**: done

**Description**: Finalize `tests/test_f13_makefiles.sh` covering TF13.1–TF13.4,
wire it into the suite runner alongside the other `test_f*` scripts, and run
the full suite to confirm no regression (the root-Makefile move must not break
any existing check that greps for `make` targets).

*Test:* the suite itself; record the pass counts in `chores.md`/`current.md`
on close, per the F10 precedent.
