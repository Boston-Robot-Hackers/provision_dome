# Manifest File Format Reference

Quick reference for adding entries to `manifest/`. See `02-doc/notes.md` for architecture overview.

Shared parsing helpers are in `manifest/lib.sh` — sourced by Dockerfiles and bare-metal scripts.

---

## config.txt — flat key=value

```
ROS_DISTRO=kilted
UBUNTU_CODENAME=noble
DOME_USER=robot
```

User overrides go in `manifest/user.txt` (gitignored), same format. Load order: `config.txt` → `user.txt` → env var.

---

## packages.txt — INI sections, one package per line

```
[apt]
curl
git

[ros]
navigation2
slam-toolbox
```

ROS packages are prefixed automatically: `navigation2` → `ros-kilted-navigation2`.

---

## pip.txt — one package per line

```
depthai
roboflowoak
```

---

## repos.txt — INI sections, one repo per line: `url dest [branch] [PRIVATE_REPO]`

```
[root]
git@github.com:campusrover/rosutils.git rosutils

[ros_ws]
https://github.com/dfki-ric/better_launch.git better_launch devel

[uros_ws]
https://github.com/micro-ROS/micro-ROS-Agent.git micro-ROS-Agent
```

`PRIVATE_REPO` marks a repo that needs credentials (every `git@` line). It may
appear before or after the branch and is never treated as one. It has no effect
until `DOME_CLONE_OVERRIDE` is set (F10).

Sections: `root` → `$DOME_HOME`, `ros_ws` → `$DOME_HOME/ros2_ws/src`, `uros_ws` → `$DOME_HOME/uros_ws/src`.

---

## apt-repos.txt — INI sections, one repo per section

```
[repo-name]
key_url     = https://example.com/key.gpg
key_file    = /usr/share/keyrings/example-keyring.gpg
key_dearmor = yes | no
list        = deb [arch={arch} signed-by={key_file}] https://example.com/apt stable main
packages    = package-name another-package
```

- `key_dearmor = yes` — key is ASCII-armored, pipe through `gpg --dearmor`
- `key_dearmor = no` — key is already binary GPG format, download directly
- `{arch}` expands to `$(dpkg --print-architecture)`
- `{key_file}` expands to the `key_file` value

---

## tools.txt — INI sections, curl-installed tools

```
[tool-name]
method = curl-sh
url    = https://example.com/install.sh
args   = --flag value
```

Only `method = curl-sh` supported: `curl -LSfs <url> | sh -s -- <args>`.

---

## colcon.txt — flat key=value

```
packages_skip = depthai_rospi pkg2
```

Multiple skip packages are space-separated. `flags` is optional extra
`colcon build` arguments; unset by default (full, non-symlink install).

---

## rosdep.txt — flat key=value

```
skip_keys = ament_python gazebo_ros_pkgs
```

Space-separated. Passed directly to `rosdep install --skip-keys`.

---

## dirs.txt — one path per line, relative to `$DOME_HOME`

```
.local/bin
.ros/camera_info
ros2_ws/src
```

Created with `mkdir -p` on both Docker and bare-metal builds.
