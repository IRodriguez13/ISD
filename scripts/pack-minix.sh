#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# MINIX adapter: pack a finished rootfs tree into disk.img via IR0 inject tooling.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TREE="${1:?usage: pack-minix.sh ROOTFS_TREE DISK}"
DISK="${2:?usage: pack-minix.sh ROOTFS_TREE DISK}"
IR0_ROOT="${IR0_ROOT:-${ROOT}/../IR0}"
INJECT="python3 ${IR0_ROOT}/scripts/inject_init_minix.py"
PROFILE="${PROFILE:-${IR0_PRODUCT_PROFILE:-minimal}}"

if [ ! -f "${IR0_ROOT}/scripts/inject_init_minix.py" ]; then
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
for d in var/lib/ir0 var/log tmp dev proc sys heart run run/doas mnt; do
	mkdir -p "${TREE}/${d}"
	touch "${TREE}/${d}/.keep"
	$INJECT "$DISK" --mode 0644 "${TREE}/${d}/.keep" "${d}/.keep"
done

inject_file "${TREE}/sbin/init" sbin/init
inject_file "${TREE}/sbin/runit" sbin/runit
inject_file "${TREE}/bin/runit-init" bin/runit-init
inject_file "${TREE}/bin/runsvdir" bin/runsvdir
inject_file "${TREE}/bin/runsv" bin/runsv
inject_file "${TREE}/bin/sv" bin/sv
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
if [ -f "${TREE}/usr/bin/nano" ]; then
	inject_file "${TREE}/usr/bin/nano" usr/bin/nano
fi
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

BUSYBOX="${TREE}/bin/busybox"
MANIFEST="${ROOT}/profiles/${PROFILE}/applets.txt"
[ -f "$MANIFEST" ] || MANIFEST="${ROOT}/packages/busybox/required_applets.txt"
chmod +x "${ROOT}/scripts/busybox_inject_manifest.sh"
IR0_ROOT="$IR0_ROOT" FASE50_BUSYBOX_BIN="$BUSYBOX" \
	"${ROOT}/scripts/busybox_inject_manifest.sh" "$DISK" "$BUSYBOX" "$MANIFEST"

inject_file "${TREE}/etc/runit/1" etc/runit/1
inject_file "${TREE}/etc/runit/2" etc/runit/2
inject_file "${TREE}/etc/runit/3" etc/runit/3
inject_file "${TREE}/etc/runit/sv/console/run" etc/runit/sv/console/run
inject_file "${TREE}/etc/runit/sv/logger/run" etc/runit/sv/logger/run

for f in passwd group issue hostname profile os-release shells hosts \
	console.conf ir0-profile resolv.conf man.conf; do
	[ -f "${TREE}/etc/${f}" ] || continue
	mode=0644
	[ "$f" = "shadow" ] && continue
	$INJECT "$DISK" --mode "$mode" "${TREE}/etc/${f}" "etc/${f}"
done
$INJECT "$DISK" --mode 0600 "${TREE}/etc/shadow" etc/shadow
[ -f "${TREE}/etc/ir0-noroot" ] && \
	$INJECT "$DISK" --mode 0644 "${TREE}/etc/ir0-noroot" etc/ir0-noroot
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
[ -f "${TREE}/usr/bin/iv" ] && VERIFY_EXTRA+=(/usr/bin/iv /bin/iv)
[ -f "${TREE}/usr/bin/pack" ] && VERIFY_EXTRA+=(/usr/bin/pack /bin/pack)
[ -f "${TREE}/usr/bin/extract" ] && VERIFY_EXTRA+=(/usr/bin/extract /bin/extract)
[ -f "${TREE}/usr/bin/make" ] && VERIFY_EXTRA+=(/usr/bin/make /bin/make)
[ -f "${TREE}/usr/bin/tcc" ] && VERIFY_EXTRA+=(/usr/bin/tcc /bin/tcc /bin/cc /lib/tcc/libtcc1.a)

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
	$INJECT --owner 0:0 --mode 0700 --chown "$DISK" root 2>/dev/null || true
fi
if [ -d "${TREE}/home/labuser" ]; then
	touch "${TREE}/home/labuser/.keep"
	$INJECT "$DISK" --mode 0644 --owner 1000:100 \
		"${TREE}/home/labuser/.keep" home/labuser/.keep
	$INJECT --owner 1000:100 --mode 0700 --chown "$DISK" home/labuser
fi

python3 "${IR0_ROOT}/scripts/verify_minix_rootfs.py" --gate "$DISK" \
	/sbin/init /sbin/runit /bin/runsvdir /bin/sh /bin/busybox \
	/sbin/fsck.ir0 /sbin/ir0-firstboot /sbin/ir0-recovery /sbin/mount-root-rw /bin/passwd \
	/usr/bin/busybox-auth /bin/login /bin/su \
	/etc/passwd /etc/shadow /etc/group /etc/os-release \
	/etc/runit/1 /etc/runit/2 /etc/runit/3 \
	/etc/runit/sv/console/run /etc/runit/sv/logger/run \
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
