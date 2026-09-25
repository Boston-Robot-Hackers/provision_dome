# Feature description for feature F11

## F11 — Terraform creates the login account as DOME_USER, with a password

**Priority**: Medium
**Done:** no
**Tasks File Created:** yes
**Tests Written:** no
**Test Passing:** no

**Description**: Make the OCI host's login account **the user you choose**
(`DOME_USER`), with a password, instead of the image's default `ubuntu`. Today
Terraform builds a bare box and everything runs as `ubuntu` with a
`DOME_USER=ubuntu` workaround. This feature folds F07's cloud-init template
into `terraform/oci/` so the account is created at first boot.

## Decisions (made with the user)

- **Supplied via Terraform variables:** `host_user` and `host_password_hash`
  in the git-ignored `terraform.tfvars`. Only a **hash** is sent to the box.
  The hash also lands in Terraform state, which is already git-ignored.
- **The password is for `sudo` only.** SSH stays **key-only**
  (`ssh_pwauth: false`), because this box is on the public internet and a
  password on port 22 can be brute-forced. The account still logs in with your
  SSH key.
- **Not `ubuntu`.** The cloud-init `users:` list names only the host user and
  omits `default`, so cloud-init does not create `ubuntu`.

## Why

- `DOME_USER=ubuntu` was a workaround for the F07 breakage "login user is not
  `DOME_USER`". The cloud-init template already fixes that, but Terraform
  never used it.
- A real user with a real password matches how you use the Pi and VM.

## Hard constraints

- **Purely additive.** `pi`, `vm` and `docker` are unchanged.
- The hand-filled cloud-init path in `cloud-howto.md` (other providers) keeps
  working. The password hash is **optional** in the template.
- No secret in the repo: no password, no hash, no key in any tracked file.

## Add

- Template: optional password hash, `sudo` requires it when set, explicit
  `ssh_pwauth: false`.
- Terraform: `host_user`, `host_password_hash` (sensitive), rendered template as
  the instance's `user_data`.
- `make ssh` and the vnc targets log in as the host user, not `ubuntu`.
- Docs: how to generate the hash, and the new Terraform path.

## Do not change

- `DOME_TARGET`, `DOME_MODE`, `DOME_DESKTOP`, `DOME_CLONE_OVERRIDE` semantics.
- The SSH-only security list.

## Open decision: the existing box

`dome-cloud-1` runs as `ubuntu` with the private repos and a built workspace.
Changing `user_data` does not re-run cloud-init on a live instance, so the new
account needs a **fresh instance**. Options: destroy and re-apply
`dome-cloud-1` (loses the current workspace), or add a second box with a
`terraform workspace` (billed, since the free arm allowance is used up).

## How to Demo

**Setup**: `terraform.tfvars` with `host_user` and `host_password_hash`.

**Steps**:
1. `terraform apply` a fresh instance.
2. `make ssh` logs in as your user, by key.
3. `sudo whoami` asks for the password, then prints `root`.
4. `ssh -o PubkeyAuthentication=no <user>@<ip>` is refused.
5. `id ubuntu` reports no such user.

**Expected output**: your own account, sudo behind a password, no password SSH,
no `ubuntu`.
