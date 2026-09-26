# Notes

Semi-permanent architecture decisions, research, calibration notes.

## Vocabulary: the machines, and the one thing that isn't one (2026-09-26)

Agreed names, so that features and reviews mean the same thing by them. Four
**hosts**, plus one **artifact** that is repeatedly mistaken for a host.

### The four hosts

**The box** — the rented OCI A1 instance, `dome-cloud-1`. Scenario 4,
`DOME_TARGET=cloud`, `cloud-howto.md`. Public IP, no robot hardware, created
and destroyed by Terraform. **Expendable by design** — losing it should cost
nothing but itself.

**The robot** — the physical Dome: a Pi 4/5 with camera, lidar, ESP32 and
GPIO. Scenario 1, `DOME_TARGET=pi` (the default), `DOME_MODE=native`,
`pi-howto.md`. *"The Pi" means this tool installing all the bits **directly
onto the Pi*** — a native bare-metal install, not a container. Lives on the
LAN (`192.168.4.100`), no public address. **Not expendable.**

**The Mac** — the workstation. Not a `DOME_TARGET` and not part of the running
system: it is the setup console (Terraform, the `oci` CLI, SSH) and the build
host for the Docker image. See *Why the Mac outranks the rest* below.

**The VM** — a local Ubuntu 24.04 guest under VMware or Parallels. Scenario 2,
`DOME_TARGET=vm`, `vm-howto.md`. The same native install as the Pi with the
Pi-hardware steps skipped; for development without Pi hardware. Expendable.

### Not a host — `dome-docker`

`dome-docker:dome-kilted` (`compose/compose.yaml:14`) is a **reusable
container image**, Scenario 3, `DOME_MODE=docker`. It is built on the Mac with
buildx (cross-compiled to arm64), pushed to a registry, then pulled and run on
the Pi.

It is **an artifact that runs on a host, not a host**. It has no credentials,
no network position and no identity of its own until something runs it, so it
never belongs in a list of machines — a recurring category error worth naming.

**It is the least debugged part of the project.** Treat its behavior as
unverified unless it has just been exercised. F06 would run the same image on
the Mac, which is what "reusable" is for.

### Why the distinction matters

Hosts carry credentials and occupy network positions; the image carries
neither. Any blast-radius question is therefore asked of the hosts, and of the
`manifest/` all of them share — not of the image.

**Why the Mac outranks the rest.** It is the only machine holding private key
material: `~/.ssh/id_ed25519` — simultaneously the GitHub key, the robot key
and the box key — plus `terraform.tfstate` and the OCI CLI credentials. It is
"not part of the operation" and still the highest-value target of the four.
This inverts the intuition that the internet-facing box is the risky one.

**Known collision.** The live box is configured `DOME_TARGET=vm`, not `cloud`,
so today *the box* and *the VM* share a target value. Reconcile under F11.

## manifest/ as single source of truth (2026-05-18)

All build configuration lives in `manifest/`. Scripts are thin executors — no package names,
repo URLs, build flags, or directory lists in script bodies. If adding something requires
editing a script rather than a manifest file, the abstraction is broken.

**Manifest files and what they own:**

| File | Owns |
|---|---|
| `config.txt` | ROS_DISTRO, UBUNTU_CODENAME, DOME_USER default |
| `packages.txt` | apt and ROS packages ([apt]/[ros] sections) |
| `pip.txt` | pip3 packages |
| `repos.txt` | git repos to clone ([root]/[ros_ws]/[uros_ws] sections) |
| `apt-repos.txt` | third-party apt repositories (GitHub CLI, VS Code) |
| `tools.txt` | curl-installed tools (mcfly) |
| `colcon.txt` | colcon build flags and skip list |
| `rosdep.txt` | rosdep install skip keys |
| `dirs.txt` | home subdirectory structure |

**Two build paths, same manifest:**

