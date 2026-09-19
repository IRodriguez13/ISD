# Product profiles

> **Last verified:** 2026-07-26  
> **Source of truth:** `profiles/<name>/`

Each profile directory contains:

| File | Role |
|------|------|
| `profile.conf` | Product policy (login, root, packages flags, network) |
| `packages.txt` | Packages to build/install |
| `applets.txt` | BusyBox applets linked into the rootfs |
| `services.txt` | Enabled runit services |
| `overlay/` | Optional file overlay |

| Profile | Login | Root | Packages (extra) | Purpose |
|---------|-------|------|------------------|---------|
| minimal | firstboot | locked | — | Canonical distro |
| development | root autologin | lab empty pw | doas nano ncurses | Lab / smokes |
| desktop | firstboot | noroot | doas nano ncurses **tinycc gnumake doom** + X11 | Auto `startx` on console login |
| desktop-console | firstboot | noroot | same as **desktop** | Terminal first; run `startx` manually |
| appliance | none | locked | — | Headless services |

`desktop` lists `tinycc`, `gnumake`, and `doom` in `profiles/desktop/packages.txt`
(mandatory package *slots*; Doom binary only builds when `ISD_DOOM_IWAD` points
at a real WAD — otherwise the build prompts to continue without Doom). Product
ash (`ir0_full`) ships line editing with tab / username completion and the
BusyBox-recommended companion flags.

Default: `PROFILE=minimal`.
