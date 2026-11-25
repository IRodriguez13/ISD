# Xfce session on Xorg: package inventory (plan only)

Scope: a minimal Xfce 4.20 session on Xorg with the `fbdev` video and `evdev`
input drivers, on IR0 (static musl, x86_64 first, aarch64 second). Nothing in
this file has been downloaded. Versions are the proposed pins; each must be
re-checked against the upstream release page and its checksum recorded in the
recipe (`packages/<pkg>/{url,version,sha256}`) at fetch time. Sizes are
approximate `.tar.xz` sizes. Build systems and musl notes come from memory of
Alpine's APKBUILDs, not from a fresh read.

`have` = a recipe already exists in `packages/`. Everything else is `new`.

## Policy decisions to confirm

- ISD has `tinyx` (Xfbdev, a TinyX tree). Xfce needs a full Xorg server
  (XKB, RANDR, COMPOSITE, DAMAGE, RENDER, XINPUT2); this plan adds `xorg-server`
  and keeps `tinyx` for the existing profiles.
- Static linking: GTK3 and glib use `dlopen` (gdk-pixbuf loaders, GIO modules,
  input methods, Xorg modules). Plan on a **dynamic musl** userland for the
  Xfce profile (`ld-musl-*.so.1` + shared libs) or on built-in loaders and
  `xorg-server` with the fbdev/evdev drivers linked statically
  (`--enable-static`-style, no module loading). This is a design choice for
  the maintainer; it changes every recipe below. If dynamic: IR0 must provide
  `mmap` file-backed `PROT_EXEC`, `mprotect`, `openat`+`O_CLOEXEC`,
  `/proc/self/maps`-free loading (musl needs none), and TLS (`arch_prctl` /
  `tpidr_el0`). Record gaps as IR0 gaps, do not patch upstream.
- IR0 ABI features Xfce is known to need (candidates for gap tracking):
  `eventfd2`, `signalfd4`, `timerfd_*`, `epoll_*`, `inotify_*`, `memfd_create`,
  `pipe2`, `accept4`, `socketpair`, `SCM_RIGHTS`, `SO_PEERCRED`, `AF_UNIX`
  abstract sockets (D-Bus), `/dev/input/event*` + `EVIOCG*`, `/dev/fb0` ioctls,
  `/dev/tty*` VT ioctls (`VT_*`, `KDSETMODE`), `/dev/shm`, SysV shm
  (`MIT-SHM`), `statx`/`getrandom`, `/proc/self/{exe,fd}`, `/sys/class/input`
  (libevdev/udev-less enumeration). Xorg is built with `-Dudev=false -Dhal=false`.

## Build order

Group 0 is host tooling. Groups 1-9 are target packages in dependency order.
Each group depends only on earlier ones.

### Group 0: host tools (not shipped)

| Tool | Needed by | On this host |
|------|-----------|--------------|
| python3 | meson, glib codegen, xcb | present |
| meson | glib, gtk3, cairo, pango, harfbuzz, fribidi, gdk-pixbuf, at-spi2, epoxy, xorg-server, dbus (optional), libxfce4* (xfce 4.20 uses meson for some) | MISSING |
| ninja | all meson builds | MISSING |
| pkgconf / pkg-config | all | present |
| gettext (`msgfmt`) | glib, gtk3, xfce | present (`msgfmt`) |
| glib-mkenums, glib-genmarshal, glib-compile-resources | gtk3, pango, xfce | present (host glib-dev) |
| autoconf/automake | autotools recipes | present |
| libtool (`libtoolize`) | git-tarball autotools only | MISSING (release tarballs ship `configure`) |
| gperf | fontconfig, xkeyboard-config | MISSING |
| xsltproc, itstool | docs/man pages (disable) | MISSING (disable docs) |
| cmake | none required | present |
| gobject-introspection | none (build with `-Dintrospection=disabled`) | MISSING (not needed) |
| perl, bison, flex | xorg-server, xkbcomp | present |

