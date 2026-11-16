# Profile: minimal (canonical)

> **Last verified:** 2026-07-26  
> **Source of truth:** `profiles/minimal/`, this file  
> **State:** Implemented (composition) / Partial (network tools, guest man)

## Required

| Item | Notes |
|------|-------|
| runit PID 1 + stage 1/2/3 | `/sbin/init`, `/etc/runit/{1,2,3}` |
| Service supervision | console + logger enabled ([`CONSOLE.md`](CONSOLE.md): fork+wait session) |
| busybox-full (0755) | Non-privileged general tools |
| busybox-auth (setuid) | `login` + `su` only |
| `ir0-passwd` (setuid) | Dedicated passwd helper |
| ash / sh | Login shell |
| Essential Unix tools | See `profiles/minimal/applets.txt` |
| Pseudo-fs mounts | `/dev`, `/proc`, `/sys`, `/heart`, `/run`, `/tmp` |
| hostname | Default `ir0`, configurable at firstboot |
| Unix accounts | Base: locked `root` only; first user via firstboot |
| Secure firstboot | Interactive or `FIRSTBOOT_SEED`; no implicit identity |
| shutdown/reboot/poweroff | BusyBox applets |
| Standard `/etc` | `os-release`, `issue`, `hosts`, `profile`, `shells`, … |
| Local recovery | Documented; `ir0-recovery` |

## Optional

| Item | When |
|------|------|
| sudo | Profiles that declare an admin user / wheel |
| Static network config | `NETWORK_MODE=static` when ABI allows |
| Guest man pages | Injected from kernel `prepare-guest-mandocs` when available |

## Unsupported (not in minimal)

| Item | Reason |
|------|--------|
| nano / ncurses | Desktop / development only |
| sudo by default | No admin user until firstboot; package optional |
| Graphics / Doom | IR0-desktop / smokes |
| TCC / GNU make | Devtools overlay |
| KTM / FASE / hostshare payloads | `out/<arch>/smoke/` only |
| Known lab credentials | `tests/fixtures/`, `smoke/overlays/` |
| Root autologin | Development only |
| Network applets that only compile | Not declared supported |

## Development-only (never ship in minimal)

- `ir0-autologin`, empty root password  
- Smoke tags / fase harnesses  
- QEMU usernet DNS as product default  
- Fixture users (`labuser`, historical `ivan` in tests)

## Login / root policy

- No root autologin  
- Root shadow locked (`!`) until an explicit seed changes policy  
- First interactive user created by firstboot; empty password rejected  
- Non-TTY without `FIRSTBOOT_SEED` leaves firstboot pending (no silent account)
