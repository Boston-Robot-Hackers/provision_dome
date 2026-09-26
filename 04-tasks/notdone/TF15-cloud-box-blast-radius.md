# TF15 Description for Feature F15

**Date Created:** 2026-09-26

Harden the box so that losing it costs only itself. Task order follows F15's
*Suggested order* — live-today findings first, worst-case findings later — not
the finding numbers.

Real hardening behavior (sshd rejecting an agent, the OCI edge refusing a
connection, a pinned installer resolving to a fixed commit) needs a live box,
so the suite uses the static `grep`/parse style already used for the
bare-metal scripts and Terraform, and each such step names the manual check
that actually proves it.

## Review notes — where F15's recommendations meet the tree

Re-read against the code on 2026-09-26. Six of F15's recommendations need a
different shape than the spec assumes; each is folded into the step that owns
it, and the spec edits they imply are listed in *Proposed F15 amendments* at
the end of this file.

- **Nothing in this repo manages sshd.** The box's `allowagentforwarding yes`
  and `x11forwarding yes` are Ubuntu image defaults, not our config. F15.1 and
  F15.7 both assume an sshd config we can edit; there isn't one, so a
  mechanism has to be created (TF15.12).

- **Terraform passes no `user_data`.** `compute.tf:13-16` says so outright, and
  `metadata` carries only `ssh_authorized_keys`. The cloud-init template is the
  hand-pasted console path, so **`bare-metal-base.sh` is the only mechanism
  that reaches the live box today.** Every on-box change here goes there, and
  F11 will pick it up for free when it teaches Terraform to render the template.

- **A branch field cannot hold a commit SHA.** F15.3 says the repo format
  "already supports a branch field", but `clone_section` passes it to
  `git clone --branch`, which accepts branches and tags only — a 40-hex SHA
  fails outright. Commit pinning needs clone-then-checkout (TF15.3), mirrored
  in the `Dockerfile`'s own clone loop, which is the lesson TF10 learned the
  hard way.

- **F17 owns `repos.txt` and will move it.** F17 renames it to
  `repos-dome.txt` and adds `repos-safe.txt`, and **`rosutils` is in both
  sets**, so the pin lands twice and TF17.9's drift guard then enforces that
  the two copies agree. See *Ordering against F17*.

- **Rotating the box key does not re-key the live box.** `ssh_authorized_keys`
  is instance metadata that cloud-init reads at first boot; changing the
  Terraform variable affects only boxes created afterward. The live box needs a
  hand edit (TF15.11).

- **`fail2ban` has no stock filter for websockify or VNC.** F15.7 grades it
  "real value for 48210", but delivering that value means writing a custom
  filter against websockify output. TF15.8's CIDR narrowing removes the
  internet from that port entirely and supersedes it (TF15.12).

## Ordering against F17

F17 replaces `DOME_CLONE_OVERRIDE` with `REPOS_CONFIG` and renames
`manifest/repos.txt`. TF15.3 and TF15.4 touch the same parser and file.

**Either order works; the collision must just be paid once.** If F15 lands
first, F17's TF17.5/TF17.6 must preserve the commit-pin field while stripping
`PRIVATE_REPO` — the fields are independent, but the parser simplification in
TF17.6 assumes a two-or-three-field line and would need to keep the third
field's SHA-vs-branch distinction. If F17 lands first, TF15.4 applies the
`rosutils` pin to **both** `repos-dome.txt` and `repos-safe.txt`.

**Recommendation: land F15 first.** TF15.3/TF15.4 are two files and a
five-line parser change, against F17's eleven steps and two file renames —
the smaller change should be the one that gets rebased.

## TF15.0 — record the decisions

**Status**: done

**Description**: Settle the four decisions the later steps would otherwise
re-litigate, and record them here.

- **Where on-box hardening lives:** `scripts/bare-metal-base.sh`, gated to
  `DOME_TARGET=cloud`, installing a template from `host-file-templates/`. It
  is the only path that reaches the live box with a rerun, it already installs
  units this way for F14, and it keeps the Pi and the VM out of scope — which
  matches F15's stated scope of *the box*.

