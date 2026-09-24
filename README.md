# provision_dome

Sets up a Dome robot from scratch.

Start with a blank microSD card and a Raspberry Pi; end with a Pi running
ROS 2 with all the Dome robot software installed, built, and ready to run.
You follow one guide start to finish and the scripts do the rest — there is
no code to write and nothing to configure by hand beyond your username.

You can also set up a virtual machine instead of a Pi, if you want to work
on the software without robot hardware in front of you.

---

## What you end up with

- **ROS 2 Kilted** on Ubuntu 24.04, installed and configured
- **The Dome robot packages** — navigation, vision, voice, control, mission
  — cloned and compiled into a ROS workspace at `~/ros2_ws`
- **Robot hardware configured** — camera, lidar, microphone array, and the
  USB device names the software expects
- **A shell that just works** — open a terminal and `ros2` commands are
  ready, with the workspace already sourced

Setup takes a while, mostly compiling. Times vary too much across hardware
and network speed to give a useful number.

---

## Which setup do I want?

| | Use this when |
|---|---|
| **Raspberry Pi** | You have a Pi and want a working robot. This is the normal choice. |
| **Virtual machine** | You want to develop without Pi hardware. No camera, lidar, or motors. |
| **Docker** | You want the robot to run from a prebuilt container image instead of a local install. Requires a Mac to build the image. |
| **Cloud VM** | You want a remote dev host reachable from anywhere. No hardware; visualize over SSH. |

Then follow that guide from top to bottom. Each one is self-contained — you
never need to jump between them.

- **Raspberry Pi** → [`02-doc/pi-howto.md`](02-doc/pi-howto.md)
- **Virtual machine** → [`02-doc/vm-howto.md`](02-doc/vm-howto.md)
- **Docker** → [`02-doc/docker-howto.md`](02-doc/docker-howto.md)
- **Cloud VM** → [`02-doc/cloud-howto.md`](02-doc/cloud-howto.md)

Undecided? [`02-doc/howto.md`](02-doc/howto.md) compares them side by side.

---

## What you need before you start

**For a Raspberry Pi setup:**

- Raspberry Pi 4 or 5
- microSD card, 16 GB or larger, and a card reader
- [Raspberry Pi Imager](https://www.raspberrypi.com/software/) on your
  computer
- A GitHub SSH key, for the private robot repositories

**For a VM setup:**

- Ubuntu **24.04 (noble)** specifically, already installed. Other Ubuntu
  releases fail partway through with confusing package errors.
- A GitHub SSH key

---

## Everyday use

Once you are set up, these are the things you will actually do.

**Get the latest robot code:**

```sh
cd ~/provision_dome
git pull
sudo scripts/bare-metal-build.sh
```

Open a new terminal afterward so the rebuilt workspace is picked up.

**Add a software package** — add its name to `manifest/packages.txt` (system
packages) or `manifest/pip.txt` (Python packages), then:

```sh
sudo scripts/bare-metal-base.sh
```

**Add a robot repository** — add it to `manifest/repos.txt`, then:

```sh
sudo scripts/bare-metal-build.sh
```

These three files are the ones you edit. You should not need to modify any
script.

---

## Optional extras

Two large downloads are left out of the default setup because most people do
not need them. Install either on demand:

```sh
install-optional-deps.sh torch     # ~1 GB   — machine learning for dome_vision
install-optional-deps.sh piper     # ~110 MB — speech output for dome_voice
install-optional-deps.sh           # both
```

Safe to re-run.

---

## If something goes wrong

Each guide ends with a Troubleshooting section covering the failures people
actually hit — network not ready, SSH key not found, build errors.

**Set up your Pi or VM before this repo was renamed?** It was previously
called `dome-docker`. Pulling the rename without renaming your local copy
breaks your shell. Both guides have a *Migrating* section with the fix.

---

## Keep your secrets out of git

Never commit `manifest/user.txt`, `.env` files, private keys, Wi-Fi
credentials, or netplan files containing passwords. `manifest/user.txt` is
already ignored by git — keep it that way.

Deleting a secret from the current files does **not** remove it from git
history. If something sensitive was ever committed, rewrite the history
before sharing the repository.

---

## Under the hood

You do not need any of this to use the robot, but if you are modifying how
setup works:

- [`02-doc/notes.md`](02-doc/notes.md) — design decisions and why things are
  built the way they are
- [`02-doc/manifest-format.md`](02-doc/manifest-format.md) — file formats for
  everything in `manifest/`
- [`02-doc/current.md`](02-doc/current.md) — what is in progress right now
- `tests/` — run `bash tests/test_f01_manifest.sh` to check the
  configuration files are intact

The short version: everything that varies — packages, repositories, build
flags, directory layout — lives in `manifest/`. The scripts read it and act
on it, and contain no such values themselves.
