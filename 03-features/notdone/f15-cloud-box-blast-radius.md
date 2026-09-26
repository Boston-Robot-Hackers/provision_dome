# Feature description for feature F15

## F15 — Contain the cloud box's blast radius

**Priority**: High

**Done:** no

**Tasks File Created:** yes

**Tests Written:** yes

**Test Passing:** yes (73 checks; suite 375 green)

**Description**: Harden **the box** so that fully losing it costs only itself.
Machine names (*the box*, *the robot*, *the Mac*, *the VM*, and `dome-docker`,
which is an artifact rather than a host) are defined once in `02-doc/notes.md`,
*Vocabulary*, and are not redefined here.

Scope is the box. The robot, the VM, `dome-docker` and F08's robot-graph work
enter only where a weakness the box shares with them makes the box's loss
someone else's problem.

### Threat model

**Premise, from the user: the box is expendable.** Port 48210 is open to
`0.0.0.0/0` with a VNC password in front of a desktop holding `NOPASSWD:ALL`
sudo, so "attacker has root on the box" is an accepted starting position, not a
finding. Nothing below argues with that.

The question is the next one: **from root on the box, what else falls?**
Findings are graded on cost *beyond* the box — the GitHub org, the robot, the
OCI tenancy and the Mac — and on whether that cost is **live today** or
merely reachable in a worst case.

**Three traps this review had to correct itself on.** Each is recorded because
the wrong intuition is the natural one:

- **"Unreachable" is not "safe."** The robot has no route from the box
  (`192.168.4.100`, no Tailscale yet). But reachability only governs
  connections made *to* the robot, and the robot **pulls code** — from GitHub,
  from `campusrover/rosutils`, from `raw.githubusercontent.com` — and runs it
  as root. Grade on **what the robot fetches**, not on what can dial it.

- **"No private keys on the box" is not "no credentials reachable."** A
  forwarded SSH agent is a *signing oracle*, not stored key material: the key
  stays on the Mac and is used remotely. The box having no keys is exactly the
  condition under which that still works. (It is nonetheless not live here —
  see F15.1.)

- **A worst case is not a current state.** F15.1 was first graded High by
  chaining three conditions and presenting the chain as fact. Grade on
  conditions that hold *today*, and say which they are.

### The Mac is the real crown jewel, and it is out of scope

Named explicitly because the box-only framing hides it. The Mac holds
`~/.ssh/id_ed25519` — one key that is simultaneously the GitHub key, the robot
key and the box key — plus `terraform.tfstate` and **`~/.oci/oci_api_key.pem`,
the OCI API private key, which is full control of the tenancy**.

So the ranking is: **Mac > robot > box**, and the machine described as "not
part of the operation" outranks the other two combined. Losing the Mac loses
everything, including the ability to rebuild.

This is not a reason to widen F15 — the box cannot reach the Mac, which
initiates every connection (the one exception is F15.8). It is a reason to
note that **the Mac deserves its own review**, and that two findings here
(F15.1, F15.2) have their root cause on the Mac even though they bite
elsewhere.

### What is already correct

Recorded so the audit isn't re-run on settled ground. Verified live on
`dome-cloud-1` and in the tree on 2026-09-26:

- **No private key material on the box.** `~/.ssh/` holds only
  `authorized_keys` and `known_hosts`; a filesystem sweep for private keys
  found nothing. F10's `PUBLIC_ONLY` is doing its job.

- **No OCI instance principal or dynamic group** in `compute.tf`. The box
  cannot call the OCI API, which closes the worst pivot (box → tenancy).

- **No live credentials on the box.** `~/.claude.json` has no `oauthAccount`
  and no `primaryApiKey`, and `~/.claude/.credentials.json` does not exist.

- **Secrets stay out of git.** `terraform.tfvars`, `*.tfstate`, and
  `manifest/user.txt` are all gitignored; a sweep of tracked files for key and
  token patterns found only documentation and placeholders.

- **Third-party apt repos are properly pinned to keyrings** — both
  (`github-cli`, `vscode`) use `signed-by=`, none use `apt-key`/unsigned.

- **`unattended-upgrades` is active**; `rosutils` is cloned read-only over
  HTTPS.

---

## Findings

### F15.1 — One SSH key is the box key, the GitHub key, and the robot key

**Severity: Low today, Medium preventive.** Not a live vulnerability — a
hardening item. Graded down from an initial "High" after review; the original
grade chained three conditions together and presented the chain as a current
state. See *Why this is not live* below.

