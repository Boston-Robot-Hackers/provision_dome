# TF07 Description for Feature F07
**Date Created:** 2026-09-22

## TF07.0 — Manual cloud bring-up with today's repo, recording every friction point
**Status**: done
**Description**: Before writing code, confirm the breakages F07 predicts.
Create an Ubuntu 24.04 instance on the provider and architecture you
actually intend to use (see `02-doc/notes.md`, *Dev host options*).

- **On OCI:** follow `02-doc/oci-howto.md`.
- **Elsewhere:** follow `02-doc/vm-howto.md` as written with
  `DOME_TARGET=vm`.

`oci-howto.md` already works around the login-user and swap problems, so
on OCI record whether those workarounds were enough, rather than whether
the problems occur.

Record in `02-doc/notes.md`, for each of the four predicted problems
(login user, repo location, unreachable new user, no swap), whether it
occurred and what workaround was needed. Also record anything unpredicted,
especially any package or build failure specific to the architecture.

If the run surfaces a problem F07 doesn't cover, stop and amend the spec
before TF07.1.

No automated test: a manual provisioning run. Record command, setup,
expected observation, and actual result per the style guide.

## TF07.1 — Add DOME_TARGET=cloud and fix the hardcoded target message
**Status**: done
**Description**: Add `cloud` to the `DOME_TARGET=pi|vm` comment in
`manifest/config.txt`. Change `host-setup.sh:151` to print the resolved
`${DOME_TARGET}` instead of the literal `DOME_TARGET=vm`.

No gate logic changes here — every existing gate tests `== "pi"`.

Test: in the style of `tests/test_f03_vm_target.sh`, assert the
`config.txt` comment lists `cloud`, and that `host-setup.sh` no longer
contains the literal `DOME_TARGET=vm —` message.

## TF07.2 — Enable swap for DOME_TARGET=cloud
**Status**: done
**Description**: Change the swap gate at `bare-metal-base.sh:35` from `pi`
only to `pi` or `cloud`. `vm` stays excluded — a local VM's memory is the
user's to size. Update the `SWAP_SIZE_MB` comment in `manifest/config.txt`,
which currently says Pi-only.

Test: extend the stubbed behavior tests in `tests/test_f04_pi_swap.sh` so
the gated block creates swap for `pi` and `cloud` and skips it for `vm` and
for an unrecognized value.

Caveat: `test_f04_pi_swap.sh`'s `run_swap_step` *copies* the gate inline
rather than extracting it from the script, so it would still pass if the
script were never changed. Add a check against the real script — grep
`bare-metal-base.sh`'s swap gate for `cloud` — so the test fails if the
script and the copy drift.

## TF07.3 — Add the cloud-init first-boot template
**Status**: done
**Description**: Write `host-file-templates/cloud/user-data.template`,
following `host-file-templates/boot/firmware/user-data.template`'s
`REPLACE_WITH_...` placeholder convention. On first boot it must:

- create `REPLACE_WITH_HOST_USER` with `REPLACE_WITH_SSH_PUBLIC_KEY` in
  `ssh_authorized_keys`, membership in `sudo`, and passwordless sudo;
- install `git` and `ca-certificates`;
- clone `provision_dome` over HTTPS into
  `/home/REPLACE_WITH_HOST_USER/provision_dome`, owned by that user;
- write `manifest/user.txt` with `DOME_USER` and `DOME_TARGET=cloud`;
- run `scripts/host-setup.sh` then `scripts/bare-metal-base.sh`, from the
  repo root, as root.

It must **not** run `bare-metal-build.sh` or contain any credential.

Test: assert the template exists, starts with `#cloud-config`, contains
both placeholders, sets `DOME_TARGET=cloud`, references `host-setup.sh` and
`bare-metal-base.sh`, and does **not** reference `bare-metal-build.sh`.
If `python3 -c 'import yaml'` succeeds, also assert it parses as YAML;
otherwise skip that one check with a message. Full first-boot behavior is a
manual test in TF07.0's style.

## TF07.4 — Add DOME_DESKTOP to the manifest and gate it in bare-metal-base.sh
**Status**: done
**Description**: Add `DOME_DESKTOP=none|vnc` to `manifest/config.txt`
(default `none`) and an `[apt-desktop]` section to `manifest/packages.txt`
(`xfce4`, `tigervnc-standalone-server`, `novnc`, `websockify`, `dbus-x11`).

In `bare-metal-base.sh`, resolve `DOME_DESKTOP` with the same env >
`user.txt` > `config.txt` precedence as `DOME_TARGET`, and append
`[apt-desktop]` to the apt list only when the value is exactly `vnc`. Print
a skip line otherwise, matching the existing swap-skip style.

