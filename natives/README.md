# ISD natives

> **Last verified:** 2026-08-31
> **Source of truth:** `scripts/build-services.sh`, `scripts/stage-rootfs.sh`,
> `scripts/pack-minix.sh`

Small userspace utilities written for IR0/ISD: either ports of tools the
product needs and BusyBox does not ship, or original implementations.

## Rule: Linux first

Every native **must compile and run on Linux before it is wired into the IR0
image**. A native that only builds inside the product hides its own portability
bugs, and debugging it costs a QEMU cycle instead of a shell command.

```bash
gcc -Wall -Wextra -Os -o /tmp/lsblk natives/lsblk.c
```

The build must be warning-clean. Behaviour may differ on Linux when the tool
reads IR0-specific interfaces (`lsblk` parses the IR0 `/proc/blockdevices`
layout, which is not Linux's), but it must not crash or fail to build.

## Contents

| Native | Replaces | Reads |
|---|---|---|
| `lsblk.c` | util-linux `lsblk` (BusyBox has no such applet) | `/proc/blockdevices`, `/proc/mounts` |

Columns are limited to what IR0 can source honestly: `NAME`, `MAJ:MIN`, `SIZE`,
`TYPE`, `MOUNTPOINT`. util-linux also prints `RM` and `RO`; IR0 has no backing
data for them, so they are omitted rather than filled with zeros.

## Adding a native

1. Write it under `natives/`, GPL-3.0-only header like the rest of the tree.
2. Build it on Linux, warning-clean, and run it.
3. `scripts/build-services.sh` — add a `cc_native` line.
4. `scripts/stage-rootfs.sh` — install into the rootfs tree.
5. `scripts/pack-minix.sh` — inject into the MINIX image. This list is
   explicit: skipping it means the binary silently never reaches the disk.
6. Cover it from a smoke that does not depend on the interactive console.

Larger third-party software (BusyBox, nano, TinyCC, pack/unpack) is vendored
under `packages/` with its own `fetch.sh` / `build.sh`, not here.