`~/.ssh/id_ed25519` (`SHA256:x+WKIprPTccLpDARo+FJqyxN/+jaTWzc+UBZu5ovLn4`) is
simultaneously the key in `compute.tf`'s `ssh_authorized_keys`, the key that
authenticates to **GitHub** (verified: `ssh -T git@github.com` → `Hi
pitosalas!`), the only key in the laptop's `ssh-agent`, and — by the
`dome1`/`dome2`/`dome3`/`robot` blocks in `~/.ssh/config` — almost certainly
the key to **the robot**.

The box only ever receives the **public** half, so this is not currently a
leak. What makes it dangerous is the combination with the box's sshd:

```
allowagentforwarding yes
x11forwarding yes
```

A single `ssh -A` to the box hands root-on-the-box a live agent socket that
signs as the user. The laptop's config has a bare `Host *` block, so a
`ForwardAgent yes` added there later would silently apply to the box too.

**What that agent can and cannot reach today.** Verified 2026-09-26:

- **GitHub: reachable now.** The box has a working route to `github.com` — it
  is how the repo is cloned and pulled. A stolen agent signs as the user
  against the whole `Boston-Robot-Hackers` org.

- **The robot: not reachable now.** `robot` is `192.168.4.100` (RFC1918); the
  box has no route to it, cannot resolve the name, and has no Tailscale. The
  direct box→robot SSH hop **does not work today.**

This does *not* make the robot safe, because **the robot reaches out.** An
attacker who pushes to `provision_dome` (or any `dome*` repo) with the stolen
agent is executed on the Pi at its next `git pull` + `bare-metal-build.sh`.
The path into the robot is git, which the robot initiates — not SSH, which it
would have to accept. Network unreachability does not close it.

**Why this is not live.** Three conditions must hold at once, and none hold
today (verified 2026-09-26):

- **The box holds no private key.** Confirmed by a filesystem sweep. Agent
  forwarding would not need one — a forwarded agent is a *signing oracle*
  reached over `$SSH_AUTH_SOCK`, so the key stays on the laptop and is used
  remotely rather than stolen. But that only matters if the socket exists.

- **The laptop does not forward the agent.** There is no `ForwardAgent` in
  `~/.ssh/config`, including in the `Host *` block. No `ssh -A`, no socket, no
  capability.

- **The window is a single session.** The socket lives only for the duration
  of a forwarded login, so an attacker must already be resident and waiting.

Without a forwarded agent the box genuinely cannot write to GitHub: `gh` is
installed but unauthenticated, and both git remotes are anonymous HTTPS, which
is read-only. **The correct reading is "one `ssh -A` away," not "exposed."**

**Why fix it anyway.** The mitigation is one `terraform.tfvars` line plus two
sshd directives, and F08's entire purpose is to put this box on Tailscale and
join the robot's ROS graph — which adds the network leg this finding currently
lacks. Cheaper before the box is load-bearing than after.

**Recommendation.** Break the shared identity rather than rely on remembering
not to type `-A`:

- Generate a **dedicated keypair per cloud box** and point
  `var.ssh_public_key_path` at it — the variable already exists, so this is a
  `terraform.tfvars` line plus a doc change.

  **This governs future boxes only, and changing it on an existing box is
  destructive.** Verified 2026-09-26: `terraform plan` reports
  `oci_core_instance.dome must be replaced` — OCI treats instance metadata as
  force-replacement, so an apply would destroy the box, its boot volume, the
  cloned repos and the built workspace, not update its `authorized_keys`.
  (Cloud-init reads `ssh_authorized_keys` at first boot in any case.)

  So the variable is set when a box is **created**, and `dome-cloud-1` is
  re-keyed **by hand**: append the new public key to `~/.ssh/authorized_keys`,
  prove login from a second session, then remove the old entry. Keep the value
  out of `terraform.tfvars` until the next rebuild — which F11 gates — or any
  later full `terraform apply` becomes a box-destroying landmine.

- Set `AllowAgentForwarding no` and `X11Forwarding no` in the box's sshd
  config (nothing in the workflow needs either; Foxglove and tunnel-mode VNC
  use `-L`, which is `AllowTcpForwarding`, not agent forwarding).

  **There is no sshd config in this repo to edit.** Those settings are Ubuntu
  image defaults, so this needs a new `/etc/ssh/sshd_config.d/` drop-in. It
  cannot arrive by cloud-init either: `compute.tf:13-16` passes **no
  `user_data`** — `metadata` carries only `ssh_authorized_keys`, and the
  template is the hand-pasted console path. `scripts/bare-metal-base.sh` is
  the only mechanism that reaches the live box, and it must `sshd -t` before
  reloading, since an invalid drop-in locks out a box reachable only by SSH.