- **Agent forwarding on the Pi is not in scope.** `AllowAgentForwarding no`
  applies to `cloud` only. The robot may rely on a forwarded agent to pull
  private repos, and F15 does not claim otherwise; widening this is a robot
  change and would need its own feature.

- **How the VNC ingress CIDR defaults.** `var.vnc_allowed_cidr` defaults to
  `"0.0.0.0/0"`, preserving today's behavior for anyone running a bare
  `terraform apply`, and **`make vnc-up` computes the caller's own address and
  passes `-var vnc_allowed_cidr=<ip>/32`**. The secure value therefore comes
  from the workflow rather than from a default that a plain apply would
  silently widen back. `make vnc-up CIDR=0.0.0.0/0` stays as the escape hatch.

- **What a pin means.** Third-party code is pinned to an **immutable commit
  SHA**, not a tag — a tag can be moved by its author, which would defeat the
  `sha256` check added in TF15.1.

*Test:* none — decisions.

## TF15.1 — pin `mcfly`, add `sha256` verification to `tools.txt`

**Status**: done

**Description**: Closes the live half of **F15.2**, which reaches the robot.

`manifest/tools.txt:9` fetches `mcfly`'s installer from the `master` branch and
`bare-metal-base.sh:169` pipes it into `sh` **as root**. Repoint the URL at a
`raw.githubusercontent.com/cantino/mcfly/<sha>/ci/install.sh` path, resolving
`<sha>` at implementation time from the newest release tag — do not guess a
version number here, look it up.

Add an optional `sha256` field to `tools.txt` and have the installer loop fetch
to a temp file, verify, then execute, instead of streaming to a shell. A pinned
commit URL is immutable, so the digest is stable; that is exactly why TF15.0
chose a SHA over a tag. Verification failure must **exit non-zero with the
expected and actual digests** — never fall back to running the script.

The `run_as_user` branch already runs the installer through
`sudo -u`; keep that, verifying before the privilege drop.

*Test:* extend the F15 suite — `tools.txt` has no `/master/` or `/main/` URL,
`[mcfly]` carries a `sha256`, `bare-metal-base.sh` verifies before executing
and no longer pipes `curl` directly into a shell for an entry that has a
digest, and `bash -n` passes. Digest-mismatch behavior is checked by calling
the extracted verify step with a deliberately wrong digest and asserting a
non-zero exit.

## TF15.2 — decide `claude-code`'s pin, or record why it has none

**Status**: done

**Result (2026-09-26):** the installer was read, and it is in better shape than
F15.2 assumed. It **does** take a version argument — `[stable|latest|VERSION]`,
validated against a regex at the top — and it **verifies what it downloads**,
checking the binary's SHA256 against the vendor manifest and refusing to
install on a mismatch.

So `args = stable` now selects the stable channel rather than the bleeding one,
and a literal version can replace it if an exact pin is ever wanted. No
`sha256` on the bootstrap itself: it is a vendor endpoint serving changing
content, and a digest there would break every run the moment it is edited. The
residual risk is that bootstrap script, and it is recorded in `tools.txt`.

Worth noting against F15.2's framing: the two installers were graded together,
but only `mcfly` was both unpinned *and* unverified, and only `mcfly` ran as
root.

**Description**: The other half of **F15.2**. `[claude-code]` runs
`claude.ai/install.sh` unpinned as `DOME_USER`.

Check whether that installer accepts a version argument. If it does, pin it via
`args` and note that the *installer itself* remains unpinned even so. If it
does not, **record that plainly** — a vendor endpoint that serves changing
content cannot be checksummed, and adding a `sha256` to it would break every
run the moment the vendor edits the file.

Lower the risk instead of pretending it is pinned: it runs as the user, not
root, which is already true and worth stating.

Do not invent a pin that the installer does not support. If there is no pin,
this step's deliverable is the written finding and a one-line comment in
`tools.txt`.

