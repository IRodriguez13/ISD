#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# MINIX adapter: pack a finished rootfs tree into disk.img via IR0 inject tooling.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TREE="${1:?usage: pack-minix.sh ROOTFS_TREE DISK}"
DISK="${2:?usage: pack-minix.sh ROOTFS_TREE DISK}"
IR0_ROOT="${IR0_ROOT:-${ROOT}/../IR0}"
INJECT="$(bash "${ROOT}/scripts/ir0-public-tool.sh" "${IR0_ROOT}" ir0-minix-inject-path)"
INJECT="python3 ${INJECT}"
PROFILE="${PROFILE:-${IR0_PRODUCT_PROFILE:-minimal}}"
PROF_CONF="${ROOT}/profiles/${PROFILE}/profile.conf"
INIT_SYSTEM=runit
if [ -f "$PROF_CONF" ]; then
	# shellcheck disable=SC1090
	source "$PROF_CONF"
fi
INIT_SYSTEM="${INIT_SYSTEM:-runit}"

if [ ! -f "${IR0_ROOT}/Makefile" ]; then
	echo "✗ set IR0_ROOT for MINIX packing" >&2
	exit 1
fi
if [ ! -d "$TREE" ]; then
	echo "✗ missing rootfs tree: $TREE" >&2
	exit 1
fi
if [ ! -f "$DISK" ]; then
	echo "✗ missing disk: $DISK" >&2
	exit 1
fi

inject_file()
{
	local src="$1" dest="$2"
	shift 2
	local mode
	mode=$(stat -c '%a' "$src")
	case "$mode" in
	4*|2*|6*)
		$INJECT "$DISK" --setuid "$@" "$src" "$dest"
		;;
	*)
		$INJECT "$DISK" --mode "$mode" "$@" "$src" "$dest"
		;;
	esac
}

echo "  MINIX   packing tree $TREE → $DISK"

# Fresh FS every pack. Re-injecting into a guest-used image leaves
# firstboot.done while etc/passwd is reset to locked root → FIRSTBOOT_SKIP
# and no login (desktop also has /etc/ir0-noroot).
echo "  MINIX   format-large (clean image, no stale firstboot markers)"
$INJECT --format-large "$DISK"

# Empty dirs first (pseudo-fs mountpoints + firstboot state). MINIX inject
# creates parents when writing a file; use .keep placeholders.
for d in var/lib/ir0 var/log tmp run run/doas mnt; do
	mkdir -p "${TREE}/${d}"
	touch "${TREE}/${d}/.keep"
	$INJECT "$DISK" --mode 0644 "${TREE}/${d}/.keep" "${d}/.keep"
done
# Empty mount points — do not inject files under proc/sys/dev (OpenRC live /proc test).
for d in dev proc sys heart; do
	mkdir -p "${TREE}/${d}"
done
# Applications such as X create per-user lock files here.  Parent directories
# synthesized by the injector otherwise keep its default root-only mode.
$INJECT --owner 0:0 --mode 01777 --chown "$DISK" tmp

inject_file "${TREE}/sbin/init" sbin/init
if [ "$INIT_SYSTEM" = "runit" ]; then
	inject_file "${TREE}/sbin/runit" sbin/runit
	inject_file "${TREE}/bin/runit-init" bin/runit-init
	inject_file "${TREE}/bin/runsvdir" bin/runsvdir
	inject_file "${TREE}/bin/runsv" bin/runsv
	inject_file "${TREE}/bin/sv" bin/sv
elif [ "$INIT_SYSTEM" = "sysvinit" ]; then
	inject_file "${TREE}/sbin/halt" sbin/halt
	inject_file "${TREE}/sbin/shutdown" sbin/shutdown
	$INJECT --hardlink "$DISK" sbin/halt sbin/reboot