Missing and required: **meson, ninja, gperf**. They are host-only Python or C
tools; obtaining them is a download decision (meson and ninja: github.com/mesonbuild/meson
and github.com/ninja-build/ninja releases, about 2.2 MB and 0.25 MB).

### Group 1: base libraries

| Package | Version | Upstream | Recipe | Build | musl notes |
|---------|---------|----------|--------|-------|------------|
| zlib | 1.3.1 | zlib.net | have | autotools-like | none |
| freetype | 2.13.3 | download.savannah.gnu.org/releases/freetype | have | autotools | none; needs harfbuzz cycle: build once without, again with |
| ncurses | have | | have | | |
| libffi | 3.4.6 | github.com/libffi/libffi/releases | new | autotools | fine |
| pcre2 | 10.44 | github.com/PCRE2Project/pcre2/releases | new | autotools | fine |
| expat | 2.6.4 | github.com/libexpat/libexpat/releases | new | autotools | fine |
| libpng | 1.6.44 | download.sourceforge.net/libpng | new | autotools | fine |
| pixman | 0.43.4 | cairographics.org/releases | new | meson | fine |
| gettext-tiny or proxy-libintl | 0.3.x | github.com/sabotage-linux/gettext-tiny | new | make | musl has no `libintl`; glib needs it. Alpine uses `gettext-dev`/`musl-libintl`. |
| util-linux (libuuid, libmount) | 2.40 | kernel.org/pub/linux/utils/util-linux | new | autotools | glib `-Dlibmount=disabled`; `libuuid` only if needed |
| libevdev | 1.13.3 | freedesktop.org/software/libevdev | new | meson | evdev driver; needs `/dev/input` |
| mtdev | 1.1.6 | bitmath.org/code/mtdev | new | autotools | optional (multitouch) |
| libpciaccess | 0.18.1 | xorg.freedesktop.org/releases/individual/lib | new | meson | xorg-server dep; on IR0 w/o PCI enumeration build `-Dpciaccess=false`/no-PCI server |

### Group 2: X client libraries beyond the existing set

| Package | Version | Upstream (xorg.freedesktop.org/releases/individual/lib unless noted) | Recipe | Build |
|---------|---------|--------|--------|-------|
| libxrender, libxfixes, libxi, libxext, libx11, libxcb, libxau, libxdmcp, libxt, libice, libsm, libxmu, libxpm, libxaw, libxcursor, libxtst, libfontenc, libxfont, xtrans, xcb-proto, xorgproto | pinned in repo | | have (21) | autotools |
| libxrandr | 1.5.4 | | new | autotools |
| libxinerama | 1.1.5 | | new | autotools |
| libxcomposite | 0.4.6 | | new | autotools |
| libxdamage | 1.1.6 | | new | autotools |
| libxft | 2.3.8 | | new | autotools |
| libxpresent | 1.0.1 | | new | autotools |
| libxres | 1.2.2 | | new | autotools |
| libxscrnsaver | 1.2.4 | | new | autotools |
| libxshmfence | 1.3.2 | | new | autotools |
| libxkbfile | 1.1.3 | | new | autotools |
| libxfont2 | 2.0.7 | | new | autotools (server) |
| libxcvt | 0.1.2 | | new | meson |
| xcb-util, xcb-util-wm, xcb-util-image, xcb-util-keysyms, xcb-util-renderutil | 0.4.1 / 0.4.2 / 0.4.1 / 0.4.1 / 0.3.10 | xcb.freedesktop.org/dist | new (5) | autotools (xfwm4 needs keysyms/wm via libwnck/startup-notification) |
| startup-notification | 0.12 | freedesktop.org/software/startup-notification/releases | new | autotools | needs xcb-util |

### Group 3: fonts, keyboard, icons (data)

