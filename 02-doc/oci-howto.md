# OCI Howto: Oracle Cloud A1 Instance to Native ROS

**F07 targets OCI A1 (Ampere, arm64) as its cloud host.** This runbook sets
up that instance and provisions the dome stack on it. It is a working
assumption — if OCI doesn't work out (capacity, console, billing), see the
fallbacks in `02-doc/notes.md`, *Dev host options*, and we revisit.

**Running this is F07 TF07.0** — the manual bring-up that confirms F07's
predicted breakages on a real instance. Record anything that goes wrong in
`02-doc/notes.md`. These steps deliberately provision with today's manual
workarounds (`DOME_USER=ubuntu`, `DOME_TARGET=vm`, hand-added swap) rather
than F07's cloud-init flow, so TF07.0 exercises the baseline the F07 code
addresses. Once TF07.0 validates, this runbook adopts F07's cloud-init
template and `DOME_TARGET=cloud`, and folds into `02-doc/cloud-howto.md`.

**The trick that makes today's scripts work:** set `DOME_USER=ubuntu`.
That's the user Oracle already created, with your SSH key and passwordless
sudo, so none of the cloud login-user problems described in F07 arise.

Prices and provider trade-offs: `02-doc/notes.md`, *Dev host options*.

Researched 2026-09-22. Items marked ~ are not verified against Oracle's own
docs.

---

## Step 0: Decide Before Signing Up

- **Your home region is permanent.** It can't be changed after signup, and
  Always Free resources exist only there. From Boston, pick **US East
  (Ashburn)**: it has three availability domains, so more chances when A1
  capacity is short ~.

- **Size:** 4 OCPU / 16 GB, with a 100 GB boot disk.
  - Occasional use (~40 h/month) costs about $0 under either version of
    the free allowance.
  - Always-on is about $18/month.

---

## Step 1: Account

1. Sign up at oracle.com/cloud/free. A credit card is required for
   identity verification.

2. **Upgrade to pay-as-you-go:** Billing → *Upgrade and Manage Payment*.
   You keep the free allowance, avoid Always Free's idle-instance reclaim,
   and reportedly get better A1 capacity ~. Approval can take a while.

3. **Set a budget alert immediately:** Billing → *Budgets* → a $5 budget
   with an email alert at 100%.

### Signing in to the Console

Sign in at **cloud.oracle.com**. The login is a **two-step prompt**, not a
single email box:

1. First it asks for a **Cloud Account Name** — *not* an email. This is the
   name of your **tenancy**: Oracle's term for the whole cloud facility (the
   top-level account) you created at signup. **Mine is `pitosalas`.**

2. Then it asks for the **email and password** that belong to that tenancy,
   which is what actually logs you in.

So: **`pitosalas` (tenancy / cloud account name) → then email + password.**

### OCIDs

Nearly everything in Oracle Cloud is identified by an **OCID** — Oracle Cloud
Identifier, essentially a GUID. There isn't one OCID; there's a separate one
for every kind of resource: the tenancy, your user, each compartment,
instance, VCN, subnet, and so on. They look like
`ocid1.<type>.oc1..aaaa…`, where `<type>` names the resource
(`ocid1.tenancy…`, `ocid1.user…`, `ocid1.instance…`). When a step or a
`terraform.tfvars` asks for an OCID, check *which* resource's OCID it wants —
`compartment_ocid`, for instance, takes the **tenancy** OCID, not your user
OCID.

---

## Step 2: Mac Prep

Your existing public key, `~/.ssh/id_ed25519.pub`, is what you'll upload for
VM login. Only the public half leaves your Mac.

Optional — the OCI CLI, for stop/start from the terminal:

```sh
brew install oci-cli
oci setup config    # creates an API key; paste its public half into
                    # Console → your profile → API keys
```

---

## Step 3: Network

Console → **Networking → Virtual cloud networks → Start VCN Wizard →
"Create VCN with Internet Connectivity."** Accept the defaults.

The default security list allows only SSH (port 22) inbound. That's what
you want — everything else goes over SSH tunnels.

---

## Step 4: Create The Instance

Console → **Compute → Instances → Create instance:**

| Field | Value |
|---|---|
| Image | Canonical Ubuntu **24.04** (aarch64 is picked automatically for A1) |
| Shape | Ampere → **VM.Standard.A1.Flex**, 4 OCPU, 16 GB |
| Networking | the VCN from Step 3, public subnet, **assign a public IPv4 address** |
| SSH keys | paste `~/.ssh/id_ed25519.pub` |
| Boot volume | override size → **100 GB** |

**If you get "Out of host capacity":** try another availability domain in
the placement section, or retry later. It's a known, ongoing A1 problem;
some people run retry scripts for it.