elif [ "$INIT_SYSTEM" = "openrc" ]; then
	inject_file "${TREE}/sbin/openrc-init" sbin/openrc-init
	inject_file "${TREE}/sbin/orc-shutdn" sbin/orc-shutdn
	inject_file "${TREE}/sbin/openrc" sbin/openrc
	inject_file "${TREE}/sbin/openrc-run" sbin/openrc-run
	inject_file "${TREE}/sbin/ir0-boot" sbin/ir0-boot
	inject_file "${TREE}/sbin/console-run" sbin/console-run
	inject_file "${TREE}/sbin/logger-run" sbin/logger-run
	$INJECT --hardlink "$DISK" sbin/orc-shutdn sbin/halt
	$INJECT --hardlink "$DISK" sbin/orc-shutdn sbin/reboot
	$INJECT --hardlink "$DISK" sbin/orc-shutdn sbin/shutdown
	inject_file "${TREE}/etc/rc.conf" etc/rc.conf
	inject_file "${TREE}/etc/init.d/ir0-boot" etc/init.d/ir0-boot
	inject_file "${TREE}/etc/init.d/console" etc/init.d/console
	inject_file "${TREE}/etc/init.d/logger" etc/init.d/logger
	inject_file "${TREE}/run/openrc/.keep" run/openrc/.keep
	inject_file "${TREE}/libexec/rc/cache/deptree" libexec/rc/cache/deptree
	inject_file "${TREE}/libexec/rc/cache/softlevel" libexec/rc/cache/softlevel
	while IFS= read -r -d '' f; do
		rel="${f#${TREE}/}"
		base="$(basename "$rel")"
		[ "${#base}" -le 14 ] || continue
		inject_file "$f" "$rel"
	done < <(find "${TREE}/libexec/rc/sh" -type f -print0 2>/dev/null)
	while IFS= read -r -d '' f; do
		rel="${f#${TREE}/}"
		base="$(basename "$rel")"
		[ "${#base}" -le 14 ] || continue
		inject_file "$f" "$rel"
	done < <(find "${TREE}/libexec/rc/bin" -type f -print0 2>/dev/null)
	while IFS= read -r -d '' f; do
		rel="${f#${TREE}/}"
		inject_file "$f" "$rel"
	done < <(find "${TREE}/etc/runlevels" -type l -print0 2>/dev/null)
fi
inject_file "${TREE}/sbin/fsck.ir0" sbin/fsck.ir0
inject_file "${TREE}/sbin/ir0-firstboot" sbin/ir0-firstboot
inject_file "${TREE}/sbin/ir0-recovery" sbin/ir0-recovery
inject_file "${TREE}/sbin/mount-root-rw" sbin/mount-root-rw
inject_file "${TREE}/bin/passwd" bin/passwd
if [ -f "${TREE}/usr/sbin/adduser" ]; then
	inject_file "${TREE}/usr/sbin/adduser" usr/sbin/adduser
	$INJECT --hardlink "$DISK" usr/sbin/adduser sbin/adduser
fi
inject_file "${TREE}/bin/ir0-status" bin/ir0-status
# BusyBox has no lsblk applet; the product ships its own.
inject_file "${TREE}/bin/lsblk" bin/lsblk
if [ -f "${TREE}/usr/bin/keymap" ]; then
	inject_file "${TREE}/usr/bin/keymap" usr/bin/keymap
	inject_file "${TREE}/usr/bin/keymap" bin/keymap
fi
if [ -f "${TREE}/etc/keymap" ]; then
	inject_file "${TREE}/etc/keymap" etc/keymap
fi
inject_file "${TREE}/usr/bin/busybox-auth" usr/bin/busybox-auth
$INJECT --hardlink "$DISK" usr/bin/busybox-auth bin/login
$INJECT --hardlink "$DISK" usr/bin/busybox-auth bin/su

if [ -f "${TREE}/usr/bin/doas" ]; then
	inject_file "${TREE}/usr/bin/doas" usr/bin/doas
fi
if [ -f "${TREE}/usr/bin/sudo" ]; then
	inject_file "${TREE}/usr/bin/sudo" usr/bin/sudo
fi
if [ -f "${TREE}/usr/bin/nano" ]; then
	inject_file "${TREE}/usr/bin/nano" usr/bin/nano
fi
# X11 product payload.  The MINIX image builder is intentionally explicit,
# so desktop binaries staged in the rootfs must also be admitted here.
if [ -f "${TREE}/usr/bin/Xfbdev" ]; then
	inject_file "${TREE}/usr/bin/Xfbdev" usr/bin/Xfbdev
	$INJECT --hardlink "$DISK" usr/bin/Xfbdev usr/bin/X
fi
if [ -f "${TREE}/usr/bin/xinit" ]; then
	inject_file "${TREE}/usr/bin/xinit" usr/bin/xinit