Test: fixture-based, in the style of `tests/test_f05_dome_mode.sh` —
desktop packages selected for `vnc`, skipped for `none` and for an
unrecognized value; `[apt-desktop]` parses to a non-empty list via the same
`awk` reader.

## TF07.5 — Add scripts/start-desktop.sh, loopback-only
**Status**: done
**Description**: Start TigerVNC on display `:1` with `-localhost yes`, and
websockify/noVNC on `127.0.0.1:6080` forwarding to `localhost:5901`. Fail
with a clear error if the desktop packages are not installed, pointing at
`DOME_DESKTOP=vnc`.

**Neither listener may bind a non-loopback address.** Raw VNC on 5901 is
the easy one to miss.

Test: static checks that the script passes `-localhost yes` to the VNC
server, binds websockify to `127.0.0.1`, and never contains `0.0.0.0`; and
that it exits non-zero with a message mentioning `DOME_DESKTOP` when
`vncserver` is not on `PATH`.

## TF07.6 — Write 02-doc/cloud-howto.md
**Status**: done
**Description**: A self-contained guide matching the structure of
`vm-howto.md`:

- choosing a provider, pointing at `02-doc/notes.md` rather than
  duplicating pricing;
- filling in and pasting the cloud-init template;
- `cloud-init status --wait` and where to look on failure;
- **generating a host-specific GitHub key on the cloud host**, adding it
  to GitHub, and revoking it at teardown — with an explicit "do not copy
  your personal key here";
- running `bare-metal-build.sh` and the smoke test;
- Foxglove over `ssh -L 8765:localhost:8765`;
- the optional desktop over `ssh -L 6080:localhost:6080`;
- teardown: destroy the instance, revoke the key.

State the software-GL limitation and the self-contained-graph limitation
plainly, with a pointer to F08.

Test: doc-presence checks in the style of `tests/test_f03_vm_target.sh:82`
— the file exists and mentions `DOME_TARGET=cloud`, `cloud-init status`,
and `ssh -L`.

## TF07.7 — Update the scenario table and README
**Status**: done
**Description**: Add the cloud host to `02-doc/howto.md`'s scenario table
and `README.md`'s scenario list. F06 also adds a scenario; if F06 has not
landed, add cloud without renumbering F06's slot and note the ordering
dependency rather than guessing its wording.

Test: both files name the cloud scenario and link `cloud-howto.md`.

## TF07.8 — Write the F07 test suite
**Status**: done
**Description**: Consolidate TF07.1–TF07.7's checks into
`tests/test_f07_cloud_target.sh`, following `tests/test_f05_dome_mode.sh`'s
`pass`/`fail` helpers and section headings. Must run on the Mac with no
cloud instance. Anything requiring a real instance stays manual and out of
the plain run.

Confirm the whole suite — all `tests/test_f0*.sh` — passes before F07 is
closed.

## TF07.9 — Terraform OCI provisioning (replaces the manual console bring-up)
**Status**: done
**Description**: The manual OCI console bring-up in `oci-howto.md` proved
**error-prone and circular** — see `02-doc/notes.md`, *Headline finding — the
OCI console is the real obstacle*. This task replaces it with a declarative,
reproducible, tearable Terraform config so TF07.0 can validate the breakages
on a box created **without** the console.

Add a `terraform/oci/` config that stands up, in the tenancy root compartment
via the working `~/.oci/config`:

- a **VCN + public subnet + internet gateway + route table**;
- a **security list** allowing only inbound SSH (port 22), matching the
  SSH-tunnel-only access model — everything else stays loopback;
- a **VM.Standard.A1.Flex** instance (arm64), **Ubuntu 24.04 aarch64**, with a
  **100 GB boot volume**, an assigned **public IPv4**, and the operator's SSH
  public key from `~/.ssh/id_ed25519.pub`;
- outputs for the **public IP** and the **instance OCID** (for stop/start).

**Scope decision — Terraform stands up a *bare* box, not the F07 cloud-init
flow.** TF07.0's job is to validate the four baseline breakages by running the
scripts by hand as `ubuntu` (`DOME_TARGET=vm`, hand-added swap), exactly as
`oci-howto.md` describes. So this config carries **no user-data** and does not
pre-create `DOME_USER` or add swap; it only removes the console from the
create step. Wiring the F07 `user-data.template` into Terraform is a later
task once the baseline is validated.

**Provider-neutrality unchanged.** This is OCI-specific glue for bring-up
only; the provisioning code (`DOME_TARGET=cloud`, swap, cloud-init) stays
provider-neutral per the F07 spec.

Test: `terraform validate` and `terraform fmt -check` on `terraform/oci/`
(no cloud calls, safe on the Mac). Live `apply` is a manual step recorded in
TF07.0's log, not an automated test — it creates real cloud resources.