| Package | Version | Upstream | Recipe | Build |
|---------|---------|----------|--------|-------|
| font-misc-misc, font-cursor-misc, font-adobe-75dpi | pinned | xorg | have (3) | autotools |
| xkeyboard-config | 2.43 | xorg.freedesktop.org/releases/individual/data | new | meson |
| xkbcomp | 1.4.7 | xorg.freedesktop.org/releases/individual/app | new | autotools |
| font-util, encodings, mkfontscale, bdftopcf | 1.4.1 / 1.0.7 / 1.1.3 / 1.1.2 | xorg | new (4) | autotools (only if bitmap fonts are regenerated) |
| dejavu-fonts (ttf) | 2.37 | github.com/dejavu-fonts/dejavu-fonts/releases | new | data copy (needed for GTK text) |
| hicolor-icon-theme | 0.18 | icon-theme.freedesktop.org/releases | new | autotools/meson |
| adwaita-icon-theme | 47.0 | download.gnome.org/sources/adwaita-icon-theme | new | meson (optional; Xfce can ship elementary-xfce-less hicolor only) |
| shared-mime-info | 2.4 | gitlab.freedesktop.org/xdg/shared-mime-info | new | meson (needs host `xmllint`? build uses libxml2; see note) |
| libxml2 | 2.12.9 | download.gnome.org/sources/libxml2 | new | autotools/meson (needed by shared-mime-info) |

### Group 4: glib and the GTK3 text/graphics chain

| Package | Version | Upstream | Recipe | Build | musl notes |
|---------|---------|----------|--------|-------|------------|
| glib | 2.82.4 | download.gnome.org/sources/glib/2.82 | new | meson | `-Dlibmount=disabled -Dselinux=disabled -Dintrospection=disabled`; needs libintl (see group 1); `gio` modules via dlopen; Alpine patches a musl `gettext` path. Cross build needs a meson cross-file (`exe_wrapper` absent: use `-Dtests=false`). |
| harfbuzz | 10.1.0 | github.com/harfbuzz/harfbuzz/releases | new | meson | `-Dglib=enabled -Dfreetype=enabled -Dcairo=disabled`; C++ (needs `libstdc++` static in toolchain) |
| fribidi | 1.0.16 | github.com/fribidi/fribidi/releases | new | meson | fine |
| fontconfig | 2.15.0 | freedesktop.org/software/fontconfig/release | new | meson/autotools | needs expat, freetype, gperf (host); `FC_CACHEDIR` under `/var/cache/fontconfig` |
| cairo | 1.18.2 | cairographics.org/releases | new | meson | `-Dxlib=enabled -Dxcb=enabled -Dpng=enabled -Dtests=disabled`; static zlib/png |
| pango | 1.54.0 | download.gnome.org/sources/pango/1.54 | new | meson | needs harfbuzz, fribidi, fontconfig, cairo |
| gdk-pixbuf | 2.42.12 | download.gnome.org/sources/gdk-pixbuf/2.42 | new | meson | `-Dpng=enabled -Dothers=disabled -Dintrospection=disabled -Dbuiltin_loaders=png`; builtin loaders avoid dlopen |
| libepoxy | 1.5.10 | github.com/anholt/libepoxy/releases | new | meson | `-Degl=no -Dglx=no -Dx11=true` (no GL on fbdev; epoxy still required by GTK3 X11 backend) |
| atk + at-spi2-core | 2.38.0 + 2.54.0 | download.gnome.org/sources/at-spi2-core | new | meson | needs dbus and glib; `-Dintrospection=disabled -Dx11=enabled`; GTK3 can build `-Datk_bridge=false` but atk itself is still required (provided by at-spi2-core >= 2.46) |
| gtk3 | 3.24.43 | download.gnome.org/sources/gtk/3.24 | new | meson | `-Dx11_backend=true -Dwayland_backend=false -Dbroadway_backend=false -Dintrospection=false -Dcolord=no -Dcloudproviders=false -Dprint_backends=file -Dtests=false -Ddemos=false -Dexamples=false`; needs glib-compile-resources/glib-mkenums, gdk-pixbuf, pango, cairo, atk, epoxy, xi, xrandr, xcomposite, xdamage, xfixes, xinerama, xcursor, shared-mime-info |

