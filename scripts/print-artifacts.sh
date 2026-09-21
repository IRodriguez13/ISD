#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Machine-readable artifact manifest for IR0 bridge (no internal out/ paths in kernel).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="${ARCH:-x86_64}"
PROFILE="${PROFILE:-minimal}"
PROF_CONF="${ROOT}/profiles/${PROFILE}/profile.conf"

if [ ! -f "${ROOT}/profiles/${PROFILE}/packages.txt" ]; then
	echo "✗ print-artifacts: unknown PROFILE=${PROFILE}" >&2
	exit 2
fi

requires_home=0
rootfs_pack=minix
if [ -f "$PROF_CONF" ]; then
	line="$(grep -E '^REQUIRES_HOME_DISK=' "$PROF_CONF" 2>/dev/null | tail -1 || true)"
	case "${line#REQUIRES_HOME_DISK=}" in
	1|yes|YES|y|Y|true|TRUE) requires_home=1 ;;
	esac
	line="$(grep -E '^ROOT_FS=' "$PROF_CONF" 2>/dev/null | tail -1 || true)"
	case "${line#ROOT_FS=}" in
	minix|ext2) rootfs_pack="${line#ROOT_FS=}" ;;
	esac
	if [ "$rootfs_pack" = minix ]; then
		line="$(grep -E '^ROOTFS_PACK=' "$PROF_CONF" 2>/dev/null | tail -1 || true)"
		case "${line#ROOTFS_PACK=}" in
		minix|ext2) rootfs_pack="${line#ROOTFS_PACK=}" ;;
		esac
	fi
fi

out_arch="${ROOT}/out/${ARCH}"
root_disk="${out_arch}/images/${PROFILE}/disk.img"
root_disk_ext2="${out_arch}/images/${PROFILE}/disk.ext2.img"
home_disk="${out_arch}/images/${PROFILE}/home.ext2.img"
rootfs="${out_arch}/rootfs/${PROFILE}"
rootfs_stamp="${out_arch}/stamps/rootfs/${PROFILE}"
variant_id="$(PROFILE="${PROFILE}" ARCH="${ARCH}" IR0_ROOT="${IR0_ROOT:-}" \
	bash "${ROOT}/scripts/compute-variant-id.sh" 2>/dev/null || echo "${PROFILE}")"

emit() {
	printf '%s=%s\n' "$1" "$2"
}

emit ROOT_DISK "$root_disk"
emit ROOT_DISK_EXT2 "$root_disk_ext2"
emit HOME_DISK "$home_disk"
emit ROOTFS "$rootfs"
emit ROOTFS_STAMP "$rootfs_stamp"
emit REQUIRES_HOME_DISK "$requires_home"
emit ROOT_FS "$rootfs_pack"
emit ROOTFS_PACK "$rootfs_pack"
emit VARIANT_ID "$variant_id"
emit ARCH "$ARCH"
emit PROFILE "$PROFILE"
