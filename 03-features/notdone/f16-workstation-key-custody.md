# Feature description for feature F16

## F16 — Key custody on the Mac

**Priority**: High

**Done:** no

**Tasks File Created:** no

**Tests Written:** no

**Test Passing:** no

**Description**: Harden **the Mac** (see `02-doc/notes.md`, *Vocabulary*) so
that code running as the logged-in user cannot walk away with the credentials
to every other machine. Opened out of F15, which found that the workstation
described as "not part of the operation" outranks every host it reviewed.

### Threat model — and why it is not F15's

F15 could assume its subject was expendable. **This one is the opposite: the
Mac is the only machine whose loss is unrecoverable.** It is not a robot that
can be reflashed or a VM Terraform can recreate; it holds the credentials that
would be used to rebuild the others.

What it holds, verified 2026-09-26:

- **`~/.ssh/id_ed25519`** — one key that authenticates to **GitHub**, **the
  robot**, **the box**, and the other hosts in `~/.ssh/config` (6 `Host`
  entries).
- **`~/.oci/oci_api_key.pem`** — the OCI API private key. Not scoped to the
  instance: it is **the tenancy**.
- **`terraform.tfstate`** — the infrastructure's topology and OCIDs.
- The **build host for `dome-docker`**, the image the robot runs.

The realistic adversary is therefore **not laptop theft**. It is *any code
executing as the user*: a malicious npm, pip or brew package, a rogue editor
extension, a compromised CLI. That distinction drives every finding below.

### What is already correct

Recorded so it is not re-audited:

- **FileVault is On.** Full-disk encryption at rest.
- **Credential file permissions are right** — `id_ed25519`, `oci_api_key.pem`
  and `~/.oci/config` are all `-rw-------`, owned by the user.
- **No agent forwarding.** No `ForwardAgent` anywhere in `~/.ssh/config`,
  including the `Host *` block. This is what keeps F15.1 from being live.
- **No Docker Hub or `gh` tokens on disk** — `~/.docker/config.json` has no
  `auths`, and `~/.config/gh/hosts.yml` does not exist.
- **`terraform.tfstate` holds no private key material** — the SSH *public* key
  and OCIDs only.
- **`AddKeysToAgent yes` + `UseKeychain yes`** are already set, which makes
  F16.1's fix nearly free.

---

## Findings

### F16.1 — Both crown-jewel private keys are plaintext on disk

**Severity: High.** The central finding; everything else is smaller.

```
id_ed25519:      NO PASSPHRASE (usable by anyone who reads the file)
oci_api_key.pem: NOT encrypted (plaintext private key)
```

Any process running as the user can read either file and use it immediately —
no prompt, no keychain, no interaction. One `cat` is GitHub write access to
the org, SSH to the robot, and **full control of the OCI tenancy**.

**FileVault does not help here.** It protects a powered-off machine against
someone holding it. Against code running while the user is logged in — the
realistic threat to a dev workstation — the disk is mounted and decrypted and
the keys are ordinary readable files. The `-rw-------` permissions are correct
and equally irrelevant: the attacker *is* the user.

There is a pointed recursion here. **F15.2 and F15.3 object to unpinned
`curl | sh` supply chain on the targets. The Mac has the same class of
exposure** — brew, npm, pip, extensions — **and holds incomparably more.**

**Recommendation.**

- **Put a passphrase on `id_ed25519`** (`ssh-keygen -p -f ~/.ssh/id_ed25519`).
  Because `AddKeysToAgent yes` and `UseKeychain yes` are already configured,
  this costs **one unlock per boot** and nothing after. Best ratio of safety
  to friction available here.
- **Better, if appetite allows:** move to a hardware-backed key — Secure
  Enclave (e.g. `secretive`) or a YubiKey — so the private key cannot be read
  by any process at all, only *used*, with presence required.
- **For OCI, prefer short-lived credentials:** `oci session authenticate`
  issues a session token instead of a permanent API key. Failing that, encrypt
  the key with a passphrase and rotate the current one, which has been
  plaintext for its whole life.

### F16.2 — One key for six hosts and GitHub means no revocation granularity

**Severity: Medium-High.** Blast-radius shape rather than a hole.