fi
if [ -f "${TREE}/usr/bin/startx" ]; then
	inject_file "${TREE}/usr/bin/startx" usr/bin/startx
fi
if [ -f "${TREE}/usr/bin/xauth" ]; then
	inject_file "${TREE}/usr/bin/xauth" usr/bin/xauth
fi
if [ -f "${TREE}/etc/X11/xinit/xinitrc" ]; then
	inject_file "${TREE}/etc/X11/xinit/xinitrc" etc/X11/xinit/xinitrc
fi
for xclient in twm xterm xclock xeyes xlogo xcalc xmessage xload xsetroot; do
	if [ -f "${TREE}/usr/bin/${xclient}" ]; then
		inject_file "${TREE}/usr/bin/${xclient}" "usr/bin/${xclient}"
	fi
done
for app_default in XLogo XLogo-color XCalc XCalc-color Xmessage Xmessage-color XLoad; do
	if [ -f "${TREE}/usr/share/X11/app-defaults/${app_default}" ]; then
		inject_file "${TREE}/usr/share/X11/app-defaults/${app_default}" \
			"usr/share/X11/app-defaults/${app_default}"
	fi
done
# iv (line-oriented editor) + pack/unpack (libarchive wrappers).
if [ -f "${TREE}/usr/bin/iv" ]; then
	inject_file "${TREE}/usr/bin/iv" usr/bin/iv
	$INJECT --hardlink "$DISK" usr/bin/iv bin/iv
fi
if [ -f "${TREE}/usr/bin/pack" ]; then
	inject_file "${TREE}/usr/bin/pack" usr/bin/pack
	$INJECT --hardlink "$DISK" usr/bin/pack bin/pack
fi
if [ -f "${TREE}/usr/bin/unpack" ]; then
	inject_file "${TREE}/usr/bin/unpack" usr/bin/unpack
	$INJECT --hardlink "$DISK" usr/bin/unpack bin/unpack
fi
if [ -f "${TREE}/usr/bin/extract" ]; then
	inject_file "${TREE}/usr/bin/extract" usr/bin/extract
	$INJECT --hardlink "$DISK" usr/bin/extract bin/extract
fi
# GNU make (CONFIG_PKG_GNUMAKE) — inject real ELF, then PATH-friendly hardlinks.
if [ -f "${TREE}/usr/bin/make" ]; then
	inject_file "${TREE}/usr/bin/make" usr/bin/make
	$INJECT --hardlink "$DISK" usr/bin/make bin/make
fi
# TinyCC (CONFIG_PKG_TINYCC) — binary + runtime tree under lib/tcc + musl CRT/headers.
if [ -f "${TREE}/usr/bin/tcc" ]; then
	inject_file "${TREE}/usr/bin/tcc" usr/bin/tcc
	$INJECT --hardlink "$DISK" usr/bin/tcc bin/tcc
	$INJECT --hardlink "$DISK" usr/bin/tcc bin/cc
	$INJECT --hardlink "$DISK" usr/bin/tcc usr/bin/cc
fi
inject_tree_files() {
	local base="$1"
	local f rel
	[ -d "${TREE}/${base}" ] || return 0
	while IFS= read -r f; do
		rel="${f#${TREE}/}"
		inject_file "$f" "$rel"
	done < <(find "${TREE}/${base}" -type f | LC_ALL=C sort)
}
inject_tree_files lib/tcc
# Ash tab-completion snippets (rootfs/base → TREE via stage-rootfs).
inject_tree_files usr/share/ash-completion
inject_tree_files etc/X11
inject_tree_files usr/share/backgrounds
inject_tree_files usr/share/fonts/X11
# CRT / libc.a for guest linking (also mirrored under lib/tcc by stage-rootfs).
if [ -f "${TREE}/usr/lib/crt1.o" ]; then
	inject_file "${TREE}/usr/lib/crt1.o" usr/lib/crt1.o
fi
if [ -f "${TREE}/usr/lib/crti.o" ]; then
	inject_file "${TREE}/usr/lib/crti.o" usr/lib/crti.o
fi
if [ -f "${TREE}/usr/lib/crtn.o" ]; then
	inject_file "${TREE}/usr/lib/crtn.o" usr/lib/crtn.o
