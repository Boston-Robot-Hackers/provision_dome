# terraform/oci — OCI A1 bring-up (F07, TF07.9)

Declarative, tearable replacement for the manual OCI console bring-up. Stands
up a **bare** Ubuntu 24.04 arm64 box on `VM.Standard.A1.Flex`: VCN, public
subnet, internet gateway, an SSH-only security list, a 100 GB boot volume, and
a public IP with your SSH key.

It carries **no cloud-init and no swap** on purpose. TF07.0 validates F07's
baseline breakages by running the provisioning scripts by hand as `ubuntu`,
per `02-doc/oci-howto.md`. Wiring in F07's `user-data.template` is a later
task.

## Prerequisites

- A working `~/.oci/config` `[DEFAULT]` profile (validate with `oci iam
  region-subscription list`).
- Terraform installed.

## Use

```sh
cd terraform/oci
cp terraform.tfvars.example terraform.tfvars   # then set compartment_ocid
terraform init
terraform plan
terraform apply        # creates real (Always Free) resources
```

`apply` prints the public IP and instance OCID. Then:

```sh
ssh ubuntu@<instance_public_ip>
```

## A second box

The free arm allowance (4 OCPU / 24 GB) is shared across all A1 instances, so a
second full-size box is billed. Stand one up in its own state so the two never
collide:

```sh
terraform workspace new box2
terraform apply -var 'instance_name=dome-cloud-2'
```

## Stop / start (save money)

Terraform is for create/destroy; use the CLI for day-to-day power state:

```sh
oci compute instance action --instance-id <instance_ocid> --action SOFTSTOP
oci compute instance action --instance-id <instance_ocid> --action START
```

## Teardown

```sh
terraform destroy      # removes the instance, VCN, and all network resources
```

Also delete the host's `oci-dome` GitHub deploy key when you tear down (see
`02-doc/oci-howto.md`).