*Test:* assert whichever outcome lands — a version in `[claude-code]`'s `args`,
or a comment in `tools.txt` naming the residual risk. A test that asserted a
pin the vendor does not offer would be a test of a wish.

## TF15.3 — teach the repo format a commit pin

**Status**: done

**Description**: Prerequisite for **F15.3**. `git clone --branch` rejects a
commit SHA, so `clone_section` (`bare-metal-build.sh:76-82`) cannot pin
`rosutils` to a commit as the spec assumes.

Extend `manifest_parse_repo` so the third field is recognized as a **commit
when it is 40 hex characters**, otherwise a branch, and have `clone_section`
clone then `git -C <dest> checkout --detach <sha>`. A failed checkout must
`exit 1` like a failed clone — a repo left on `main` when a pin was requested
is the exact silent-wrong-version case the pin exists to prevent.

**Mirror the change in the `Dockerfile`'s own clone loop** (`Dockerfile:40-44`).
It duplicates `clone_section` rather than sharing it, which is how
`DOME_CLONE_OVERRIDE` came to be silently ignored in the image (see TF17.4);
the same divergence here would leave Scenario 3 unpinned.

*Test:* extend the F15 suite — parse a branch line, a 40-hex line and a
two-field line, asserting which of branch/commit is set each time; assert
`clone_section` and the `Dockerfile` both contain a detached checkout; `bash -n`
both. Real cloning needs network, consistent with the rest of the suite.

## TF15.4 — pin `rosutils` to a commit

**Status**: done

**Description**: Closes **F15.3**'s live half. `manifest/repos.txt:2` clones
`campusrover/rosutils` unpinned, and `manifest/bashrc:3` sources
`ros2_robot_bashrc.bash` from it into **every interactive shell on every
target**, including the robot's.

Add the current `main` commit SHA as the third field. Record in the manifest
comment that the pin is deliberate and that moving it is a review step, not a
routine bump — an unreviewed bump reintroduces the finding.

If F17 has already landed, apply the identical pin to both
`manifest/repos-dome.txt` and `manifest/repos-safe.txt`; TF17.9's drift guard
will then hold them together.

*Test:* extend the F15 suite — every `rosutils` entry under `manifest/` carries
a 40-hex third field, and all such entries agree. Whether the pinned commit is
the one intended is a human judgment, not an assertion.

## TF15.5 — remove Doppler from the project

**Status**: done

**Description**: The latent half of **F15.3**, and the scope changed mid-task on
the user's instruction: **remove Doppler entirely** rather than write a rule
against logging into it.

`ros2_robot_bashrc.bash` calls `doppler configure get token` in every
interactive shell. It was inert only because no token was configured, and one
`doppler login` would have put a whole secret store one box compromise away.

What landed:

- Deleted the `[doppler]` section from `manifest/apt-repos.txt`, so the CLI is
  no longer installed on **any** target — Pi, VM, cloud or Docker image.
- Dropped the Doppler token check from `scripts/box-audit.sh` and the
  `no doppler login` clause from `cloud-howto.md`, since neither has anything
  left to guard.
- Updated the third-party-repo lists in `spec.md`, `notes.md`, `pi-howto.md` and
  `vm-howto.md` to name only GitHub CLI and VS Code.
- Removed the `[doppler]` assertions from `tests/test_f01_manifest.sh`.

**This is a stronger fix than the original plan.** A written rule relies on
remembering it; with the CLI absent, the hook in `rosutils` cannot resolve a
token at all. The hook itself is left alone, exactly as this task originally
argued — it lives in a third-party repo that TF15.4 has now pinned, and
patching a pinned checkout to delete a call that is already inert would be
worse than leaving it.

Historical mentions in `chores.md`, `history.md` and the F01 feature files are
left as record.

*Test:* `test_f01_manifest.sh` no longer expects a `[doppler]` section and
passes; `test_f15_blast_radius.sh` asserts the audit's remaining checks. A
"Doppler is absent" assertion was considered and skipped — asserting the absence
of every removed component is unbounded.