fi
if [ -f "${TREE}/usr/lib/libc.a" ]; then
	inject_file "${TREE}/usr/lib/libc.a" usr/lib/libc.a
fi
# Guest C headers (minimal musl set from tinycc stage).
if [ -d "${TREE}/usr/include" ] && [ -f "${TREE}/usr/bin/tcc" ]; then
	inject_tree_files usr/include
fi
if [ -f "${TREE}/etc/doas.conf" ]; then
	$INJECT "$DISK" --mode 0440 "${TREE}/etc/doas.conf" etc/doas.conf
fi
if [ -f "${TREE}/etc/sudoers" ]; then
	$INJECT "$DISK" --mode 0440 "${TREE}/etc/sudoers" etc/sudoers
fi

BUSYBOX="${TREE}/bin/busybox"
PACK_TMP="$(mktemp -d "${TMPDIR:-/tmp}/isd-pack-minix.XXXXXX")"
trap 'rm -rf "$PACK_TMP"' EXIT
MANIFEST="${PACK_TMP}/busybox-full.applets"
"$BUSYBOX" --list > "$MANIFEST"
chmod +x "${ROOT}/scripts/busybox_inject_manifest.sh"
IR0_ROOT="$IR0_ROOT" FASE50_BUSYBOX_BIN="$BUSYBOX" \
	"${ROOT}/scripts/busybox_inject_manifest.sh" "$DISK" "$BUSYBOX" "$MANIFEST"

if [ "$INIT_SYSTEM" = "runit" ]; then
	inject_file "${TREE}/etc/runit/1" etc/runit/1
	inject_file "${TREE}/etc/runit/2" etc/runit/2
	inject_file "${TREE}/etc/runit/3" etc/runit/3
	inject_file "${TREE}/etc/runit/sv/console/run" etc/runit/sv/console/run
	inject_file "${TREE}/etc/runit/sv/logger/run" etc/runit/sv/logger/run
elif [ "$INIT_SYSTEM" = "sysvinit" ]; then
	inject_file "${TREE}/etc/inittab" etc/inittab
	inject_file "${TREE}/etc/init.d/rcS" etc/init.d/rcS
	inject_file "${TREE}/sbin/console-run" sbin/console-run
	inject_file "${TREE}/sbin/logger-run" sbin/logger-run
fi

for f in passwd group issue hostname profile ashrc os-release shells hosts \
	console.conf ir0-profile resolv.conf man.conf; do
	[ -f "${TREE}/etc/${f}" ] || continue
	mode=0644
	[ "$f" = "shadow" ] && continue
	$INJECT "$DISK" --mode "$mode" "${TREE}/etc/${f}" "etc/${f}"
done
$INJECT "$DISK" --mode 0600 "${TREE}/etc/shadow" etc/shadow
[ -f "${TREE}/etc/ir0-noroot" ] && \
	$INJECT "$DISK" --mode 0644 "${TREE}/etc/ir0-noroot" etc/ir0-noroot
[ -f "${TREE}/etc/ir0-home" ] && \
	$INJECT "$DISK" --mode 0644 "${TREE}/etc/ir0-home" etc/ir0-home
[ -f "${TREE}/etc/ir0-autologin" ] && \
	$INJECT "$DISK" --mode 0644 "${TREE}/etc/ir0-autologin" etc/ir0-autologin
[ -f "${TREE}/etc/busybox/bb_status.tsv" ] && \
	$INJECT "$DISK" --mode 0644 "${TREE}/etc/busybox/bb_status.tsv" etc/busybox/bb_status.tsv
[ -f "${TREE}/etc/network/interfaces" ] && \
	$INJECT "$DISK" --mode 0644 "${TREE}/etc/network/interfaces" etc/network/interfaces
[ -f "${TREE}/usr/lib/ir0/build-info" ] && \
	$INJECT "$DISK" --mode 0644 "${TREE}/usr/lib/ir0/build-info" usr/lib/ir0/build-info