```
manifest/
    |
    +---> Dockerfile.base + Dockerfile      (docker compose build on Mac)
    |
    +---> scripts/bare-metal-base.sh + scripts/bare-metal-build.sh  (run as root on target)
```

**User overrides:** `manifest/user.txt` (gitignored) overrides `DOME_USER` and sets
`DOCKERHUB_USERNAME` and `DOME_PASSWORD`. `config.txt` holds project defaults;
`user.txt` holds per-user values. Load order: config.txt → user.txt → env var.

**Shared helpers:** `manifest/lib.sh` — source this in any script that needs to parse
manifest files. Provides `manifest_field`, `manifest_require`, `manifest_sections`,
`manifest_config`. All fail fast with explicit ERROR messages on missing required fields.

**Design doc:** `02-doc/manifest-as-ground-truth.md`

## Dev host options: cloud vs a box under the desk (2026-09-22, revised)

Supports F07. Researched on 2026-09-22; prices move, so re-check before
buying.

**Confidence markers:** ✓ = checked against the provider's own docs or a
retailer listing. ~ = from a secondary source, a search summary, or
general knowledge; treat as unverified.

### Assumptions

- **Two usage profiles.** *Occasional*: about 40 hours a month.
  *Always-on*: about 730 hours. The first revision priced only always-on,
  which is the wrong default for a dev box.

- **Baseline size: 4 cores, 8–16 GB.** The largest Pi 5 is 4 cores / 16 GB,
  so 8 cores is not "Pi parity." F07 T01 should measure a real build and
  adjust.

### Architecture

- **Default to arm64.** It matches the Pi *and* the Apple Silicon Mac, so
  builds and any prebuilt binaries behave the same on all three machines.

- **x86_64 is allowed but untested.** The apt setup resolves architecture
  with `dpkg --print-architecture`, but nobody has checked that every
  `[ros]` package exists for amd64 or looked through the ~20 workspace repos
  for arm-only code. `piper` isn't committed in `dome_control`; it's
  installed by `install-optional-deps.sh`, whose per-architecture handling
  is unverified. Run F07 T01 on x86 before relying on it.

- **F06 is different:** it runs the robot's arm64 Docker image, so arm64 is
  mandatory there.

### What "off" costs

This decides the occasional-use price more than the hourly rate does.

- **DigitalOcean.** A powered-off droplet is **still billed in full** ✓.
  - To stop paying, snapshot it ($0.06/GB-month ✓) and destroy it. Restore
    by creating a new droplet from the snapshot, which takes minutes.
  - The restored droplet gets a new IP unless you keep a reserved IP. A
    reserved IP is free while assigned but $5/month while unassigned ✓ —
    which, with destroy-between-sessions, is most of the month.
  - All of this is scriptable with `doctl`; no dashboard needed.

- **Oracle (OCI).** Stopping an instance via the console, CLI, or API
  **pauses compute billing** for standard shapes ✓. The A1 flex shape isn't
  named explicitly in that doc ~.
  - Shutting down from inside the OS (`sudo shutdown`) does **not** stop
    billing ✓. You must use the CLI or console.
  - The boot volume keeps billing while stopped, probably inside the free
    block-storage allowance ~. Whether the public IP survives stop/start is
    unverified ~.
  - One command each way; no snapshot, no new machine.

- **Hetzner.** Powered-off servers are still billed ~, so it's the same
  snapshot-and-delete routine as DigitalOcean.

- **A box under the desk.** Power switch. Electricity only.

### Monthly cost, 4-core class

| Option | ~40 h/mo | Always-on | One-time |
|---|---|---|---|
| DigitalOcean basic 4 vCPU / 8 GB | ~$4 (+$5 if reserved IP kept) | $48 ~ | — |
| OCI A1 4 OCPU / 16 GB, pay-as-you-go | **$0** | ~$18 (or $0) | — |
| Hetzner CPX31, US | not priced | $60+ ~ | — |
| Refurb mini PC (Lenovo M920q) | ~$0.25 power | ~$2.20 power | ~$305 ✓ |
| Spare Pi 5, 16 GB | ~$0.05 power | ~$1 power | ~$305 ~ |
| Your Mac, VM (Scenario 2) | $0 | not always-on | $0 |