## TF15.6 — `make stop` disarms the box

**Status**: done

**Description**: Closes **F15.9**, and bounds the exposure window for every
other finding in F15. The invariant is the user's: ***stopped means
disarmed.***

`terraform/oci/Makefile:33-34`'s `stop` issues a `SOFTSTOP` and nothing else,
leaving `48210` open at the OCI edge and both VNC units `enabled`, so a later
`make start` silently restores a publicly reachable desktop.

Make `stop` run the `vnc_access=none` security-list apply before the
`SOFTSTOP`. `vnc-down` already does exactly that apply, so `stop` should depend
on it rather than repeat the command — `vnc-down`'s leading `-` on the ssh line
already tolerates an unreachable or unprovisioned box, which is the case that
matters when stopping. Update `help` so the output states that stopping closes
the port.

The security list is the authoritative boundary, so this one change
establishes the invariant on its own.

*Test:* extend the F15 suite — `stop` reaches the `vnc_access=none` apply
(directly or via a prerequisite), the `help` text says stopping disarms, and
`make -n stop` in a dry run shows both the apply and the `SOFTSTOP`. The real
proof is manual and belongs to TF15.16.

## TF15.7 — arming is always explicit

**Status**: done

**Description**: **F15.9**'s defense-in-depth half. `bare-metal-base.sh:126-128`
runs `systemctl enable` on `dome-vnc.service` and `dome-vnc-firewall.service`,
so the desktop returns on every boot — a standing intent to serve that nothing
in the workflow revokes.

Install the units but do **not** enable them; let `make vnc-up`'s
`systemctl start`/`restart` be the only thing that serves a desktop. With the
port closed at the edge a running `dome-vnc` is unreachable anyway, so this
changes no reachability — it removes a second thing that has to be remembered.

**Check the `tfvars` steady state while here.** `terraform.tfvars` does not set
`vnc_access`, so it defaults to `none` and the drift F15.9 warns about is not
present today. It appears the moment someone writes `vnc_access = "public"`
into that file, at which point a full `terraform apply` reopens the port behind
`vnc-up`/`vnc-down`'s back. Document in `terraform.tfvars.example` that the
steady state stays `none` and that `public` belongs on the `vnc-up` command
line.

*Test:* extend the F15 suite — `bare-metal-base.sh` installs the units without
enabling them, `vnc-up` starts them, and `terraform.tfvars.example` documents
the `none` steady state. Note the small behavior change for the person on the
box: after a reboot the desktop needs `vnc-up`, which is the point.

## TF15.8 — narrow the VNC ingress CIDR

**Status**: done

**Description**: **F15.5**'s CIDR half, and the cheapest large win in F15 —
it removes the entire internet from the one open port.

`network.tf:53` hardcodes `source = "0.0.0.0/0"` for 48210. Add
`var.vnc_allowed_cidr`, defaulting to `"0.0.0.0/0"` per TF15.0, with a
validation that it parses as CIDR, and reference it from the dynamic block.
Leave the SSH rule at line 38 alone — SSH is key-only, and locking it to one
address locks you out from anywhere else.

Have `make vnc-up` resolve the caller's public address and pass
`-var vnc_allowed_cidr=<addr>/32`, with `CIDR ?=` overridable so
`make vnc-up CIDR=0.0.0.0/0` still works and `make vnc-up CIDR=1.2.3.0/24`
covers a changing home address. **The lookup must fail loudly**: if the address
cannot be resolved, stop rather than fall back to `0.0.0.0/0` — a silent
widening here is precisely the bug this task fixes.

Note the trade-off in the docs: a dynamic residential address means a
`vnc-up` rerun after it changes.

*Test:* extend the F15 suite — `network.tf` references the variable rather than
a literal `0.0.0.0/0` in the VNC block, the SSH rule is unchanged,
`variables.tf` validates the value, `vnc-up` passes the var and has no
`0.0.0.0/0` fallback path. `terraform validate` runs if the binary is present,
skipped with a message otherwise, matching how the suite treats optional tools.

