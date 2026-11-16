# IR0/Unix distro contract

> **Last verified:** 2026-07-26  
> **Source of truth:** this file, `VERSION`, `profiles/`, `Makefile`  
> **Status:** Implemented (pipeline) / Partial (aarch64 boot, DHCP)

## Purpose

IR0-userspace is the **reference builder** for the canonical minimal generic IR0/Unix
distribution — not a personal lab disk filler.

**Generic** means: not tied to one maintainer, one host path, QEMU-only, x86-64-only,
or MINIX-only; configurable by explicit profiles; same userspace over targets.

**Canonical** means: one officially supported minimal composition, documented layout
and contracts, reproducible artifacts, baseline for IR0-compatible kernels — not a
universal package manager or large distro.

## Three-tree boundary

| Tree | Owns |
|------|------|
| **IR0** | Kernel, drivers, UAPI, integration tooling / image adapters |
| **IR0-userspace** | Distro base, init, services, packages, config, rootfs |
| **IR0-desktop** | Graphics server, WM, desktop apps / overlays |

Kernel use from this repo is limited to:

1. Public UAPI via `headers_install` or an exported UAPI sysroot/tarball  
2. Integration / smokes  
3. Optional image adapters (MINIX inject, ISO)

## Primary artifact

```text
out/<arch>/rootfs/<profile>/
```

Packers consume a finished tree:

```text
rootfs tree → image-minix | rootfs-tar | (future: cpio, ext2, 9p)
```

## Profiles

| Profile | Role |
|---------|------|
| `base` | Internal common layer (not user-selected) |
| `minimal` | **Canonical** interactive minimum |
| `development` | Lab: optional root autologin, diagnostics, smokes |
| `appliance` | Services without interactive login |
| `desktop` | minimal + IR0-desktop prep (sudo, nano, ncurses, tinycc, gnumake, doom) |

Default `PROFILE` is `minimal`.

## UAPI

```bash
make headers IR0_ROOT=../IR0
make headers IR0_UAPI_TARBALL=/path/ir0-uapi.tar
make build IR0_UAPI_SYSROOT=/path/sysroot
```

No private kernel headers (`kernel/`, `mm/`, `arch/`, …).

## States

Document features as **Implemented** / **Partial** / **Planned** / **Unsupported**.

## Non-goals

Runtime package manager, systemd, PAM, glibc, dynamic libs by default, shipping
lab credentials or smoke binaries in the canonical image.
