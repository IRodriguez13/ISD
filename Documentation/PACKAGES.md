# ISD packages, stamps, and truth model

> **Last verified:** 2026-07-28  
> **Source of truth:** `Makefile`, `mk/paths.mk`, `scripts/resolve-packages.sh`,
> `scripts/isdconfig.py`, `scripts/stage-rootfs.sh`.

## Truth model

| Layer | File | Role |
|-------|------|------|
| Profile mandatory set | `profiles/<profile>/packages.txt` | Packages always built/installed for that profile |
| Extras | `.isdconfig` (`CONFIG_PKG_*`, `CONFIG_APPLET_*`) | Optional packages + BusyBox applet links; `make isdconfig` (interactive) / `isd-defconfig` |
| Core | busybox + runit | Always on; cannot disable |
| Policy only | `profiles/<profile>/profile.conf` | Login/root/fsck/network — **not** package truth |

Resolver (`scripts/resolve-packages.sh`):

```text
core (busybox runit)
  ∪ profiles/$PROFILE/packages.txt
  ∪ .isdconfig CONFIG_PKG_*=y
  + auto-dep nano → ncurses
```

Applets: profile `applets.txt` plus `.isdconfig` `CONFIG_APPLET_*=y` (e.g. `CONFIG_APPLET_TOP=y` → `/bin/top`). BusyBox must include the applet (`CONFIG_TOP=y` in `packages/busybox/ir0_full.config`).

`profiles/*/packages.txt` is lean (busybox+runit). Common extras default to **y** in `isd-defconfig` (nano, ncurses, opendoas, top).

## Stamp layout

```text
out/<arch>/stamps/
  toolchain/ok
  uapi/headers
  packages/<pkg>
  services/product
  rootfs/<profile>
  images/<profile>
```

| Stamp | Depends on | Notes |
|-------|------------|-------|
| **packages/**\* | toolchain **only** | Independent of UAPI — recipes use musl (+ host Linux headers where needed) |
| **services/product** | toolchain + UAPI | `build-services.sh` needs `-isystem sysroot/usr/include` |
| **rootfs/\<profile\>** | package stamps + services + UAPI + stage inputs / overlays | Overlay files feed the Make graph via `find` |
| **images/\<profile\>** | rootfs stamp | `disk.img` under `out/<arch>/images/<profile>/` |

`scripts/stamp-run.sh` writes a stamp **only on success**. A failed recipe leaves the previous stamp (if any) untouched so Make retries.

## Overlays → rootfs

`stage-rootfs.sh` layers (missing dirs are no-ops):

1. `rootfs/base`
2. legacy `rootfs/` (`etc`, `root`, …)
3. `profiles/<profile>/overlay`
4. `rootfs/arch/<arch>`
5. `rootfs/local` (gitignored personal overrides)

Keep empty overlay dirs with `.keep` so the tree exists in git.

## Packaged extras

| CONFIG | Recipe | Guest install |
|--------|--------|---------------|
| `CONFIG_PKG_NANO` | `packages/nano/` | `/usr/bin/nano` (+ auto `ncurses`) |
| `CONFIG_PKG_NCURSES` | `packages/ncurses/` | (library for nano) |
| `CONFIG_PKG_OPENDOAS` | `packages/opendoas/` | `/usr/bin/doas` |
| `CONFIG_PKG_GNUMAKE` | `packages/gnumake/` | `/usr/bin/make`, `/bin/make` |
| `CONFIG_PKG_TINYCC` | `packages/tinycc/` | `/usr/bin/tcc`, `/lib/tcc/`, musl CRT/headers |
| `CONFIG_PKG_DOOM` | `packages/doom/` | `/usr/ken/games/doom`, `/usr/share/doom/doom1.wad` |

## Keyboard layout (US + LATAM)

Both PS/2 ASCII maps live in the IR0 kernel. ISD ships `/usr/bin/keymap` (not
BusyBox `loadkmap` — that needs Linux `KDSKBENT`, which IR0 does not implement):

```bash
keymap           # print current: us | latam
keymap latam     # set + persist /etc/keymap
keymap us
```

The console service applies `/etc/keymap` at start. Firstboot wizard asks
`us|latam` (default `us`). Do **not** enable BusyBox `CONFIG_LOADKMAP` for this.

`make fetch` downloads into `packages/<name>/dist` and unpacks to
`packages/<name>/src` only when missing (safe to re-run offline).
`packages/doom/` uses a custom `fetch.sh` (sources from `IR0_ROOT/setup/doom`).

`make clean` removes **`out/` only** (stamps + staged binaries). It never
deletes `packages/*/src` or `packages/*/dist`. `make distclean` also drops
unpacked `src/` but keeps downloaded tarballs in `dist/`.

## Doom IWAD

Desktop lists `doom` in `packages.txt`. IWAD discovery (`scripts/find-doom-iwad.sh`):

1. `ISD_DOOM_IWAD=/path/to/doom1.wad` (explicit)
2. `rootfs/local/usr/share/doom/` or `…/ken/games/` (`doom1.wad` / `DOOM1.WAD`)
3. Lab tree `../universal-doom/DOOM1.WAD` (sibling of ISD or IR0, or
   `$HOME/Escritorio|Desktop/universal-doom`)

```bash
# Usually enough when ../universal-doom/DOOM1.WAD exists:
make build PROFILE=desktop
# Or force a path:
export ISD_DOOM_IWAD=/path/to/doom1.wad
make build-doom PROFILE=desktop
```

If **no** IWAD is found:

- **TTY:** asks whether to continue the ISD build **without** compiling Doom.
- **Non-interactive:** skips Doom (exit 0) unless `ISD_DOOM_REQUIRE=1` (hard fail)
  or `ISD_DOOM_SKIP=1` (skip, no prompt).
- Rootfs omits `/usr/ken/games/doom` until an IWAD is found and you rebuild
  (`rm out/<arch>/stamps/packages/doom && make build-doom`).

`CONFIG_PKG_DOOM=y` is scrubbed to `n` on validate **only** when no IWAD is
found. With `../universal-doom/DOOM1.WAD` present, `=y` is kept.