## TF15.9 — `make audit`

**Status**: done

**Description**: Enforces **F15.4**. Provisioning installs `claude-code` and
`gh` on a box that, in `public` mode, is internet-facing. Both are clean
today; the first interactive login writes a live token to disk and the "box is
expendable" premise stops being true without anything announcing it.

Add `audit` to `terraform/oci/Makefile` — laptop-side, SSHes in, **exits
non-zero** if any of these exists: `~/.claude/.credentials.json`, an
`oauthAccount` or `primaryApiKey` in `~/.claude.json`, `~/.config/gh`,
`~/.git-credentials`, or any private key under `~/.ssh` or
`/home`. Print what was found and where; print a clean bill otherwise.

Exiting non-zero is the whole point — a target that only prints is a target
nobody reads.

Keep the check list in one place in the recipe so adding a credential path
later is a one-line change.

*Test:* extend the F15 suite — the target exists, is `.PHONY`, appears in
`help`, and its check list names each path above. Run the check **logic**
locally against a temp directory seeded with a fake `.credentials.json` and
assert non-zero, then against an empty one and assert zero; that requires the
checks to be a shell snippet the test can source rather than inline `ssh`
text, so factor it as `scripts/box-audit.sh` run over ssh. Live behavior is
TF15.16's.

## TF15.10 — the credential and browser rules, written down

**Status**: done

**Description**: The documentation half of **F15.4** and all of **F15.8**.

In `02-doc/cloud-howto.md`:

- **No interactive credential login on a `public`-mode box** — no `claude`
  login, no `gh auth login`, no secret-manager login.
- If a GitHub credential is genuinely needed, use a **read-only deploy key
  scoped to one repo**, never an account key. The existing "Optional: a
  private cloud dev box" section documents adding a key that can push; that
  warning predates public VNC mode and now understates the risk — rewrite it.
- Open the noVNC page in a **separate browser profile with no signed-in
  sessions**, and never type Mac or GitHub credentials into anything that page
  shows. It is untrusted JavaScript from a machine assumed hostile, served over
  plaintext HTTP on a bare-IP origin.
- **Keep XQuartz off the Mac.** It is absent today, which is what closes
  `ssh -X` to a hostile box; if it is ever installed, `X11Forwarding no`
  (TF15.12) is what covers it.

*Test:* extend the F15 suite — `cloud-howto.md` states the no-login rule, the
deploy-key guidance, and the browser-profile rule; the old push-capable-key
wording is gone. Doc-only otherwise.

## TF15.11 — a dedicated keypair per box

**Status**: partly done — repo side landed; Mac keygen and live re-key are manual

**Description**: Closes **F15.1**, which is preventive rather than live:
`~/.ssh/id_ed25519` is simultaneously the GitHub key, the robot key and the box
key, but the box holds only its public half and the Mac forwards no agent
today. F08 adds the network leg this finding currently lacks, so it is cheaper
now than later.

Three parts, and **the fix lives on the Mac**:

- Generate `~/.ssh/id_dome_cloud` and point `ssh_public_key_path` at its
  public half in `terraform.tfvars`. The variable already exists; this is one
  line.
- Add a `Host` block for the box in the Mac's `~/.ssh/config` with
  `IdentityFile ~/.ssh/id_dome_cloud`, `IdentitiesOnly yes` and an explicit
  **`ForwardAgent no`**. The config has a bare `Host *` block, so a
  `ForwardAgent yes` added there later would otherwise reach the box.
- Point the Makefile's `SSH_KEY ?=` at the new key so `make ssh`/`vnc-*` use it.

**The live box will not pick this up.** `ssh_authorized_keys` is instance
metadata read by cloud-init at first boot, so the Terraform change governs
future boxes only. Re-key `dome-cloud-1` by appending the new public key to
`~/.ssh/authorized_keys` over the existing session, verifying login with the
new key in a **second** session, then removing the old entry. Do not remove
the old key before the new one is proven — that is a lockout.

