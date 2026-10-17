# Dome Cookbook: Concepts

Read this once. The four recipes assume it and do not repeat it.

- **[A Raspberry Pi](cookbook-pi.md)** — a real robot.
- **[A virtual machine](cookbook-vm.md)** — development, no hardware.
- **[A container on a Pi](cookbook-container.md)** — built elsewhere, run on the Pi.
- **[A rented cloud machine](cookbook-cloud.md)** — a dev host reachable from anywhere.

---

## What this tool does

You supply a machine with nothing on it but Ubuntu. This tool turns it into a
working ROS 2 workspace: ROS installed, the robot's repositories cloned,
everything compiled, and a shell where `ros2` commands just work.

You do not write any code and you do not configure anything by hand beyond
your username. You run three scripts in order and open a new terminal.

Setup takes a while, mostly compiling. How long varies enough across machines
and networks that any number here would mislead you.

---

## Which one do I want?

|  | Pick this when |
|---|---|
| **A Raspberry Pi** | You have a Pi and want a working robot. The normal choice. |
| **A virtual machine** | You want to work on the software with no hardware in front of you. |
| **A container on a Pi** | You want the Pi to run a prebuilt image instead of compiling locally. Needs a Mac to build it. |
| **A rented cloud machine** | You want a dev host reachable from anywhere. No hardware. |

The first, second and fourth are the **same three scripts**, differing in one
setting. The third is different in kind: the compiling happens somewhere else
and the Pi runs the result.

---

## The manifest is the source of truth

Everything installable lives in `manifest/`. The scripts contain no package
names and no repository URLs — they read those lists and execute them.

| File | Holds |
|---|---|
| `config.txt` | Project defaults: ROS version, Ubuntu version, settings |
| `user.txt` | **Your** local overrides. Not in git. You create it. |
| `packages.txt` | System and ROS packages |
| `pip.txt` | Python packages |
| `repos-dome.txt` | The full robot's repositories |
| `repos-safe.txt` | A minimal set: shell tools and a launch library |
| `apt-repos.txt` | Third-party software sources |
| `tools.txt` | Tools installed by download rather than by package |
| `colcon.txt` | Compiler flags, and packages to skip |
| `rosdep.txt` | Dependencies to skip resolving |
| `dirs.txt` | Which folders to create in your home directory |
| `bashrc` | The shell setup that becomes your `~/.bashrc` |

This is why "add a package" and "add a repository" later mean *edit a list and
re-run a script*, never *edit a script*.

Exact file syntax, if you need it: [`manifest-format.md`](manifest-format.md).

---

## `config.txt` versus `user.txt`

`config.txt` is in git and holds the project's defaults. **Do not edit it** to
change your own machine.

`user.txt` is **not** in git, does not exist until you create it, and holds
your overrides. You create it by hand **on every machine you set up**. This is
the single most commonly missed step.

```sh
printf 'DOME_USER=yourname\n' > manifest/user.txt
cat manifest/user.txt
```

When a setting is defined in more than one place, the **last** of these wins:

```
config.txt   →   user.txt   →   an environment variable
```

So an environment variable beats `user.txt`, which beats `config.txt`.

**Write `user.txt` with `>` and not `>>` when you mean to replace it.** A
duplicated line does not currently produce an error — the two values get
concatenated into nonsense, and the result is a setting that silently does
nothing. If you are adding a line to a file you already made, check the result
with `cat`.

---

## The five settings

These are all you ever set. Each has a default, so you only write the ones
that differ.

**`DOME_USER`** — the login account to set up. It must match an account that
already exists on the machine. On a Pi, it must match the username you typed
into Raspberry Pi Imager.

**`DOME_TARGET`** — what kind of machine this is: `pi`, `vm`, or `cloud`.
Default `pi`.

- `pi` installs camera, lidar and GPIO support, and creates a swapfile.
- `vm` skips all hardware-specific work.
- `cloud` skips hardware too, but still creates the swapfile, because rented
  machines are usually short on memory.

Getting this wrong is the most common cause of a confusing failure: on a VM
without `DOME_TARGET=vm`, the scripts try to build a Raspberry Pi audio
overlay and stop with `install: invalid target '/boot/firmware/...'`.

**`DOME_MODE`** — `native` or `docker`. Default `native`. `native` installs ROS
directly onto the machine. `docker` means this machine runs the prebuilt
container instead, and is only used by the container recipe.

**`DOME_DESKTOP`** — `none` or `vnc`. Default `none`. Set `vnc` when you need a
real graphical display for something like `rviz2`.

**`DOME_VNC_ACCESS`** — `none`, `tunnel`, or `public`. Only meaningful with
`DOME_DESKTOP=vnc`. It decides **who can reach that desktop**: `tunnel` means
only someone with an SSH key, over a tunnel; `public` means anyone with the
URL and a password. Covered in the cloud recipe.

**`REPOS_CONFIG`** — which set of repositories to clone. See the next section.

---

## Repository sets

A machine does not clone "the repos". It clones **one named set**, and the
name maps to a file:

| `REPOS_CONFIG` | File | What you get | GitHub key? |
|---|---|---|---|
| `DOME` | `manifest/repos-dome.txt` | The whole robot. The default. | **Yes** |
| `SAFE` | `manifest/repos-safe.txt` | Shell tools and a launch library | No |
| `NONE` | *(none)* | Nothing at all | No |

