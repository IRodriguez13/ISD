# ISD — IR0 Software Distribution

Declarative, stamp-based builder for the canonical product image on top of the
IR0 kernel: runit PID 1, BusyBox, login/auth, firstboot, recovery, and `/etc`
overlays.

Sibling kernel: [`IR0`](https://github.com/IRodriguez13/IR0) — public UAPI
(`headers_install`), pack adapters, and QEMU/`first-boot` orchestration. See
[`Documentation/DISTRO_CONTRACT.md`](Documentation/DISTRO_CONTRACT.md) and
[`Documentation/PACKAGES.md`](Documentation/PACKAGES.md).

| Layer | Repo | Role |
|-------|------|------|
| Kernel | [IR0](https://github.com/IRodriguez13/IR0) | mechanisms, drivers, UAPI, boot ISO |
| Distro | **ISD** (this tree) | packages, init, services, rootfs, `disk.img` |

<p align="center">
  <img src="Documentation/assets/isd-firstboot.png" alt="ISD first boot — create your account" width="720" />
</p>

<p align="center"><em>ISD first boot wizard (generic account; password also authenticates doas).</em></p>

<p align="center">
  <img src="Documentation/assets/isd-vi-editor.png" alt="ISD guest — BusyBox vi editing main.c" width="720" />
</p>

<p align="center"><em>After login: BusyBox <code>vi</code> on the MINIX rootfs — edit guest sources under QEMU (<code>make run PROFILE=minimal</code> from IR0).</em></p>

<p align="center">
  <img src="Documentation/assets/isd-top.png" alt="ISD guest — BusyBox top under runit" width="720" />
</p>

<p align="center"><em>BusyBox <code>top</code>: runit as PID 1 with supervised services (<code>runsvdir</code>/<code>runsv</code>) and an interactive shell — product process tree on QEMU.</em></p>

<p align="center">
  <img src="Documentation/assets/isd-doom.png" alt="IR0/Unix — Doom on QEMU (desktop profile)" width="720" />
</p>

<p align="center"><em>Doom on the desktop profile: fbdev + evdev clients on the ISD rootfs under QEMU (<code>make run PROFILE=desktop</code> from IR0).</em></p>

<p align="center">
  <img src="Documentation/assets/isd-x11-desktop.png" alt="ISD upstream X11 desktop running on IR0 with uname output" width="960" />
</p>

<p align="center"><em>Experimental <code>desktop</code> profile: unmodified X.Org clients on TinyX/Xfbdev with twm, xterm, Xaw widgets, mouse and keyboard. The terminal shows the exact IR0 kernel build used by the graphical smoke.</em></p>

## Fastest path (from IR0)

```bash
git clone https://github.com/IRodriguez13/IR0.git
cd IR0
make first-boot PROFILE=minimal    # clones ../ISD, asks before sudo install
make run PROFILE=minimal
```

Layout:

```text
parent/
├── IR0/          # kernel + first-boot / run-isd
└── ISD/          # this repo — owns out/<arch>/images/<profile>/disk.img
```

`make first-boot` does **not** inject BusyBox/runit one-by-one. It builds the
ISD image for `PROFILE` and boots that disk. Legacy inject remains behind
`IR0_LEGACY_USERSPACE=1` for smokes.

## From this tree alone

```bash
export IR0_ROOT=../IR0
make                                # instant help; no compiler or package probe
make x86-64 minimal                 # build a complete x86-64 minimal image
make arm minimal                    # same command shape for aarch64
make x86-64 desktop plan            # inspect an exact selection first
make menuconfig                     # compose an exact custom distribution
```

The default is `make isd` → `x86-64 desktop`. Outputs are ISA-local under
`out/<arch>/` and `sysroot/<arch>/`, so an x86-64 and aarch64 build cannot
overwrite one another. `ISD_JOBS=2` is the conservative default for package
sub-builds; raise it deliberately on hosts with enough memory.

Extras (interactive — packages + BusyBox applets such as `top`):

```bash
make menuconfig
# or non-interactive:
#   python3 scripts/isdconfig.py set CONFIG_PKG_NANO=y
#   python3 scripts/isdconfig.py set CONFIG_APPLET_TOP=y
make x86-64 minimal               # apply the saved minimal selection
```

`profiles/*/packages.txt` is lean (busybox+runit). Defconfig enables nano, ncurses, sudo, and applet `top` by default.

## Profiles

| Profile | Role |
|---------|------|
| `minimal` | Canonical small image — first-boot user registration + sudo + nano |
| `development` | Lab only (root autologin / fixtures) |
| `desktop` | **Default** — desktop policy + nano/ncurses |
| `appliance` | Services only (busybox + runit) |

Per-profile outputs:

```text
out/<arch>/rootfs/<profile>/
out/<arch>/images/<profile>/disk.img
out/<arch>/stamps/{toolchain,uapi,packages,services,rootfs,images}/
```

Package stamps depend on the **toolchain only** (not UAPI). Services need UAPI.
See [`Documentation/PACKAGES.md`](Documentation/PACKAGES.md).

## Layout

```text
packages/        upstream recipes + setuid.allowlist
profiles/        profile.conf (policy), packages.txt (truth), overlay/
rootfs/base/     canonical /etc (no personal accounts)
scripts/         resolve-packages, isdconfig, stamp-run, stage-rootfs, …
services/        runit stages, console, firstboot, …
out/<arch>/      product/ stamps/ rootfs/<profile>/ images/<profile>/
Documentation/   distro contract and guides
```

## Gates

```bash
./tests/contracts/run.sh
make toolchain-check ARCH=x86_64
make profiles-check
make personal-data-check
make rootfs-check PROFILE=minimal
make release-check PROFILE=minimal ARCH=x86_64
```
