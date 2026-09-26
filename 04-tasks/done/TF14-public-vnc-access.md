# TF14 Description for Feature F14

**Date Created:** 2026-09-25

Per-VM VNC access mode: a single controllable TigerVNC desktop reached either
publicly (URL + VNC password) or by SSH key over a tunnel. Removes the
`x11vnc` dual-mirror design. Each step names its test, or why one is not
feasible; VNC serving and firewall behavior need a live box, so those steps use
the static `grep`/parse style the suite already uses for shell/Terraform.

## TF14.0 — resolve the open questions

**Status**: done

**Decisions (2026-09-25):** mode selector is `DOME_VNC_ACCESS=public|tunnel|none` in `user.txt`; a Terraform `vnc_access` var drives the firewall; the single source of truth (Terraform writing `user.txt` via cloud-init) is **deferred to F11** — F14 sets the two in step at provision. One public port, **48210** (drop 48211). VNC password is a manual one-time `vncpasswd`. `make vnc-up`/`vnc-down` are **kept** as manual overrides (simplified to the single server).

**Description**: Settle the spec's open questions with the user: where the mode
flag lives and the box/Terraform split; the single canonical port; whether
`vnc_test` is replaced by the `public`-mode signal; password provisioning; and
whether `make vnc-up`/`vnc-down` survive. Every step below assumes a
`DOME_VNC_ACCESS=public|tunnel|none` flag plus a matching Terraform signal;
revise if the user picks otherwise.

*Test:* none — a decision.

## TF14.1 — add the `DOME_VNC_ACCESS` config flag

**Status**: done

**Description**: Add `DOME_VNC_ACCESS` to `manifest/config.txt` (default
`none`) with the same env > `user.txt` > `config.txt` resolution the other
keys use, documented inline. `public` and `tunnel` are the active values.

*Test:* extend `tests/test_f14_vnc_access.sh` — assert the config default and
that `manifest_config`/the resolver reads it.

## TF14.2 — single-server public VNC service (drop x11vnc)

**Status**: done

**Description**: Replace the `x11vnc` dual-mirror bring-up with a single
TigerVNC `:1` + one `websockify` on `0.0.0.0:<port>` for `public` mode. Provide
it as a systemd unit that starts on boot when `DOME_VNC_ACCESS=public`.
`tunnel` mode continues to use `scripts/start-desktop.sh` (loopback). Remove
all `x11vnc` references.

*Test:* extend the suite — assert no repo reference to `x11vnc`; the unit binds
`0.0.0.0:<port>` only in `public` mode and loopback otherwise; static checks
(real serving needs a live box, noted).

## TF14.3 — Terraform opens exactly one port in public mode

**Status**: done

**Description**: Make the security list open the single public port when the box
is in `public` mode, in steady state (not behind a temporary flag). Drop the
second port. Reconcile or remove `var.vnc_test` per TF14.0. In `tunnel`/`none`
mode no VNC port is open.

*Test:* extend the suite — `terraform validate`/`plan`-style static asserts (or
grep of `network.tf`) that one port opens in `public` and none otherwise.

## TF14.4 — password provisioning and the mode plumbing

**Status**: done

**Description**: Ensure `public` mode has a `~/.vnc/passwd` (documented
`vncpasswd` step, or a first-boot/`bare-metal-base.sh` path per TF14.0) and that
`tunnel` mode adds the tester's SSH public key. Wire `DOME_VNC_ACCESS` through
first-boot / the desktop setup so the right service and firewall result.

*Test:* extend the suite — assert the mode drives the service/firewall choice
and that `public` mode requires a password (no `SecurityTypes None`).

## TF14.5 — docs: cloud-howto access-mode section

**Status**: done

**Description**: Rewrite `02-doc/cloud-howto.md` Step 7 into the two modes:
`public` (set `DOME_VNC_ACCESS=public`, set a VNC password, share the URL) and
`tunnel` (add the tester's key, `ssh -L`). Remove the two-mirror / `x11vnc` /
`vnc-up`-two-port description. Update the root `Makefile`/`terraform/oci`
`Makefile` help and the `vnc-up`/`vnc-down` fate per TF14.0.

*Test:* extend the suite — cloud-howto documents both modes and no longer
mentions `x11vnc` or two public ports.

## TF14.6 — desktop is self-sufficient (terminal + agreed app list)

**Status**: done

**Description**: Make a `vnc` desktop usable on arrival. Add a terminal
emulator (`xfce4-terminal` — the `xfce4` metapackage does NOT pull one;
confirmed live 2026-09-25) and the agreed application set to
`manifest/packages.txt` `[apt-desktop]`. Final list is recorded in the F14
feature file once confirmed with the user. Verify `tigervnc-tools` (added at
`a218d0f`) is in `[apt-desktop]` so the password tool exists.

*Test:* extend the suite — assert `[apt-desktop]` contains `xfce4-terminal`,
`tigervnc-tools`, and each agreed app.

## TF14.7 — write the test suite and run it green

**Status**: done

**Description**: Finalize `tests/test_f14_vnc_access.sh` covering TF14.1–TF14.6,
and run the full suite to confirm no regression (especially any check that
grepped the old two-port `vnc-up`).

*Test:* the suite itself; record pass counts in `chores.md`/`current.md` on
close, per the F10/F13 precedent.
