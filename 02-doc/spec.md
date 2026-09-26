# Spec

## Goal

Reproducible ROS2 robot environment on Raspberry Pi, delivered via two build paths from one manifest. No custom code — pure shell scripts, manifest files, Docker, and standard tooling.

## Manifest as Single Source of Truth

All build configuration lives in `manifest/`. Scripts are thin executors. If adding a package, repo, or flag requires editing a script body rather than a manifest file, the abstraction is broken.

| File | Owns |
|---|---|
| `config.txt` | ROS_DISTRO, UBUNTU_CODENAME, DOME_USER default |
| `packages.txt` | apt and ROS packages (`[apt]`/`[ros]` sections) |
| `pip.txt` | pip3 packages |
| `repos.txt` | git repos to clone (`[root]`/`[ros_ws]`/`[uros_ws]` sections) |
| `apt-repos.txt` | third-party apt repos (GitHub CLI, VS Code) |
| `tools.txt` | curl-installed tools (mcfly) |
| `colcon.txt` | colcon build flags and package skip list |
| `rosdep.txt` | rosdep install skip keys |
| `dirs.txt` | home subdirectory structure |
| `bashrc` | shell environment sourced into `.bashrc` |
| `lib.sh` | shared manifest parsing helpers (sourced by all scripts) |

## Two Build Paths

```
manifest/
    |
    +---> Dockerfile.base + Dockerfile          (docker compose build, runs on Mac)
    |
    +---> scripts/bare-metal-base.sh + scripts/bare-metal-build.sh   (run as root on target)
```

Both paths produce identical ROS2 environments: same packages, repos, workspace layout, `.bashrc`, and user account. Divergence between paths is a defect.

## Target Platform

- Hardware: Raspberry Pi (arm64)
- OS: Ubuntu 24.04 (noble), fresh flash on microSD
- ROS2 distro: Kilted (configurable via `config.txt`)
- User account: `robot` (default, overridable via `user.txt`)

## User Override Mechanism

`manifest/user.txt` (gitignored) overrides `DOME_USER`, sets `DOCKERHUB_USERNAME` and `DOME_PASSWORD`. Load order: `config.txt` → `user.txt` → environment variable. Scripts fail fast with explicit error on missing required fields.

## Package Scope

- ROS2 base + configured distro packages
- Third-party apt repos (GitHub CLI, VS Code)
- Curl-installed tools (mcfly)
- pip3 packages
- Multiple git workspaces: root, ros_ws, uros_ws

## Constraints

- No custom programming — shell only
- All package/repo lists in manifest, never hardcoded in scripts
- `manifest/lib.sh` is the only shared logic; all scripts source it
- Tests (`tests/test_f01_manifest.sh`) validate manifest parsing and script behavior