**Verified 2026-09-26: the plan DOES replace the instance.** With
`ssh_public_key_path` repointed, `terraform plan` reports
`oci_core_instance.dome must be replaced` (1 to add, 1 to destroy) — OCI treats
instance metadata as force-replacement. The line was therefore **reverted out of
`terraform.tfvars`**, which returns the plan to `No changes`.

Consequence: the per-box key reaches Terraform only at the next rebuild, which
F11 gates. Until then the live box is re-keyed by hand and the Mac-side
half (keypair, `~/.ssh/config` block, Makefile `SSH_KEY`) is what is actually in
force. `terraform.tfvars.example` carries the warning so the next person does
not apply it casually.

*Test:* extend the F15 suite — `terraform.tfvars.example` documents the
per-box key, the Makefile's `SSH_KEY` default is the box key, and
`cloud-howto.md` documents generating it plus the `ForwardAgent no` block. The
Mac's own `~/.ssh/config` is outside the repo and is verified by hand in
TF15.16.

## TF15.12 — sshd hardening and hygiene, installed on cloud targets

**Status**: done

**Description**: The on-box half of **F15.1** plus **F15.7**. Nothing in this
repo manages sshd today, so this step creates the mechanism TF15.0 chose.

Add `host-file-templates/etc/ssh/sshd_config.d/60-dome-hardening.conf`:

```
AllowAgentForwarding no
X11Forwarding no
PermitRootLogin no
```

Nothing in the workflow needs the first two — Foxglove and tunnel-mode VNC use
`ssh -L`, which is `AllowTcpForwarding` and stays on. Install it from
`bare-metal-base.sh` **only when `DOME_TARGET=cloud`**, then validate with
`sshd -t` and reload; a bad drop-in that is reloaded unvalidated is a lockout
on a box reachable only by SSH. On any other target, remove a stale copy, the
way the F14 block already handles its units.

Same step, same gate, from **F15.7**:

- `systemctl mask rpcbind.socket rpcbind` — it listens on `0.0.0.0:111`,
  nothing here uses it, and it is currently blocked only by the two firewalls.
- Record `ubuntu ALL=(ALL) NOPASSWD:ALL` as a **deliberate** decision in
  `cloud-howto.md` under the box-is-expendable premise, rather than leaving it
  an accident of cloud-init.
- Note that DDS binds to the VCN address rather than loopback
  (`10.0.1.235:44733` and friends). Unreachable while the security list admits
  only 22 and 48210; **re-check if a second instance joins the subnet.** A
  note, not a change.

**`fail2ban` is deliberately skipped.** It has no stock filter for websockify
or VNC, so the 48210 value F15.7 credits it with requires writing one, and
TF15.8 removes the internet from that port outright. For key-only SSH it adds
nothing. Record the reasoning so it is a decision rather than an omission.

*Test:* extend the F15 suite — the template exists and contains the three
directives, `bare-metal-base.sh` installs it under the `cloud` gate, runs
`sshd -t` before reloading, removes it otherwise, and masks `rpcbind`;
`cloud-howto.md` documents the `NOPASSWD` decision and the skipped `fail2ban`.
That sshd actually refuses an agent is TF15.16's manual check.

## TF15.13 — TLS on the noVNC listener

**Status**: done

**Result (2026-09-26):** landed, then corrected after live testing. `--cert`
alone was **not** sufficient — websockify accepts encrypted and unencrypted
connections on the same port unless told otherwise, and `curl
http://<ip>:48210/vnc.html` from the Mac returned **200** with the cert in
place. Added `--ssl-only`, which is what actually closes the plaintext path.
The suite now asserts it, since this is the kind of flag an edit could silently
drop and leave the feature looking done.

**Description**: **F15.5**'s TLS half. `start-desktop.sh:69` runs websockify
with no `--cert`, so noVNC is served over `ws://`: screen contents and every
keystroke cross the internet in the clear, and the VNC challenge-response can
be captured and cracked offline — against a password the protocol **silently
truncates to 8 characters**.

