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

## repos-&lt;set&gt;.txt — INI sections, one repo per line: `url dest [revision]`

Each **named repo set** gets its own file, and `REPOS_CONFIG` picks one (F17):
`REPOS_CONFIG=DOME` reads `manifest/repos-dome.txt`, `SAFE` reads
`manifest/repos-safe.txt`. The value is uppercase, the filename lowercase.

```
[root]
https://github.com/campusrover/rosutils.git rosutils 1e0fbebea7ced8c63ea1bb60031d06e42a3daedf

[ros_ws]
https://github.com/dfki-ric/better_launch.git better_launch devel

[uros_ws]
https://github.com/micro-ROS/micro-ROS-Agent.git micro-ROS-Agent
```

The optional third field is **one revision**: 40 hex characters is a commit
pin, anything else a branch. There is no credential marker — whether a set
needs a GitHub key is **derived** from whether it contains any `git@` or
`ssh://` url, and the build reports that when it resolves the set.

A section may be empty, which documents that the omission is deliberate;
`repos-safe.txt` leaves `[root-pi]` and `[uros_ws]` empty for that reason.

**Adding a set** needs no code change: drop in `manifest/repos-<name>.txt` and
set `REPOS_CONFIG=<NAME>`. `NONE` is reserved and means clone nothing, so
`manifest/repos-none.txt` must never be created.

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