### Group 5: D-Bus

| Package | Version | Upstream | Recipe | Build | musl notes |
|---------|---------|----------|--------|-------|------------|
| dbus | 1.14.10 | dbus.freedesktop.org/releases/dbus | new | autotools (meson on 1.16) | `--disable-systemd --disable-selinux --disable-libaudit --without-x --with-system-socket=/run/dbus/system_bus_socket`; needs expat; wants `socketpair`, `SCM_RIGHTS`, `SO_PEERCRED`, abstract unix sockets, `eventfd`/`epoll`. User `messagebus` and `/run/dbus` in the rootfs layer. |
| dbus-glib | not needed | | | xfce 4.20 uses GDBus |

### Group 6: Xorg server and drivers

| Package | Version | Upstream | Recipe | Build | notes |
|---------|---------|----------|--------|-------|-------|
| xorg-server | 21.1.15 | xorg.freedesktop.org/releases/individual/xserver | new | meson | `-Dxorg=true -Dxvfb=false -Dglamor=false -Dudev=false -Dudev_kms=false -Dhal=false -Dsystemd_logind=false -Ddri1/2/3=false -Dxephyr=false -Dsecure-rpc=false -Dlisten_tcp=false -Dsuid_wrapper=false`; needs pixman, libxfont2, libxkbfile, libxshmfence, xkbcomp path, `/dev/tty` VT handling |
| xf86-video-fbdev | 0.5.1 | xorg.freedesktop.org/releases/individual/driver | new | autotools | needs `/dev/fb0` (`FBIOGET_*`, `mmap`) |
| xf86-input-evdev | 2.11.0 | same | new | autotools | needs libevdev, `/dev/input/event*` |
| xorgproto, xauth, xinit, xsetroot | have | | have | | startx glue exists |
| tinyx | have | | have | | keep for non-Xfce profiles |

### Group 7: Xfce libraries

Upstream for all: `archive.xfce.org/src/<group>/<name>/4.20/<name>-4.20.0.tar.xz`
(`xfce` group: libxfce4util, xfconf, libxfce4ui, garcon, exo, xfce4-panel,
xfce4-settings, xfwm4, xfdesktop, thunar, xfce4-session, tumbler). Build:
autotools (`./configure`, GTK-Doc and introspection off, `--disable-vala`).

| Package | Version | Recipe | Needs |
|---------|---------|--------|-------|
| libxfce4util | 4.20.0 | new | glib |
| xfconf | 4.20.0 | new | glib, dbus, libxfce4util |
| libxfce4ui | 4.20.0 | new | gtk3, xfconf, libxfce4util, libgtop-less, startup-notification |
| garcon | 4.20.0 | new | gtk3, libxfce4ui, libxfce4util |
| exo | 4.20.0 | new | gtk3, libxfce4ui, libxfce4util, glib (needs host `perl`) |
| libwnck3 | 43.1 | new | gtk3, xres, startup-notification (download.gnome.org/sources/libwnck/43; xfce4-panel and xfwm4 need it) |

### Group 8: Xfce session components

| Package | Version | Recipe | Needs |
|---------|---------|--------|-------|
| xfwm4 | 4.20.0 | new | gtk3, libwnck3, libxfce4ui, xfconf, xcomposite, xdamage, xpresent, xres, xrandr, startup-notification |
| xfce4-panel | 4.20.0 | new | gtk3, libwnck3, libxfce4ui, exo, garcon, xfconf |
| xfdesktop | 4.20.0 | new | gtk3, libwnck3, libxfce4ui, exo, garcon, thunar-less (`--disable-file-icons` optional) |
| thunar | 4.20.0 | new | gtk3, exo, libxfce4ui, xfconf, gudev-less (`--disable-gudev`), pcre2 |
| xfce4-settings | 4.20.0 | new | gtk3, libxfce4ui, exo, garcon, xfconf, xi, xrandr, xcursor, libxklavier-less |
| xfce4-session | 4.20.0 | new | gtk3, libxfce4ui, xfconf, libwnck3, dbus (`--disable-polkit --disable-systemd`) |
| tumbler | 4.20.0 | new, optional | gdk-pixbuf, dbus, glib (thumbnailer; skip in minimal session) |