- Add an explicit `ForwardAgent no` for the box in the laptop's `~/.ssh/config`
  as defense in depth.

### F15.2 — `curl | sh` as root from an unpinned branch, on every target

**Severity: High.** Reaches the robot, so not box-scoped.

`scripts/bare-metal-base.sh:166-168` pipes downloaded scripts straight into a
shell, and `manifest/tools.txt` pins nothing:

- **`[mcfly]`** runs **as root** from
  `raw.githubusercontent.com/cantino/mcfly/master/ci/install.sh` — the
  `master` branch, no tag, no commit, no checksum.
- **`[claude-code]`** runs from `claude.ai/install.sh` as `DOME_USER`, also
  unpinned.

This same manifest provisions the **Pi**. A compromise of that upstream branch
is root on the robot, not just on an expendable VM.

**Recommendation.** Pin `[mcfly]` to a release tag or commit SHA rather than
`master`, and add an optional `sha256` field to `tools.txt` that
`bare-metal-base.sh` verifies before executing. Prefer a released binary
artifact over a pipe-to-shell installer where one exists.

### F15.3 — Unpinned third-party shell code sourced into every shell

**Severity: High.** Also reaches the robot.

`manifest/bashrc:3` sources `~/rosutils/ros2_robot_bashrc.bash` in every
interactive shell on every target. `rosutils` is cloned from
`campusrover/rosutils` with **no branch or commit pin**, so whatever is on
`main` at clone time runs as the user, everywhere.

That file also contained a secret-manager hook that read a Doppler token,
which would have put a whole secret store one box compromise away had one ever
been configured.

**Resolved by removal (2026-09-26): Doppler is gone from this project
entirely** — the `[doppler]` apt repo is deleted, so the CLI the hook calls is
no longer installed on any target and the hook cannot resolve a token. That is
strictly better than a written rule not to log in, which this feature originally
proposed: there is now nothing to log into.

**Recommendation.** Pin `rosutils` to a commit in `repos.txt`. The Doppler half
of this finding needs no further action.

**The existing branch field cannot carry the pin.** `clone_section` passes it
to `git clone --branch`, which accepts branches and tags only — a 40-hex SHA
fails outright, and a tag can be moved by its author. Pinning to a commit means
teaching the parser to recognize a SHA and the cloner to clone then
`git checkout --detach`, **mirrored in the `Dockerfile`'s duplicated clone
loop** — the divergence that already left the image ignoring
`DOME_CLONE_OVERRIDE`.

### F15.4 — An exposed box accumulates credentials over time

**Severity: Medium-High.** Latent: correct today, degrades with use.

Provisioning installs `claude-code` and `gh` on a box that, in `public` mode,
is internet-facing. Both are clean right now. But the first `claude` login or
`gh auth login` writes a live account token to disk, and `cloud-howto.md`'s
"Optional: a private cloud dev box" section documents adding a GitHub key that
**can push to the user's repos** — it warns about this, but the warning
predates public VNC mode and now understates the risk.

The "box is expendable" premise silently stops being true the moment any of
that happens.

**Recommendation.** State the rule in the docs: **no interactive credential
login on a `public`-mode box.** If a GitHub credential is genuinely needed,
use a **read-only deploy key scoped to one repo**, never an account key. Add a
`make audit` target that fails if `~/.claude/.credentials.json`, `~/.config/gh`,
`~/.git-credentials`, or any private key appears on the box.

### F15.5 — The public desktop is plaintext and unthrottled

**Severity: Medium** for the box itself (accepted), but it is the **front door
to every finding above**, so it is worth fixing on those grounds alone.

`scripts/start-desktop.sh:69` runs websockify with no TLS:

```
exec websockify --web="${NOVNC_WEB}" "${BIND}" localhost:5901
```

Consequences: noVNC is served over `ws://`, so screen contents and every
keystroke cross the internet in the clear; the VNC DES challenge-response can
be captured and cracked offline; and the VNC protocol **silently truncates the
password to 8 characters**, so a long passphrase provides no extra strength.
`fail2ban` is inactive, so guesses against 48210 are unlimited.

**Recommendation.** Two independent improvements, either of which helps:

- Give websockify `--cert` (self-signed is enough for this) so the desktop is
  `wss://`, **and `--ssl-only`**. Verified live 2026-09-26: with `--cert` alone
  websockify still accepts plaintext on the same port — `http://<ip>:48210`
  returned **200** — so the encryption is advisory and any browser defaulting to
  `http://` gets a cleartext session and a capturable challenge-response.
  `--cert` without `--ssl-only` does not close this finding.

  Say in the docs that the browser will warn about the self-signed
  certificate — an unexplained warning on a page the user has just been told to
  distrust is worse than no change.
- **Narrow the ingress CIDR.** `network.tf:53` hardcodes `source =
  "0.0.0.0/0"`; making it a variable defaulting to the user's own IP removes
  the entire internet from the threat surface and costs nothing in
  convenience.
- **Document the 8-character truncation next to the `vncpasswd` step.** This is
  a doc change, not a code one, and it belongs in the recommendation rather
  than only in the finding above: a user who picks a long passphrase today gets
  no benefit from it and has no way to find that out.

### F15.6 — Root-compartment placement

**Severity: Medium**, preventive.

`terraform.tfvars` sets `compartment_ocid` to the **tenancy OCID**, so every
resource lives in the root compartment. This is harmless while there is no
instance principal (F15's good news above), but it means any future grant to
this instance would be scoped to the whole tenancy.

**Recommendation.** Create a dedicated child compartment for the dev host so
that any later IAM grant is bounded by construction. Keep instance principals
off unless a concrete need appears.

### F15.7 — Hygiene

**Severity: Low.** Defense in depth; none of these are reachable today.

- **`rpcbind` listens on `0.0.0.0:111`.** Blocked by both the OCI security list
  and the local iptables policy, but nothing in this project uses it — mask
  the socket.
- **`fail2ban` inactive** — low value for key-only SSH, and the value it would
  add on 48210 is **not available off the shelf**: there is no stock filter for
  websockify or VNC, so it means authoring one against websockify's output.
  F15.5's CIDR half removes the internet from that port outright and
  supersedes it. **Skipped deliberately**, not overlooked.
- **`permitrootlogin without-password`** — the OCI image's root key carries a
  forced command, but `PermitRootLogin no` is cleaner and costs nothing.
- **`ubuntu ALL=(ALL) NOPASSWD:ALL`** — in scope under "box expendable", but
  should be written down as a deliberate decision rather than an accident of
  cloud-init.
- **DDS binds to the VCN address** (`10.0.1.235:44733` and friends), not
  loopback. Not reachable from outside, since the security list admits only 22
  and 48210 — worth re-checking if a second instance ever joins the subnet.

### F15.8 — The box attacks back: client-side surface on the Mac

**Severity: Low.** Added after the Mac was brought into the model; it is the
**only** direction in which a compromised box touches the Mac, since the Mac
initiates every connection.

Three candidate vectors were checked on 2026-09-26. Two are closed:

- **X11 forwarding: closed.** The box advertises `x11forwarding yes`, but
  **XQuartz is not installed on the Mac** and no `ForwardX11` appears in
  `~/.ssh/config`, so there is no X client to attack. Worth keeping that way —
  `ssh -X` to a hostile box is a keylogger.

- **Agent forwarding: closed today.** See F15.1.

One is open:

- **noVNC is untrusted JavaScript from a machine assumed hostile.** Using the
  desktop means opening `http://<box>:48210/vnc.html` **in the Mac's browser**,
  so a compromised box serves arbitrary JS to it, over plaintext HTTP, on a
  bare-IP origin. The browser sandbox is the only thing between that page and
  the Mac. It cannot read local files, but it can phish convincingly, abuse
  anything already authenticated to that origin, and reach whatever the
  browser's attack surface allows.

**Recommendation.** Mostly a stated rule rather than code: open the noVNC page
in a **separate browser profile** with no signed-in sessions, and never enter
Mac or GitHub credentials into anything that page shows. F15.5's TLS half also
helps by giving the origin an identity. Keep XQuartz off the Mac; if it is ever
installed, set `X11Forwarding no` on the box.

### F15.9 — Stopping the box does not disarm it

**Severity: Medium.** A design defect in F14, found 2026-09-26 by assuming a
stopped box was a closed one and being wrong.

**The invariant, per the user: *stopped should mean disarmed.*** It does not
hold today.

`make stop` issues a `SOFTSTOP` and nothing else. After it:

- the security list still admits **`48210` from `0.0.0.0/0`**, and
- `dome-vnc.service` and `dome-vnc-firewall.service` are both **`enabled`**.

So `make start` silently restores a publicly reachable desktop — no
`vnc-up`, no prompt, no output saying so. Disarming requires remembering a
separate `make vnc-down`, and the whole point of stopping the box between
sessions is that it is the thing you *do* remember.

This also quietly widens every other finding here: the exposure window is not
"while I am using it" but "from the first `vnc-up` until I happen to run
`vnc-down`", spanning any number of stop/start cycles.

**Recommendation.** Make the lifecycle target enforce the invariant rather
than rely on a second command:

- **`make stop` closes the port** — run the existing `vnc_access=none` apply
  as part of stopping. The security list is the authoritative boundary, so
  this alone establishes the invariant.
- **Consider also not enabling the units on boot**, so that arming is always
  an explicit `vnc-up`. Defense in depth: with the port closed at the edge a
  running `dome-vnc` is unreachable anyway, but "enabled" is a standing
  intent to serve that nothing in the workflow ever revokes.
- **Watch for tfvars drift.** `vnc-up`/`vnc-down` flip `vnc_access` with
  `-var` and `-target` overrides, so a later full `terraform apply` re-reads
  `terraform.tfvars` and can silently reopen the port. Whichever way this is
  fixed, the steady-state value in `tfvars` must agree.

  **This is latent, not present.** `terraform.tfvars` does not set
  `vnc_access` today, so it takes the variable's `none` default and a full
  apply currently closes the port rather than opening it. The drift appears the
  moment someone writes `vnc_access = "public"` into that file — which is why
  the steady state belongs in `terraform.tfvars.example` as a stated rule.

**Status:** the live box was disarmed by hand on 2026-09-26 (security list now
admits SSH only). The defect itself is unfixed.

---

## Suggested order

Ordered by what is **live today**, not by worst case. Reordered after review:
F15.1 was originally first on the strength of a worst case that turned out to
depend on conditions that do not currently hold.

1. **F15.2 / F15.3** — pin `mcfly`, `claude-code`, and `rosutils`. **The only
   findings that are unconditionally live**, and they apply to the *robot*,
   which is not expendable. No box compromise, credential, or network path is
   required for these to bite.
2. **F15.9** — make `make stop` close the port, so *stopped means disarmed*.
   Small, and it bounds the exposure window for every other finding here.
3. **F15.5 (CIDR half)** — narrow 48210 from `0.0.0.0/0` to one IP. One
   variable; removes the internet from the attack surface.
4. **F15.4** — write down the no-interactive-login rule; add `make audit`.
   Prevents the box from silently accumulating what it currently lacks.
5. **F15.1** — dedicated box key + `AllowAgentForwarding no`. Preventive, and
   worth doing before F08 adds the missing network leg. Note the fix lives on
   **the Mac** (a per-box keypair), not on the box.
6. **F15.5 (TLS half)**, **F15.6**, **F15.7**, **F15.8**.

**Deliberately not in F15: a review of the Mac.** It outranks every machine
here (`~/.oci/oci_api_key.pem` alone is the whole tenancy), but it is not
reachable from the box, so it belongs in its own feature — now **F16**
(`03-features/notdone/f16-workstation-key-custody.md`). F16 found both of the
Mac's crown-jewel private keys stored unencrypted, which makes it the higher
priority of the two.

## How to Demo

**Setup**: `dome-cloud-1` running and provisioned in `public` VNC mode, with
the F15 changes applied.

**Steps**:

1. From the laptop, run `ssh -A` to the box, then on the box run
   `ssh-add -l` and `ssh -T git@github.com`.
2. Run `make -C terraform/oci audit` (new target) against the box.
3. From a host **other** than the approved IP, open
   `http://<ip>:48210/vnc.html`.
4. Inspect the provisioned `mcfly`, `claude-code`, and `rosutils` versions
   against the pins in `manifest/tools.txt` and `manifest/repos.txt`.

**Expected output**:

1. Agent forwarding is refused — `ssh-add -l` reports no agent, and the GitHub
   auth attempt fails. Box compromise therefore cannot push to the org, which
   is what closes the git-borne route to the robot.
2. The audit passes, reporting no credential files and no private keys.
3. The connection is refused at the OCI edge, not merely password-prompted.
4. Each resolves to the exact pinned commit/digest, not a moving branch. If
   `claude-code`'s installer offers no version pin, the expected result is the
   recorded finding saying so — see F15.2.

**Keep a second SSH session open throughout.** The sshd drop-in and the key
rotation can each lock you out of a box whose only other door is the VNC
desktop this feature is busy closing.