# Guest man pages (pre-rendered ASCII cat7)
if [ -d "${TREE}/usr/share/man/cat7" ]; then
	for page in "${TREE}/usr/share/man/cat7"/*.7; do
		[ -f "$page" ] || continue
		base="$(basename "$page")"
		# MINIX v1 name length ≤14 including extension
		$INJECT "$DISK" --mode 0644 "$page" "usr/share/man/cat7/${base}"
	done
fi

VERIFY_EXTRA=()
[ -f "${TREE}/usr/bin/nano" ] && VERIFY_EXTRA+=(/usr/bin/nano)
[ -f "${TREE}/usr/bin/doas" ] && VERIFY_EXTRA+=(/usr/bin/doas)
[ -f "${TREE}/usr/bin/sudo" ] && VERIFY_EXTRA+=(/usr/bin/sudo)
[ -f "${TREE}/usr/bin/iv" ] && VERIFY_EXTRA+=(/usr/bin/iv /bin/iv)
[ -f "${TREE}/usr/bin/pack" ] && VERIFY_EXTRA+=(/usr/bin/pack /bin/pack)
[ -f "${TREE}/usr/bin/extract" ] && VERIFY_EXTRA+=(/usr/bin/extract /bin/extract)
[ -f "${TREE}/usr/bin/make" ] && VERIFY_EXTRA+=(/usr/bin/make /bin/make)
[ -f "${TREE}/usr/bin/tcc" ] && VERIFY_EXTRA+=(/usr/bin/tcc /bin/tcc /bin/cc /lib/tcc/libtcc1.a)
[ -f "${TREE}/usr/bin/Xfbdev" ] && VERIFY_EXTRA+=(/usr/bin/Xfbdev /usr/bin/X)
[ -f "${TREE}/usr/bin/xinit" ] && VERIFY_EXTRA+=(/usr/bin/xinit)
[ -f "${TREE}/usr/bin/startx" ] && VERIFY_EXTRA+=(/usr/bin/startx)
[ -f "${TREE}/usr/bin/xauth" ] && VERIFY_EXTRA+=(/usr/bin/xauth)
[ -f "${TREE}/etc/X11/xinit/xinitrc" ] && VERIFY_EXTRA+=(/etc/X11/xinit/xinitrc)
[ -f "${TREE}/etc/ir0-home" ] && VERIFY_EXTRA+=(/etc/ir0-home)
[ -f "${TREE}/usr/bin/twm" ] && VERIFY_EXTRA+=(/usr/bin/twm)
[ -f "${TREE}/usr/bin/xterm" ] && VERIFY_EXTRA+=(/usr/bin/xterm)
[ -f "${TREE}/usr/bin/xclock" ] && VERIFY_EXTRA+=(/usr/bin/xclock)
[ -f "${TREE}/usr/bin/xeyes" ] && VERIFY_EXTRA+=(/usr/bin/xeyes)
[ -f "${TREE}/usr/bin/xlogo" ] && VERIFY_EXTRA+=(/usr/bin/xlogo)
[ -f "${TREE}/usr/bin/xcalc" ] && VERIFY_EXTRA+=(/usr/bin/xcalc)
[ -f "${TREE}/usr/bin/xmessage" ] && VERIFY_EXTRA+=(/usr/bin/xmessage)
[ -f "${TREE}/usr/bin/xload" ] && VERIFY_EXTRA+=(/usr/bin/xload)
[ -f "${TREE}/usr/share/X11/app-defaults/XLogo" ] && \
	VERIFY_EXTRA+=(/usr/share/X11/app-defaults/XLogo /usr/share/X11/app-defaults/XLogo-color)
[ -f "${TREE}/usr/share/X11/app-defaults/XCalc" ] && \
	VERIFY_EXTRA+=(/usr/share/X11/app-defaults/XCalc /usr/share/X11/app-defaults/XCalc-color)
[ -f "${TREE}/usr/share/X11/app-defaults/Xmessage" ] && \
	VERIFY_EXTRA+=(/usr/share/X11/app-defaults/Xmessage /usr/share/X11/app-defaults/Xmessage-color)
[ -f "${TREE}/usr/bin/xsetroot" ] && VERIFY_EXTRA+=(/usr/bin/xsetroot)
[ -f "${TREE}/usr/share/backgrounds/ir0desk.xbm" ] && \
	VERIFY_EXTRA+=(/usr/share/backgrounds/ir0desk.xbm)
[ -f "${TREE}/etc/X11/twm/system.twmrc" ] && \
	VERIFY_EXTRA+=(/etc/X11/twm/system.twmrc)

# Optional Ken games (usually injected post-pack by IR0 install-ken-games)
if [ -f "${TREE}/usr/ken/games/doom" ]; then
	$INJECT "$DISK" --mode 0755 "${TREE}/usr/ken/games/doom" usr/ken/games/doom
	$INJECT "$DISK" --mode 0755 "${TREE}/usr/ken/games/doom" usr/bin/doom
	VERIFY_EXTRA+=(/usr/ken/games/doom /usr/bin/doom)
fi
if [ -f "${TREE}/usr/ken/games/doom1.wad" ]; then
	$INJECT "$DISK" --mode 0644 "${TREE}/usr/ken/games/doom1.wad" usr/ken/games/doom1.wad
fi

# Homes
if [ -d "${TREE}/root" ]; then
	touch "${TREE}/root/.keep"
	$INJECT "$DISK" "${TREE}/root/.keep" root/.keep
	inject_tree_files root/Developer
	$INJECT --owner 0:0 --mode 0700 --chown "$DISK" root 2>/dev/null || true
fi
if [ -d "${TREE}/home/labuser" ]; then
	touch "${TREE}/home/labuser/.keep"
	$INJECT "$DISK" --mode 0644 --owner 1000:100 \
		"${TREE}/home/labuser/.keep" home/labuser/.keep
	inject_tree_files home/labuser/Developer
	$INJECT --owner 1000:100 --mode 0700 --chown "$DISK" home/labuser
fi

if [ -f "${TREE}/root/Developer/shebang/direct.sh" ]; then
	VERIFY_EXTRA+=(/root/Developer/shebang/direct.sh)
fi
if [ -f "${TREE}/root/Developer/shebang/busybox-ash.sh" ]; then
	VERIFY_EXTRA+=(/root/Developer/shebang/busybox-ash.sh)
fi

VERIFY_PATHS=( \
	/sbin/init /bin/sh /bin/busybox \
	/sbin/fsck.ir0 /sbin/ir0-firstboot /sbin/ir0-recovery /sbin/mount-root-rw /bin/passwd \
	/usr/bin/busybox-auth /bin/login /bin/su \
	/etc/passwd /etc/shadow /etc/group /etc/os-release \
)
if [ "$INIT_SYSTEM" = "runit" ]; then
	VERIFY_PATHS+=( \
		/sbin/runit /bin/runsvdir \
		/etc/runit/1 /etc/runit/2 /etc/runit/3 \
		/etc/runit/sv/console/run /etc/runit/sv/logger/run \
	)
elif [ "$INIT_SYSTEM" = "sysvinit" ]; then
	VERIFY_PATHS+=( \
		/etc/inittab /etc/init.d/rcS \
		/sbin/console-run /sbin/logger-run /sbin/halt \
	)
elif [ "$INIT_SYSTEM" = "openrc" ]; then
	VERIFY_PATHS+=( \
		/sbin/openrc-init /sbin/openrc /etc/rc.conf \
		/etc/init.d/ir0-boot /sbin/ir0-boot \
		/sbin/console-run /sbin/logger-run \
		/libexec/rc/sh/init.sh /libexec/rc/sh/rc-func.sh \
		/libexec/rc/sh/ssd-daemon.sh \
		/libexec/rc/bin/fstabinfo /libexec/rc/bin/checkpath \
		/libexec/rc/bin/mountinfo /libexec/rc/bin/rc-depend \
		/libexec/rc/cache/deptree /libexec/rc/cache/softlevel \
		/run/openrc/.keep \
		/sbin/orc-shutdn /sbin/halt \
	)
fi

python3 "${IR0_ROOT}/scripts/verify_minix_rootfs.py" --gate "$DISK" \
	"${VERIFY_PATHS[@]}" \
	"${VERIFY_EXTRA[@]}"

# Fresh product images must not carry guest firstboot markers (login brick).
if python3 "${IR0_ROOT}/scripts/verify_minix_rootfs.py" "$DISK" \
	/etc/firstboot.done >/dev/null 2>&1; then
	echo "✗ stale /etc/firstboot.done on packed image (format-large failed?)" >&2
	exit 1
fi
if python3 "${IR0_ROOT}/scripts/verify_minix_rootfs.py" "$DISK" \
	/var/lib/ir0/firstboot.done >/dev/null 2>&1; then
	echo "✗ stale /var/lib/ir0/firstboot.done on packed image" >&2
	exit 1
fi

echo "  MINIX   packed $DISK"