Generate a self-signed cert on the box if absent and pass `--cert` (plus
`--key`) in **public mode only**; tunnel mode is already inside an SSH channel
and gains nothing. Print the resulting `https://`/`wss://` URL, and say in the
docs that the browser will warn about the self-signed cert — an unexplained
warning on a page you have just told the user to distrust is worse than no
change.

Note the 8-character truncation in `cloud-howto.md` next to the `vncpasswd`
step. A user who picks a long passphrase today gets no benefit from it and has
no way to know.

*Test:* extend the F15 suite — `start-desktop.sh` passes `--cert` in public
mode and not in tunnel mode, generates the cert if missing, `bash -n` passes,
and `cloud-howto.md` documents the warning and the truncation. Real TLS
serving is TF15.16's.

## TF15.14 — child compartment (deferrable)

**Status**: deferred — needs a plan against the live tenancy, see below

**Deferred (2026-09-26), not attempted.** Creating a compartment is a real
change to the OCI tenancy, and the plan that would tell us whether the instance
gets replaced cannot be run without first creating it — the `oci_core_images`
data source needs a compartment that exists. So the decision the task depends
on is not available for free.

It stays deferred until the next rebuild, which `current.md` already records as
blocked on F11. Nothing is lost by waiting: the finding is preventive, and its
premise — no instance principal in `compute.tf` — still holds, so there is no
grant for the root compartment to over-scope today.

**Description**: **F15.6**, preventive and last for a reason.
`terraform.tfvars` sets `compartment_ocid` to the tenancy OCID, so everything
lives in the root compartment. Harmless while there is no instance principal —
`compute.tf` has none, which is F15's own good news — but any future IAM grant
to this instance would be scoped to the whole tenancy.

Create a child compartment and repoint `compartment_ocid` at it, so a later
grant is bounded by construction. Keep instance principals off unless a
concrete need appears.

**Expect this to want a rebuild.** Moving existing resources between
compartments is per-resource and partly unsupported, and `terraform plan` will
likely show replacement — which also means a fresh box, which
`current.md` records as blocked until F11 teaches cloud-init the branch and the
`DOME_*` vars. **Run the plan, and if it replaces the instance, defer this
step to the next rebuild and say so in the feature file** rather than
destroying a working box for a preventive fix.

*Test:* if applied, assert `terraform.tfvars.example` documents a child
compartment and no longer suggests the tenancy OCID. If deferred, no test —
record the deferral.

## TF15.15 — the F15 test suite

**Status**: done

**Description**: Finalize `tests/test_f15_blast_radius.sh` as the feature's
dedicated suite, following `test_f14_vnc_access.sh`'s shape: `pass`/`fail`
counters, per-task sections, static checks over `manifest/`, `scripts/`,
`terraform/` and `02-doc/`, `bash -n` on every touched script.

Three checks beyond the per-step assertions:

- **No unpinned third-party execution anywhere.** Scan `manifest/tools.txt`
  and every `curl`/`wget` in `scripts/` for a `raw.githubusercontent.com` URL
  on `master`/`main`, or a `curl … | sh`/`| bash` without a preceding digest
  check. This is the check that stops F15.2 from growing back with the next
  tool added.
- **No `0.0.0.0/0` on the VNC port.** Assert it in `network.tf` and in the
  `Makefile`'s `vnc-up`, so a later edit cannot quietly undo TF15.8.
- **`stop` disarms.** Assert the dependency from TF15.6 survives, since it is
  a Makefile prerequisite and easy to drop in an unrelated edit.

Also confirm `test_f14_vnc_access.sh` still passes: TF15.7 stops enabling the
units, and F14's suite asserts `systemctl enable dome-vnc.service` in
`bare-metal-base.sh` (`test_f14_vnc_access.sh` ~line 44). **That assertion must
be updated, not deleted** — it becomes "installs the unit without enabling it",
which is F15's new invariant and still worth pinning.

