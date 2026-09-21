# Console login session (host → guest one-shot)

> **Last verified:** 2026-09-20  
> **Source of truth:** `rootfs/base/etc/profile`, `profiles/*/profile.conf`, IR0 `scripts/kernel_manager.py`

## Purpose

When booting a persistent machine from `make kmang`, the operator may choose
**terminal only** or **X direct** before `make poweron`. That choice is not
kernel state: it is a **one-shot userspace hint** consumed on the first console
login.

## Guest contract

| Path | Lifetime | Writer | Reader |
|------|----------|--------|--------|
| `/etc/ir0-session` | One login | IR0 host (`kernel_manager.py` via `inject_init_minix.py`) | `/etc/profile` |
| `/etc/ir0-profile` | Persistent | ISD `stage-rootfs.sh` | `/etc/profile`, init, firstboot |

### `/etc/ir0-session` values

| Content | Effect after console login |
|---------|----------------------------|
| *(file absent)* | Use profile default (see below) |
| `terminal` | Do not auto-start X |
| `x` | Run `/usr/bin/startx` on console tty when executable |

The file is **removed** immediately after read (one-shot).

### Profile default (no one-shot file)

| `/etc/ir0-profile` | Default auto-X |
|--------------------|----------------|
| `desktop` | yes (console tty) |
| `desktop-console` | no |
| other | no |

`desktop-console` ships the same X stack as `desktop`; only login policy differs.

## Host contract (kmang)

Profiles with `KMANG_BOOT_PROMPT=1` in `profiles/<name>/profile.conf` enable the
TUI prompt on **Enter** (select + boot) and **`b`** (boot Default).

Set `KMANG_BOOT_PROMPT=0` to disable the prompt for a profile without changing
guest login scripts.

IR0 writes `etc/ir0-session` on the **machine persistent disk** (`disk.img`),
not on the kernel ISO. Filename is capped at MINIX v1 `NAME_LEN=14`.

## Boundaries

- **Kernel:** not involved.
- **kmang:** injects optional one-shot file; does not repack rootfs.
- **ISD:** interprets file in `/etc/profile`; owns `/etc/ir0-profile`.
- **usmang (future):** userland composition (BusyBox vs coreutils, init system) is
  separate from this login-session hint.

## Verification

```bash
# IR0 repo
python3 scripts/test_kernel_manager.py -v
make kmang-test

# After kmang boot choice, on guest (first login)
test ! -f /etc/ir0-session && echo one-shot consumed
```
