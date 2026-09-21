#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# STO-0: estimate EXT2 root image size from a staged rootfs tree (host e2fsprogs).
set -euo pipefail

TREE="${1:?usage: estimate-rootfs-ext2.sh ROOTFS_TREE}"
DISK_MB_MIN="${DISK_MB_MIN:-32}"
DISK_MB_MAX="${DISK_MB_MAX:-64}"
DISK_MB_FLOOR="${EXT2_DISK_MB_FLOOR:-32}"

if [ ! -d "$TREE" ]; then
	echo "✗ missing rootfs tree: $TREE" >&2
	exit 2
fi

kb="$(du -sk "$TREE" | awk '{print $1}')"
files="$(find "$TREE" -xdev \( -type f -o -type l \) 2>/dev/null | wc -l | tr -d ' ')"

# Headroom for metadata + growth; stay within kernel ext2 single block-group cap.
need_mb="$(( (kb * 2 / 1024) + 24 ))"
if [ "$need_mb" -lt "$DISK_MB_MIN" ]; then
	need_mb="$DISK_MB_MIN"
fi
if [ "$need_mb" -lt "$DISK_MB_FLOOR" ]; then
	need_mb="$DISK_MB_FLOOR"
fi
if [ "$need_mb" -gt "$DISK_MB_MAX" ]; then
	echo "✗ EXT2 estimate ${need_mb}MiB exceeds cap ${DISK_MB_MAX}MiB (tree ${kb}KiB)" >&2
	exit 2
fi

echo "  EXT2    tree=${kb}KiB files=${files} → ${need_mb}MiB image (cap ${DISK_MB_MAX}MiB)" >&2
printf 'EXT2_TREE_KB=%s\nEXT2_FILE_COUNT=%s\nEXT2_SIZE_MB=%s\n' "$kb" "$files" "$need_mb"