*Test:* this task is the test.

## TF15.16 — live verification on the box

**Status**: not done — box is STOPPED

**Description**: The static suite cannot prove any of this. Run F15's *How to
Demo* against `dome-cloud-1` and record command, expectation and actual result
per `.claude/style_guide.md`'s manual-test rule.

Ordered so a mistake is recoverable — **keep a second SSH session open
throughout**, because TF15.11 and TF15.12 can both lock you out:

1. `ssh -A` to the box, then `ssh-add -l` and `ssh -T git@github.com` on it.
   Expect no agent and a failed GitHub auth: box compromise cannot push to the
   org, which is what closes the git-borne route to the robot.
2. `make -C terraform/oci audit` — expect a pass, naming no credential files
   and no private keys.
3. From a host other than the approved address, open
   `http://<ip>:48210/vnc.html` — expect **refused at the OCI edge**, not a
   password prompt. Then confirm it still works from the approved address.
4. `make -C terraform/oci stop`, then re-check the security list — expect
   48210 closed. `make start` and re-check — expect it still closed until an
   explicit `vnc-up`.
5. Reboot the box; confirm no desktop is served until `vnc-up`.
6. Verify the provisioned `mcfly` and `rosutils` match the pins, resolving
   `git -C ~/rosutils rev-parse HEAD` against `repos.txt`.

Finish by reconciling the two live-box discrepancies `current.md` records —
`DOME_TARGET=vm` where it should be `cloud`, and the duplicated
`DOME_DESKTOP=vnc` line — or confirm they are F11's to fix and leave them
named.

*Test:* this task is the manual test; record results in the feature file.

## TF15.17 — close out

**Status**: not done

**Description**: Set F15's **Done**, **Tests Written** and **Test Passing** to
yes, move `03-features/notdone/f15-cloud-box-blast-radius.md` to
`03-features/done/` and this file to `04-tasks/done/`, and update
`02-doc/current.md` — which is stale in a way F15's own findings care about: it
still lists F15.9 as unfixed and does not mention F16 or F17 at all.

Any finding deliberately not implemented (TF15.2's pin if the vendor offers
none, TF15.14 if the plan wants a rebuild) is recorded in the feature file as a
**decision with its reason**, not dropped. A feature closed with a silent gap
is the same failure mode F15 documents throughout.

*Test:* none — bookkeeping.

## F15 amendments — applied 2026-09-26

All seven were approved and written into
`03-features/notdone/f15-cloud-box-blast-radius.md`. Kept here as the record of
what changed in the spec and why, since each one is a correction to a
recommendation the tree would not have supported.

1. **F15.3's "the format already supports a branch field"** — change to say a
   commit pin needs clone-then-checkout support, because `git clone --branch`
   rejects a SHA. Currently it reads as a one-line manifest edit.
2. **F15.1 and F15.7's sshd items** — note that this repo manages no sshd
   config, so the fix is a new drop-in installed by `bare-metal-base.sh`, and
   that Terraform passes no `user_data` (`compute.tf:13`), so cloud-init is not
   the delivery path for the live box.
3. **F15.1's key recommendation** — add that rotating `ssh_public_key_path`
   governs future boxes only; cloud-init reads the metadata at first boot, so
   the live box needs a hand edit.
4. **F15.7's `fail2ban` line** — downgrade from "real value for 48210" to
   skipped-with-reason: no stock websockify/VNC filter exists, and F15.5's CIDR
   half supersedes it.
5. **F15.9's tfvars-drift bullet** — record that `terraform.tfvars` does not
   currently set `vnc_access`, so the drift is latent rather than present.
6. **F15.5** — add the VNC password's silent 8-character truncation to the
   *recommendation*, not just the finding; it changes what the docs must say
   next to `vncpasswd`.
7. **The `How to Demo` list is numbered 7–14** (a Markdown continuation
   artifact) and its steps do not align with its expected outputs. Renumber
   1–4 / 1–4.
