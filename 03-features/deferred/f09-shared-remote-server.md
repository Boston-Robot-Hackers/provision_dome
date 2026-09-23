# Feature description for feature F09

## F09 — Shared remote ROS 2 server with on-demand wake

**Priority**: Low
**Done:** no
**Tasks File Created:** no
**Tests Written:** no
**Test Passing:** no
**Description**: Deferred idea, recorded so it isn't lost. The user doubts
they'll pursue it.

A ROS 2 dev server for **one or two users**, reachable from the open
internet. It runs either in someone's closet (not at the robot's location)
or as a DigitalOcean droplet. Users SSH in with keys and get an Ubuntu
desktop from a URL.

## Shape discussed

- **Access:** key-based SSH; a browser desktop via KasmVNC. Both are exposed
  through **Cloudflare Tunnel**, so no router ports are opened and the URLs
  stay fixed, with **Cloudflare Access** (email OTP) in front for login.
  Never raw VNC or bare noVNC — VNC's standard auth truncates passwords to 8
  characters and sends everything unencrypted.

- **Multi-user:** per-user accounts, and a per-user `ROS_DOMAIN_ID` so
  users' nodes don't see each other.

- **On-demand wake (droplet variant):** a Cloudflare Worker page, behind
  Access, with a Start button. It creates the droplet from the latest
  snapshot and shows status.
  - A Worker cron checks for idleness. After ~30 idle minutes it powers
    off, snapshots, and destroys the droplet — **destroying only after the
    snapshot completes**, and keeping the previous snapshot.
  - The DigitalOcean token (scoped, with a billing alert) lives only in the
    Worker.
  - Cost: ~$0.07/hour awake plus ~$1.50/month for snapshots.

## Why deferred

- A lot of infrastructure outside this repo for one or two users.
- A closet box exposes its host's home network; it would need a separate
  VLAN or guest network.
- Not at the robot's location, so it still needs F08 to reach the robot's
  graph.
- Conflicts with F07's single-user, SSH-tunnel-only decisions. Adopting it
  would mean revising F07 first.

Pricing and trade-offs: `02-doc/notes.md`, *Dev host options*.
