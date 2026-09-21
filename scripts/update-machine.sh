#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Update userspace payload on a persistent machine disk (ISD-owned; IR0 supplies inject tool).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IR0_ROOT="${IR0_ROOT:?IR0_ROOT is required}"
ARCH="${ARCH:-x86_64}"
PROFILE="${PROFILE:-minimal}"
MACHINE_DIR="${MACHINE_DIR:?MACHINE_DIR is required}"
PROF_CONF="${ROOT}/profiles/${PROFILE}/profile.conf"

requires_home=0
if [ -f "$PROF_CONF" ]; then
	line="$(grep -E '^REQUIRES_HOME_DISK=' "$PROF_CONF" 2>/dev/null | tail -1 || true)"
	case "${line#REQUIRES_HOME_DISK=}" in
	1|yes|YES|y|Y|true|TRUE) requires_home=1 ;;
	esac
fi
if [ "$requires_home" != "1" ]; then
	echo "✗ update-machine: PROFILE=${PROFILE} does not support live userspace update" >&2
	exit 2
fi

DISK="${MACHINE_DIR}/disk.img"
TREE="${ROOT}/out/${ARCH}/rootfs/${PROFILE}"
INJECT="$(bash "${ROOT}/scripts/ir0-public-tool.sh" "$IR0_ROOT" ir0-minix-inject-path)"

if [ ! -f "$DISK" ]; then
	echo "✗ missing machine disk: $DISK" >&2
	exit 2
fi

echo "  UPDATE   PROFILE=${PROFILE} rootfs-tree"
make -C "$ROOT" IR0_ROOT="$IR0_ROOT" ARCH="$ARCH" PROFILE="$PROFILE" -s rootfs-tree

if [ ! -d "$TREE" ]; then
	echo "✗ missing staged rootfs: $TREE" >&2
	exit 2
fi

temporary="${DISK}.desktop-new.$$"
previous="${DISK}.previous"
trap 'rm -f "$temporary"' EXIT
cp --reflink=auto --sparse=always "$DISK" "$temporary"

inject_file()
{
	local path="$1"
	local source="${TREE}/${path}"
	local mode
	if [ ! -f "$source" ]; then
		echo "✗ desktop payload missing: $source" >&2
		exit 2
	fi
	mode=$(stat -c '%a' "$source")
	python3 "$INJECT" --mode "$mode" "$temporary" "$source" "$path"
}

inject_tree_files()
{
	local base="$1"
	local f rel
	[ -d "${TREE}/${base}" ] || return 0
	while IFS= read -r f; do
		rel="${f#${TREE}/}"
		inject_file "$rel"
	done < <(find "${TREE}/${base}" -type f | LC_ALL=C sort)
}

for path in \
	usr/bin/Xfbdev usr/bin/X usr/bin/xinit usr/bin/startx usr/bin/xauth \
	usr/bin/twm usr/bin/xterm usr/bin/xsetroot \
	usr/bin/xclock usr/bin/xeyes usr/bin/xlogo usr/bin/xcalc usr/bin/xmessage \
	etc/X11/xinit/xinitrc \
	usr/share/fonts/X11/misc/6x13.bdf \
	usr/share/fonts/X11/misc/cursor.bdf \
	usr/share/fonts/X11/misc/fonts.alias \
	usr/share/fonts/X11/misc/fonts.dir
do
	if [ "$path" = usr/bin/X ]; then
		python3 "$INJECT" --mode 04755 "$temporary" \
			"${TREE}/usr/bin/Xfbdev" "$path"
	else
		inject_file "$path"
	fi
done

inject_tree_files etc/X11/twm
inject_tree_files usr/share/backgrounds
inject_tree_files usr/share/X11/app-defaults
for path in etc/profile etc/ashrc; do
	inject_file "$path"
done

python3 "$INJECT" --owner 0:0 --mode 01777 --chown "$temporary" tmp

cp --reflink=auto --sparse=always "$DISK" "$previous"
mv "$temporary" "$DISK"
trap - EXIT
echo "✓ machine userspace updated: $DISK"
echo "  ROLLBACK $previous"