`DOME` needs a GitHub key because most of the robot's repositories are
private. `SAFE` contains only public repositories reachable over HTTPS, so a
machine using it never needs a credential — which is the point of it on a
machine exposed to the internet.

The build tells you which set it picked before it clones anything:

```
==> REPOS_CONFIG=SAFE (manifest/repos-safe.txt, 2 repos, no GitHub SSH key needed)
```

`NONE` is reserved and means clone nothing. A name with no matching file is an
error that names the file it looked for — it never quietly falls back to a
default or clones nothing and calls that success.

**To add a set**, drop in `manifest/repos-<name>.txt` and use `<NAME>`. No code
changes.

---

## The three scripts, and which to re-run

Order matters the first time. After that, you re-run only the one that owns
what you changed.

**`scripts/host-setup.sh`** — owns **the machine and the account**. Creates the
login user, installs device rules, and on a Pi sets up hardware access. Run it
once, reboot afterward.

> Device rules only reach the system when this script runs. If you pull a
> change to them later, a `git pull` alone does nothing — re-run this script.

**`scripts/bare-metal-base.sh`** — owns **packages**. Installs ROS itself and
everything in `packages.txt` and `pip.txt`. Safe to re-run any time; re-run it
after changing either list, or after changing `DOME_DESKTOP`.

**`scripts/bare-metal-build.sh`** — owns **repositories and the build**. Clones
the selected set, resolves dependencies, compiles the workspace, and installs
your `~/.bashrc`. Re-run it after changing a repository set.

All three need `sudo`. So:

| You changed | Re-run |
|---|---|
| `packages.txt` or `pip.txt` | `bare-metal-base.sh` |
| `DOME_DESKTOP` | `bare-metal-base.sh` |
| a repository set, or `REPOS_CONFIG` | `bare-metal-build.sh` |
| device rules | `host-setup.sh` |

**An important limit:** the build **skips any repository that is already
cloned**. So pulling this repo and rebuilding picks up *newly added*
repositories, but does **not** update the ones already on disk. To update one:

```sh
git -C ~/ros2_ws/src/<repo> pull
sudo ~/provision_dome/scripts/bare-metal-build.sh
```

---

## The two Makefiles run on different machines

This trips people up, so it is worth being blunt.

**The one in the repository root runs on the machine you built.** It wraps the
day-to-day jobs there:

```sh
make build      # clone new repos and recompile
make desktop    # start the graphical desktop
make env        # show the settings actually in effect
make status     # is the workspace built, and how many packages
```

**The one in `terraform/oci/` runs on your own computer**, and controls a
rented cloud machine from outside. It needs cloud credentials, so it does not
work on the machine itself:

```sh
make -C terraform/oci start    # start the machine
make -C terraform/oci stop     # stop it (do this between sessions)
make -C terraform/oci ssh      # log in
make -C terraform/oci status   # is it running, and at what address
make -C terraform/oci audit    # check it holds no credentials
```

If a `make` command says it cannot find your cloud credentials, you are
running it on the wrong machine.

---

## The workspace, and why you need a new terminal

Your code lives in **`~/ros2_ws`**. Sources in `~/ros2_ws/src`, compiled
output in `~/ros2_ws/install`.

The build installs a `~/.bashrc` that sets up ROS and your workspace for you.
**It only takes effect in shells started afterward.** The terminal you ran the
build in does not have it.

So after any build: **open a new terminal, or log out and back in.** If `ros2`
is not found, or `$ROS_DISTRO` is empty, this is almost always why.

You also get **`bru`**, a helper from the `rosutils` repository, on your path.
`rosutils` is cloned to `~/rosutils` rather than into the workspace, so it is
not a ROS package and will not show up in `ros2 pkg list`.

---

## Words we use

**Hosts and modes are different things.** The four recipes are **modes** —
ways of setting a machine up. Elsewhere you may see four **machines** named:
*the robot* (the Pi), *the VM*, *the box* (a rented cloud machine), and *the
Mac* (your own computer). These are not the same list. **The Mac is a machine
but not a mode** — you never run these recipes on it, you only work from it.
**A container is a mode but not a machine** — it runs on a Pi and has no
identity of its own.

**The box** — a rented cloud machine. Assume it is expendable and treat it
that way.

**Native** — ROS installed directly on the machine. Three of the four recipes.

**Container** — ROS inside a prebuilt image. One recipe.

**Underlay** — the ROS installation itself, in `/opt/ros/kilted`.

**Overlay** — your compiled workspace in `~/ros2_ws/install`, layered on top.
"Sourcing the overlay" is what makes your own packages visible.

**`rosdep`** — resolves a package's declared dependencies into things to
install. The build runs it for you.

**`colcon`** — the ROS build tool. It compiles the workspace. This is the slow
part, and on a Pi it is very slow.

**A repository set** — one named list of repositories to clone. See above.

---

## Where to go next

Pick your recipe and follow it top to bottom. Each is self-contained; you will
not need to come back here except for reference.

- **[A Raspberry Pi](cookbook-pi.md)**
- **[A virtual machine](cookbook-vm.md)**
- **[A container on a Pi](cookbook-container.md)**
- **[A rented cloud machine](cookbook-cloud.md)**

Everyday jobs and symptom-by-symptom troubleshooting are at the end of each
recipe.
