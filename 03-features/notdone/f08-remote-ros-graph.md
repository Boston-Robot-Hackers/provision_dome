# Feature description for feature F08

## F08 — Join a remote host to the robot's ROS graph over Tailscale

**Priority**: Low
**Done:** no
**Tasks File Created:** no
**Tests Written:** no
**Test Passing:** no
**Description**: Let a remote development host — the F07 cloud box, or the
F06 Mac container — see and publish to the live robot's ROS 2 graph across
a Tailscale link.

Split out of F07. F06 already called this "a separate feature, not a
variation" of its own scenario, and the same is true for F07: unlike the
rest of F07, it **cannot be done without changing the robot**.

## Why this is harder than it looks

- **Tailscale carries no multicast.** It is a layer-3 mesh, so default DDS
  discovery (SPDP multicast) silently finds nothing even though `ping`
  works. Discovery must be unicast.

- **Unicast discovery must be configured on both ends.** A FastDDS
  discovery server only works if the robot's nodes are configured as its
  clients. `ROS_STATIC_PEERS` must list the peer on each side. Either way,
  the robot's environment changes, and `manifest/bashrc` is shared by the
  robot and every other native target.

- **The RMW in use is not pinned on the native path.** Only
  `compose/compose.yaml:24` sets `RMW_IMPLEMENTATION` (defaulting to
  `rmw_fastrtps_cpp`). The native path sets nothing in this repo;
  `~/rosutils/ros2_robot_bashrc.bash`, which lives in a separate repo, may.
  `ROS_DISCOVERY_SERVER` is FastDDS-specific, so the mechanism can't be
  chosen until the RMW is known.

- **The robot must run Tailscale.** That's a new service on the Pi,
  installed and authenticated by hand, with its own auth-key handling.

## Open questions — to resolve before tasks are written

1. **Which RMW does the robot actually run?** Check `rosutils`.
2. **Discovery mechanism.** Two options:
   - `ROS_STATIC_PEERS` with `ROS_AUTOMATIC_DISCOVERY_RANGE`, which ROS 2
     supports across RMWs since Iron. Simpler, symmetric, no extra process.
   - A FastDDS discovery server, which scales better but adds a process to
     run and is FastDDS-only.
3. **Opt-in on the robot.** How does a Pi opt in without affecting robots
   that never join a remote host? Likely a `manifest/user.txt` key read by
   `manifest/bashrc`, unset by default.
4. **`ROS_DOMAIN_ID` policy.** Several robots or developers on one tailnet
   need distinct domains or they cross-talk.
5. **Command authority.** A remote host can publish `/cmd_vel` to a
   physical robot. Decide whether that is acceptable, gated, or forbidden
   before enabling it. This is the reason F07 stayed single-user.

## Known limitations

- **Tailscale MTU is 1280.** RTPS fragments large messages; camera and
  point-cloud topics will be poor across the link.
  `compressed-image-transport` is already installed and helps.
- **Latency.** A cloud host's round trip to a home robot is tens of
  milliseconds at best. Fine for monitoring; not for tight control loops.

## How to Demo

**Setup**: A provisioned F07 cloud host and a provisioned robot, both on
the same tailnet, both configured per the mechanism chosen above.

**Steps**:

1. On the robot: `ros2 run demo_nodes_cpp talker`.
2. On the cloud host: `ros2 topic echo /chatter` → messages arrive.
3. On the cloud host: `ros2 node list` → the robot's nodes are listed.
4. Control: disable the opt-in on the robot, restart the talker → the cloud
   host sees nothing.

**Expected output**: bidirectional discovery across Tailscale only when
explicitly enabled on both ends; no change to a robot that has not opted in.
