# Notes

Semi-permanent architecture decisions, research, calibration notes.

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
| `apt-repos.txt` | third-party apt repositories (Doppler, GitHub CLI, VS Code) |
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