The same key authenticates everything. There is no way to revoke the robot's
trust without simultaneously breaking GitHub, the box, and three other hosts —
so in an incident the choice is a painful full re-key or leaving access live.

It also defeats containment: a key leaked from *any* single context is a leak
of *all* contexts.

**Recommendation.** Split by role — a GitHub key, a robot key, a per-cloud-box
key (F15.1 already asks for the last, and `var.ssh_public_key_path` exists to
receive it). Distinguish them in `~/.ssh/config` with `IdentityFile` plus
`IdentitiesOnly yes` so the right key is offered to the right host.

### F16.3 — `docker login` will write a plaintext token

**Severity: Medium.** Latent: clean today, degrades the first time it is used.

`~/.docker/config.json` currently has no `auths` — but it also has **no
`credsStore`**. Docker therefore defaults to writing credentials into that
file as **base64, which is encoding, not encryption**, rather than into the
macOS keychain.

This matters because `docker-howto.md` Step 2 is *"Mac — Build And Push"*: the
documented workflow ends in a `docker login`. The registry account it would
expose publishes **the image the robot runs**, so a stolen token is a path to
the robot that needs no network access to it.

**Recommendation.** Set `"credsStore": "osxkeychain"` in
`~/.docker/config.json` **before** the next `docker login`, and say so in
`docker-howto.md` Step 2. If a token was ever stored, rotate it.

### F16.4 — `terraform.tfstate` is world-readable

**Severity: Low.** Free to fix.

```
-rw-r--r--  pitosalas  22508 bytes
```

It holds no private key material — verified — so this is infrastructure
topology, OCIDs and the SSH public key, not secrets. But state files are a
known place for provider secrets to land, and `0644` is an accident rather
than a decision.

**Recommendation.** `chmod 600`, and treat the whole `terraform/oci/`
directory as credential-adjacent. Already gitignored, which is the important
half.

### F16.5 — The Mac's own supply chain is unreviewed

**Severity: Medium**, and deliberately left open rather than answered.

F15 scrutinised what the *targets* install. Nothing has examined what the
**Mac** runs as the user: brew formulae, global npm and pip packages, editor
extensions, and any `curl | sh` in this project's own Mac-side instructions.

Given F16.1, **any one of those is a full credential compromise**, so the Mac
arguably deserves stricter supply-chain hygiene than the robot — the inverse
of where attention has gone so far.

**Recommendation.** Treat as a scoping task, not a fix: inventory what runs as
the user, decide what actually needs to be installed globally, and prefer
project-scoped tooling. Fixing F16.1 first substantially reduces what any of
it can steal, which is why this is listed last.

---

## Suggested order

Strictly by payoff; the first item removes most of the risk on its own.

1. **F16.1** — passphrase `id_ed25519`. One command, one unlock per boot,
   `UseKeychain` already configured. This alone converts "any code as the user
   takes everything" into "an attacker must also defeat the keychain."
2. **F16.1 (OCI half)** — move to session tokens or encrypt and rotate the API
   key. Highest-value credential on the machine.
3. **F16.3** — set `credsStore` before the next `docker login`. Preventive and
   free.
4. **F16.4** — `chmod 600` the state file.
5. **F16.2** — split the identity by role. Do it alongside F15.1, which needs
   a box-specific key anyway.
6. **F16.5** — inventory the Mac's supply chain.

## How to Demo

**Setup**: the Mac, after applying F16.1–F16.4.

**Steps**:

1. `ssh-keygen -y -P "" -f ~/.ssh/id_ed25519`
2. `head -1 ~/.oci/oci_api_key.pem`
3. Reboot, then `ssh dome-cloud-1` — observe the unlock prompt — then run it a
   second time.
4. `stat -f '%Sp' terraform/oci/terraform.tfstate`
5. `docker login`, then inspect `~/.docker/config.json`.

**Expected output**:

1. Fails — the key is passphrase-protected and cannot be read unattended.
2. Reports `ENCRYPTED`, or the file is gone in favour of a session token.
3. Prompts once, then not again: the passphrase is cached by the keychain and
   agent, confirming the cost is one unlock per boot.
4. `-rw-------`.
5. No `auths` entry in the file; the credential is in the macOS keychain.