---

## Step 5: First Login

The default user is **`ubuntu`**. Password login is already disabled; your
key is the only way in.

```sh
ssh ubuntu@<public-ip>
sudo apt update && sudo apt -y upgrade
```

**Pin the key.** If your Mac's `~/.ssh/config` has a broad `Host *` block
with its own `IdentityFile`, plain `ssh` can offer the wrong key and fail with
`Permission denied (publickey)`. Name the key explicitly:

```sh
ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes ubuntu@<public-ip>
```

Use the private key that matches the public key you gave the instance. The
same flags apply to the tunnel commands below.

**Add swap by hand.** Today the repo creates swap only when
`DOME_TARGET=pi`; F07 TF07.2 changes that.

```sh
sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

---

## Step 6: Provision Dome

Clone into `ubuntu`'s home — `manifest/bashrc` expects the repo at
`~/provision_dome`:

```sh
cd ~
git clone https://github.com/Boston-Robot-Hackers/provision_dome.git
cd provision_dome
printf 'DOME_USER=ubuntu\nDOME_TARGET=vm\nDOME_CLONE_OVERRIDE=PUBLIC_ONLY\n' > manifest/user.txt

sudo scripts/host-setup.sh        # finds 'ubuntu' already exists, skips user creation
sudo scripts/bare-metal-base.sh
sudo scripts/bare-metal-build.sh
```

**No GitHub key, no private repos.** `DOME_CLONE_OVERRIDE=PUBLIC_ONLY` tells
`bare-metal-build.sh` to skip every repo marked `PRIVATE_REPO` in
`manifest/repos.txt`, so the build needs no GitHub credential and this
internet-facing box never holds one. The only key on the instance is the
**public** login key Terraform installed; your private key stays on your Mac.

**What this excludes.** The dome robot packages are all private (`dome`,
`dome2`, `dome_control`, `dome_nav`, `dome_vision`, …), so a `PUBLIC_ONLY` box
gets a working ROS 2 environment with only the public dependencies — none of
the dome code itself.

**If you later want the private repos here anyway:** generate a *throwaway* key
on the VM (`ssh-keygen -t ed25519 -C oci-dome -f ~/.ssh/id_ed25519`), add its
public half at GitHub → SSH keys, drop the `DOME_CLONE_OVERRIDE` line from
`manifest/user.txt`, re-run `sudo scripts/bare-metal-build.sh`, and delete the
`oci-dome` key from GitHub at teardown. Never copy your personal key to this
box.

---

## Step 7: Smoke Test

`bare-metal-build.sh` installed `manifest/bashrc` as `~/.bashrc`. Open a
**new** SSH session and run:

```sh
echo "$ROS_DISTRO"                # kilted
ros2 pkg list | grep dome
```

---

## Step 8: Visualize With Foxglove

No ports opened — everything goes through an SSH tunnel. On the Mac:

```sh
ssh -L 8765:localhost:8765 ubuntu@<public-ip>
```

In that session, on the VM:

```sh
ros2 launch foxglove_bridge foxglove_bridge_launch.xml
```

Then connect the Foxglove app on the Mac to `ws://localhost:8765`.

---

## Step 9: Stop And Start To Save Money

- **Console:** Instance → **Stop** / **Start**.

- **CLI:**

  ```sh
  oci compute instance action --instance-id <ocid> --action SOFTSTOP
  oci compute instance action --instance-id <ocid> --action START
  ```

- **`sudo shutdown` inside the VM does *not* stop billing.** Always stop
  from the Console or CLI.

- **The IP survives stop/start.** Oracle's docs say the ephemeral public IP
  stays assigned while the instance is stopped; it's released only on
  terminate.

- **The disk is kept while stopped** and probably falls inside the free
  block-storage allowance ~.

---

## Troubleshooting

**"Out of host capacity" at create or start** — see Step 4. Capacity is the
most likely thing to block you.

**A port you opened is still unreachable** — Oracle's Ubuntu image ships
its own iptables rules (`/etc/iptables/rules.v4`, via
`netfilter-persistent`) that block everything except 22. You must allow the
port there *and* in the VCN security list. Not needed while everything goes
over SSH tunnels.

**Unexpected charges** — the free allowance is ambiguous. Oracle's docs say
1,500 OCPU-hours and 9,000 GB-hours a month for all tenancies. Support has
reportedly told pay-as-you-go customers they still get 3,000 / 18,000. Your
budget alert from Step 1 settles it in practice.

**New shells fail with `/opt/ros//setup.bash: No such file or directory`**
— the repo isn't at `~/provision_dome` for the `ubuntu` user. See Step 6.