### Group 9: session glue (ISD, not upstream)

Profile `xfce`: `startxfce4` via `xinit`, `/etc/X11/xorg.conf.d/` with `fbdev`
and `evdev` sections, `dbus-daemon --system`, `messagebus` user, XDG dirs,
fontconfig cache dir. These are ISD layers, not packages.

## Counts and size

| Group | New packages | Approx download (MB) |
|-------|--------------|----------------------|
| 1 base libs | 10 | 30 (util-linux 8, libpng 1.5, pcre2 2, libffi 1.4, expat 0.5, pixman 1, libevdev 0.5, mtdev 0.3, libpciaccess 0.4, gettext-tiny 0.3, plus slack) |
| 2 X client libs | 19 (incl. 5 xcb-util + startup-notification) | 7 |
| 3 fonts/keyboard/icons/data | 9 | 28 (xkeyboard-config 2.5, dejavu 2.5 ttf zip 12, libxml2 2.5, shared-mime-info 0.6 + adwaita ~3, tools 1) |
| 4 glib / GTK3 chain | 9 (glib, harfbuzz, fribidi, fontconfig, cairo, pango, gdk-pixbuf, libepoxy, at-spi2-core) + gtk3 = 10 | 100 (gtk3 ~20, cairo ~32, harfbuzz ~18, glib ~5, gdk-pixbuf ~6, pango ~2, at-spi2 ~1.5, fontconfig 1.4, fribidi 1, epoxy 0.7) |
| 5 D-Bus | 1 | 1.5 |
| 6 Xorg | 3 | 5 |
| 7 Xfce libs | 6 | 9 |
| 8 Xfce session | 7 | 30 |
| **Total** | **about 65 new** (plus 21 already present, 3 fonts) | **about 210 MB** |

Estimate error is about 25 percent. Host tools add about 3 MB (meson, ninja, gperf).

## Cross toolchain (aarch64-musl)

State on this host: **no `aarch64-linux-musl-gcc`**. `make toolchain-check
ARCH=aarch64` cannot resolve a compiler (only `aarch64-linux-gnu-gcc` exists,
which is glibc and must not be used for the target). x86_64 uses
`/usr/bin/x86_64-linux-musl-gcc` from the host package set.

ISD has **no toolchain recipes** today (no gcc/binutils/musl package under
`packages/`; `scripts/toolchain.sh` only locates an installed compiler). So
"build with ISD's own recipes" first needs new recipes, in this order:

1. `binutils` 2.43.x (ftp.gnu.org/gnu/binutils, ~27 MB), target `aarch64-linux-musl`.
2. `gcc` stage 1 (gcc 14.x, ftp.gnu.org/gnu/gcc, ~90 MB) with `gmp` (~2 MB),
   `mpfr` (~1.5 MB), `mpc` (~0.8 MB), `--without-headers --disable-shared`.
3. IR0 UAPI for arm64 (already produced: `scripts/install-uapi.sh ARCH=aarch64`).
4. `musl` 1.2.5 (musl.libc.org/releases, ~1 MB) built with the stage 1 compiler,
   installed into the target sysroot.
5. `gcc` stage 2 with libgcc and libstdc++ (C++ is needed by harfbuzz).

Total about 125 MB of sources, none present on this host, plus host `make`,
`g++`, `flex/bison`. Downloads required are listed in the task report; nothing
was fetched.