How the figures were derived:

- **DigitalOcean:** $48/month plan ≈ $0.066/hour × 40 h ≈ $2.60, plus a
  ~25 GB snapshot at $0.06/GB ≈ $1.50. The $48 figure came via a summarized
  pricing page — confirm it on the pricing page.

- **OCI:** $0.01/OCPU-hour + $0.0015/GB-hour ~ (Oracle's pricing page
  returned 403; rates came from search results).
  - The Ampere allowance was **halved on 2026-06-15** to 1,500 OCPU-hours
    and 9,000 GB-hours per month, and Oracle's docs say this applies to
    *all* tenancies ✓
    ([InfoQ](https://www.infoq.com/news/2026/07/oracle-cloud-free-tier-limits/)).
    Support staff have reportedly told pay-as-you-go customers they still
    get the old 3,000 / 18,000; unresolved.
  - Occasional: 160 OCPU-hours and 640 GB-hours — well inside either
    allowance, so **$0**.
  - Always-on: (2,920 − 1,500) × $0.01 + (11,680 − 9,000) × $0.0015 ≈
    **$18**. Under the old allowance it's $0.
  - **Correction:** the first revision's "$28.40 for 8 OCPU / 16 GB" used
    the old allowance. Under the documented one it's about $47.
  - The free tier reclaims idle *Always Free* instances. Whether that
    applies to instances in an upgraded pay-as-you-go account is unverified
    ~.

- **Hetzner:** US locations sell only the x86 CPX/CCX lines; arm64 (CAX) is
  EU-only ✓. The only US price found was CPX21 (3 vCPU / 4 GB) at $37.49 ✓
  after a June 2026 price rise, so a 4-vCPU CPX31 is likely $60+ ~.

- **Mini PC:** a refurbished Lenovo ThinkCentre M920q (i5-8500T, 6 cores,
  16 GB, 512 GB NVMe) is $305 in one Newegg listing ✓
  ([listing](https://www.newegg.com/lenovo-thinkcentre-m920q-business-desktops-workstations/p/1VK-0003-1GHM2)).
  The used market may be lower ~.
  - Power: roughly 10 W idle ~, at Massachusetts rates of 30–33¢/kWh ✓
    → about $2.20/month always-on.

- **Pi 5 16 GB:** $120 at launch, raised repeatedly by DRAM shortages to
  about $305 by April 2026 ~
  ([Raspberry Pi news](https://www.raspberrypi.com/news/more-memory-driven-price-rises/)).
  Smaller-RAM models cost less.

### What a desk box changes

A box on the robot's home network changes more than the cost.

- **It's Scenario 2, not a cloud host.** Install Ubuntu 24.04 directly and
  follow `vm-howto.md`. You create the user yourself at install, so there's
  no cloud-init step and no wrong-login-user problem.

- **It joins the robot's ROS graph natively at home.** Same LAN, so plain
  multicast discovery works. **Most of F08 becomes unnecessary** when you're
  home.

- **Remote access from away** needs Tailscale on the box (free personal
  plan ~). It's used only for SSH, so the no-multicast limitation doesn't
  matter.

- **It has real graphics.** The M920q's integrated GPU gives `rviz2`
  hardware GL instead of software rendering.

- **Costs:** you own hardware, and home power or internet outages take it
  offline. A mini PC is x86; a Pi gives exact robot parity but the slowest
  builds.

### Ruled out

- **AWS** — user preference; too complex for a small dev box.

- **fly.io** — Fly Machines are Firecracker VMs booted from a container
  image, not blank VMs to provision, so they don't fit the
  bare-metal-scripts flow. The free allowance ended in 2024 ~. x86_64-only
  ✓ ([thread](https://community.fly.io/t/are-arm64-fly-machines-available/5902)).

- **Oracle Always Free `E2.1.Micro`** — 1/8 OCPU and 1 GB RAM; far too
  small for a workspace build. A1 pay-as-you-go, stopped between sessions,
  is the better "free."

- **Vultr, Linode, Lightsail** — not priced. DigitalOcean already covers
  "familiar, simple, flat-priced."

### Summary

- **Occasional use, no hardware:** OCI A1 pay-as-you-go, stopped between
  sessions — likely $0 and arm64. The price is OCI's AWS-like console,
  "out of capacity" errors for A1 in popular regions ~, and the unresolved
  allowance question.

- **Simplest cloud to operate:** DigitalOcean 4/8. Either leave it running
  for $48/month, or snapshot and destroy with scripted `up`/`down` for a
  few dollars.

- **Robot developer at home:** a desk box on the robot's network. About
  $300 once, ~$2/month power, no start/stop routine, joins the robot's
  graph without F08, with Tailscale for access from away. Cheaper than
  DigitalOcean always-on within about six months.

## TF07.0 — OCI A1 bring-up log (started 2026-09-23)

Live log of the manual OCI A1 (arm64) bring-up, following `oci-howto.md`.
Purpose: confirm F07's four predicted breakages and capture friction so the
docs describe the real experience. Filled in step by step as it happens.

### The four predicted breakages — verdict

| # | Predicted problem | Occurred? | Workaround needed |
|---|---|---|---|
| 1 | Login user is `root`/`ubuntu`, not `DOME_USER` | Yes — login is `ubuntu` | `DOME_USER=ubuntu` sufficed. Plus a **client-side** snag: a Mac `~/.ssh/config` `Host *` `IdentityFile` masked the instance key; `ssh -i … -o IdentitiesOnly=yes` fixed it. |
| 2 | Repo cloned in wrong home → empty `ROS_DISTRO` | **Yes, transiently — `ROS_DISTRO` was unset in a new shell after the build** | Resolved: a fresh shell later printed `kilted` and `ros2 pkg list` works. *Not* the predicted cause (repo was in the right home). The root cause was not diagnosed; likely the earlier runs failed before `bare-metal-build.sh` installed `bashrc`, and the final successful run installed it (unverified). |
| 3 | New user unreachable (no `authorized_keys`) | No | Reused the pre-existing `ubuntu` (Terraform installed the key), so no new user was created. |
| 4 | No swap on the cloud shape | Yes — bare box has none | Add `/swapfile` by hand (F07 TF07.2 automates this for `DOME_TARGET=cloud`). Build succeeded anyway — 24 GB RAM is ample. |

Note: `oci-howto.md` sidesteps #1–#3 with `DOME_USER=ubuntu` and adds swap
by hand for #4, so on OCI we record whether those workarounds sufficed — they
did. New finding this run: a **host-specific GitHub key is load-bearing** —
`bare-metal-build.sh` clones private repos as `DOME_USER` (`sudo -u`), so the
key must live in that user's `~/.ssh`. Deleting it (during the "don't copy your
personal key" cleanup) left the box with only `authorized_keys`, and the build
died at the first clone (`campusrover/rosutils`, `Permission denied
(publickey)`). Fix: generate a host key named `~/.ssh/id_ed25519` on the VM
(default name → auto-offered, no ssh config needed) and add it to GitHub as
`oci-dome`; verified with both `ssh -T` and `sudo -u ubuntu ssh -T`. **Doc
fix:** `oci-howto.md`/`cloud-howto.md` should stress the key must be the
*DOME_USER's* key and use the default filename, and warn that removing it
breaks the build at the first private clone.

### RESOLVED — `ROS_DISTRO` unset in a new shell after a full build (2026-09-24)

**Closed 2026-09-24:** smoke test on `dome-cloud-1` in a fresh shell —
`echo "$ROS_DISTRO"` → `kilted`; `ros2 pkg list | grep dome` lists all 11
`dome*` packages (incl. `dome_telemetry`); `swapon --show` lists `/swapfile`
(4G). Cause of the earlier empty value was not pinned down (see table, #2).
The original diagnosis notes are kept below.

After `bare-metal-build.sh` completed, **a new login shell still has
`ROS_DISTRO` undefined** on `dome-cloud-1`. This is breakage #2, but the
predicted cause does **not** apply here:

- The repo *is* at `~/provision_dome` (ubuntu's home), which matches the
  hardcoded path in `manifest/bashrc:1`.
- `manifest/config.txt:2` has an uncommented `ROS_DISTRO=kilted`, exactly what
  `bashrc:1` greps: `export ROS_DISTRO=$(grep '^ROS_DISTRO=' ~/provision_dome/manifest/config.txt | cut -d= -f2)`.
- The build itself resolved `ROS_DISTRO=kilted` fine (script line 34).

So the grep *should* return `kilted` at shell startup. Something else is
breaking the chain. **Diagnostics to run next session (on the box):**

- `head -2 ~/.bashrc` — is it actually `manifest/bashrc` (did the build's
  install step at `bare-metal-build.sh:122-124` run)? If the earlier
  clone-failed run left the build incomplete and the good run also errored
  before line 122 (e.g. a `colcon build` failure under `set -e`), the bashrc
  was never installed.
- `grep -n bashrc ~/.profile` — does the login shell still source `~/.bashrc`?
  (Ubuntu's default `~/.profile` does; confirm the build didn't replace
  `~/.profile`.)
- Run bashrc line 1 by hand: `grep '^ROS_DISTRO=' ~/provision_dome/manifest/config.txt | cut -d= -f2` — does it print `kilted`?
- `bash -lc 'echo "[$ROS_DISTRO]"'` vs an interactive shell — rule out
  non-interactive shells (which don't source `.bashrc`).
- Check whether `source ~/rosutils/ros2_robot_bashrc.bash` (bashrc:2) errors
  and aborts the rest of `.bashrc` — though line 1 sets `ROS_DISTRO` *before*
  it, so this shouldn't zero it out.

Most likely: the bashrc was never installed because the build didn't reach its
tail (a `colcon` failure), i.e. "done" may have meant "stopped," not
"succeeded." Confirm the build's exit status and the `colcon build` summary
line next session before closing TF07.0.

### Step-by-step log

- **Step 1 (Account), 2026-09-23** — Signed up at oracle.com/cloud/free,
  **completed ~9:25**. Attempted the pay-as-you-go upgrade immediately and
  **could not**: the console reports the upgrade is unavailable because
  **tenancy provisioning is still in progress**. Waiting for provisioning to
  complete before retrying.
  - **The console becomes usable long before the billing upgrade unblocks.**
    Compute → Instances → Create instance was fully functional within the
    first hour, but the **pay-as-you-go upgrade still reported "account
    provisioning is in progress"** even after ~45+ min (checked ~22:10).
    So "console works" ≠ "account provisioned for billing" — they clear on
    different timelines. Proceeded on the **Always Free** tier; the upgrade
    is *not* a prerequisite to start and can be retried later (likely
    signalled by an email). *(Approx times; signup ~21:25.)*
  - **The "account is ready" email is the real signal** that the billing
    upgrade has unblocked — it arrived and the pay-as-you-go upgrade then
    worked. Full provisioning (to upgrade-ready) took ~<duration pending>
    from signup ~21:25. Doc fix: tell users to wait for that email before
    trying to upgrade, and to just start the instance on Always Free
    meanwhile.
  - **The upgrade itself is also asynchronous** — after submitting the
    pay-as-you-go upgrade there is a further processing delay before it
    completes. It does not block instance creation (Always Free A1 runs
    regardless), so don't wait on it. Total OCI onboarding involves *three*
    separate waits: tenancy provisioning → billing-upgrade-ready (email) →
    upgrade processing.

### Headline finding — the OCI console is the real obstacle

The manual OCI console bring-up is **error-prone and circular**, not because
of our scripts but because of the console itself: wrong defaults hidden
behind Edit buttons (Oracle Linux, 1 OCPU, no public IP, no SSH key),
spurious "incompatible settings" warnings on a valid image/shape, a
public-IP step that has to be redone after creation, and three separate
onboarding waits. A first-time operator loops for a long time before a box
even exists.

**Conclusion:** F07's "simplify provisioning" goal is not served by
documenting this click-path in `oci-howto.md`. It should be **scripted** —
OCI CLI (`oci compute instance launch ...`) or, better, **Terraform** (OCI
provider) for a declarative, reproducible, tearable bring-up. This matches
the "scripted up/down" the F07 spec already anticipated. Likely a new F07
task (or a follow-on feature): a `terraform/` config or an `oci-up.sh` that
creates VCN+subnet+instance with the right image/shape/public-IP/SSH-key in
one command. Cost: a one-time OCI API-key setup (`oci setup config`).

### API credentials (for the Terraform pivot)

- oci-cli was installed and `oci setup config` run, but it produced a
  **malformed `~/.oci/config`**: a duplicate `[DEFAULT]` section whose header
  was written as `DEFAULT]` (missing the leading `[`), which made oci-cli
  crash on every call. Fixed by keeping only the first, complete section
  (backup at `~/.oci/config.bak`). After that, `oci iam
  availability-domain list` returned the three Ashburn ADs — auth confirmed.
  Region `us-ashburn-1`. **Doc fix:** warn that the setup can emit a broken
  config and to validate with a real API call before trusting it.

### Unpredicted friction

- **A1 capacity was available in all three Ashburn ADs** at create time
  (2026-09-23 ~21:53) — the console banner said so explicitly. The dreaded
  "Out of host capacity" did not occur on this run.

- **Console defaults are wrong for us, and the way to change them is hidden.**
  The create-instance form defaults to **Oracle Linux 9** and the tiny x86
  **VM.Standard.E2.1.Micro** shape. Both must be changed (Ubuntu 24.04 +
  Ampere A1.Flex), but the image/shape choices are only reachable by
  clicking an **Edit** button on the "Image and shape" block — not obvious,
  and easy to click Create with the wrong OS. **Doc fix:** oci-howto Step 4
  should say "click Edit on Image and shape, then change Image to Canonical
  Ubuntu 24.04 and Shape to VM.Standard.A1.Flex" explicitly.

- **Only "Minimal" Ubuntu images exist for aarch64 in this region.** The
  aarch64 24.04 options offered were all **Minimal** (22.04 / 24.04 / 26.04
  Minimal aarch64); no standard aarch64 24.04 image was listed. Chose
  **Canonical Ubuntu 24.04 Minimal aarch64**. Minimal still has cloud-init,
  apt, systemd, and SSH, and `host-setup.sh` installs its own deps, so this
  should be fine — but if `bare-metal-base.sh` fails on a base package a full
  image would have had, Minimal is the suspect. **Doc fix:** oci-howto should
  say to pick "Canonical Ubuntu 24.04 ... aarch64" (Minimal is expected on A1)
  and must NOT pick 26.04 (wrong codename vs. noble).

  - **Update (2026-09-24): a full, non-Minimal `Canonical-Ubuntu-24.04-aarch64`
    image now exists** in Ashburn (`...-2026.09.18-0`, `operating_system_version
    = "24.04"`), alongside the Minimal ones (`24.04 Minimal aarch64`). The
    Terraform config selects the full image, so the Minimal-only worry above is
    moot on the Terraform path. The console "Minimal only" observation may have
    been a console-listing artifact or has since changed.

### Terraform pivot landed (2026-09-24)

The scripted bring-up the headline finding called for is now in
`terraform/oci/` (task **TF07.9**, done). It stands up a **bare** box — VCN,
public subnet, internet gateway, an **SSH-only** security list, a
`VM.Standard.A1.Flex` at **4 OCPU / 24 GB** (the full Always-Free arm
allowance), a 100 GB boot volume, and a public IP with `~/.ssh/id_ed25519.pub`.

- **No cloud-init, no swap on purpose** — TF07.0 still validates the four
  baseline breakages by running the scripts by hand as `ubuntu`, per
  `oci-howto.md`. Terraform only removes the console from the create step.
- **Validated without spending an apply:** `terraform fmt -check`,
  `terraform validate`, and `terraform plan` all pass. Plan = *6 to add*;
  the image data source resolves to `Canonical-Ubuntu-24.04-aarch64-2026.09.18-0`;
  auth via the working `~/.oci/config` succeeds.
- **The half-built console instance** (`instance-20260923-2216`) is already
  **TERMINATED** — no cleanup needed.
- **Second box:** the free arm allowance is shared across all A1 instances, so
  a second full-size box is billed. Decision: keep box #1 at the full 24 GB and
  pay for #2 (≈$0 if stopped between sessions). `terraform workspace` +
  `-var instance_name=...` stands up a non-colliding second box.
- **`terraform apply` succeeded (2026-09-24)** — 6 resources in ~50s, instance
  `RUNNING`, ephemeral public IP assigned. Auth/image/shape all as planned. The
  scripted path is dramatically less error-prone than the console.

- **SSH friction — client-side key selection, not the box (doc fix).** First
  `ssh ubuntu@<ip>` gave `Permission denied (publickey)` even though the
  instance had the right key (installed-key fingerprint matched
  `~/.ssh/id_ed25519.pub` exactly). Cause: a local `~/.ssh/config` `Host *`
  block forcing a different `IdentityFile`, plus an agent holding only an
  unrelated RSA key, so `id_ed25519` was never reliably offered. Fix that
  worked: `ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes ubuntu@<ip>`.
  **Doc fix:** `oci-howto.md` / `cloud-howto.md` should give the explicit
  `-i ... -o IdentitiesOnly=yes` form (or a `~/.ssh/config` host block) so a
  broad `Host *` identity setting doesn't mask the instance key. Confirms
  breakage **#1** (login user is `ubuntu`, key-only) — the workaround sufficed
  once the right key was offered.

- **Default user is `ubuntu`** on the Canonical Ubuntu image (not `opc`, which
  is Oracle Linux only; root login disabled).

- **Next:** finish TF07.0's baseline run on the box (swap by hand, clone,
  `host-setup.sh` + `bare-metal-base.sh` + host GitHub key +
  `bare-metal-build.sh` + smoke test) and fill in the breakage table.

- **Follow-up wanted (user request, 2026-09-24): make the login username a
  parameter.** Today the Terraform config uses the image's fixed default user
  (`ubuntu`); the desired end state is a `host_user` variable so the operator
  chooses the login name. On OCI the username is baked into the image, so a
  custom name means wiring cloud-init into the Terraform config to create that
  user with the SSH key — i.e. folding F07's `host-file-templates/cloud/
  user-data.template` (`DOME_USER`) into `terraform/oci/`. This is the "wire
  the F07 cloud-init flow into Terraform" task already anticipated; capture it
  as a task (TF07.10) when we move past the TF07.0 baseline.

- **Pay-as-you-go upgrade is blocked during initial provisioning.**
  `oci-howto.md` Step 1 presents the upgrade as an immediate action
  ("Billing → *Upgrade and Manage Payment*"), but a brand-new tenancy is
  still provisioning right after signup and the console refuses the upgrade
  until that finishes. **Doc fix:** Step 1 should say to wait for tenancy
  provisioning to complete before attempting the upgrade, and note the
  option can be hard to locate (label/path varies: Billing & Cost
  Management → "Upgrade and Manage Payment" / "Payment Method", a top-banner
  "Upgrade" button, or the profile menu).
