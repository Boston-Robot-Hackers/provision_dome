# TF11 Description for Feature F11

**Date Created:** 2026-09-24

Feature: Terraform creates the login account as `DOME_USER`, with a password
for `sudo` and key-only SSH. Purely additive; the hand-filled cloud-init path
keeps working.

## TF11.0 — Template: optional password, sudo behind it, no password SSH
**Status**: not done
**Description**: In `host-file-templates/cloud/user-data.template`, add a
`REPLACE_WITH_PASSWORD_HASH` placeholder. When a hash is supplied, set
`lock_passwd: false`, `passwd: <hash>` and `sudo: "ALL=(ALL) ALL"`. Always set
`ssh_pwauth: false`. Keep the current passwordless behavior when no hash is
given, so the hand-filled path is unchanged.

Decide how the optional part is expressed so the file stays valid YAML both
filled and unfilled; do not leave a literal placeholder in a filled copy.

Test: in `tests/test_f11_terraform_host_user.sh`, assert the template contains
the placeholder, `ssh_pwauth: false`, and still parses as YAML; assert a filled
render has a real `passwd:` line and `sudo: "ALL=(ALL) ALL"`, and an unfilled
render keeps today's behavior.

## TF11.1 — Terraform: host_user, host_password_hash, rendered user_data
**Status**: not done
**Description**: In `terraform/oci/`, add `host_user` and `host_password_hash`
(`sensitive = true`) to `variables.tf`, and set `metadata.user_data` to the
rendered template (base64) alongside `ssh_authorized_keys`. Fill the template's
placeholders from the variables and the public key file. Add an `ssh_user`
output. Update `terraform.tfvars.example` and the comment above the instance
that says "no cloud-init".

Confirm the `ubuntu` default user is not created, and that keeping
`ssh_authorized_keys` in metadata does not break cloud-init when there is no
default user.

Test: `terraform fmt -check`, `terraform validate` and `terraform plan` pass;
assert the variables are declared, the password one is `sensitive`, and no
literal hash or password appears in any tracked `.tf`, example, or template.

## TF11.2 — Makefile logs in as the host user
**Status**: not done
**Description**: `make ssh`, `vnc-up` and `vnc-down` hard-code `ubuntu`. Read the
user from the `ssh_user` Terraform output instead, and update the `help` text.

Test: assert the Makefile no longer contains `ubuntu@`; `make -n ssh` prints the
resolved user.

## TF11.3 — Docs
**Status**: not done
**Description**: `terraform/oci/README.md`: the new variables, how to generate a
hash (`mkpasswd -m sha-512` or `openssl passwd -6`), and that SSH stays
key-only. `oci-howto.md` and `cloud-howto.md`: point Terraform users at the new
path and note the `ubuntu` workaround is for the manual console path only.
Update `02-doc/current.md`.

Test: assert the docs mention `host_password_hash` and key-only SSH.

## TF11.4 — Live verification on a fresh OCI instance
**Status**: not done
**Description**: Manual test, run per the demo steps in the feature file. Needs
the open decision on the existing box first (rebuild it, or a second box). Record
command, setup, expected observation and actual result in `02-doc/notes.md`,
including anything unpredicted (for example the metadata key with no default
user).

No automated test: a real provisioning run.

## TF11.5 — F11 test suite and regression check
**Status**: not done
**Description**: Consolidate the checks above in
`tests/test_f11_terraform_host_user.sh`, using the `pass`/`fail` helpers of the
other suites. Confirm the whole suite (all `tests/test_f0*.sh`, F10, and this
one) passes before F11 is closed.
