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
if [ -f "$PROF_CONF" ]; then
	line="$(grep -E '^REQUIRES_HOME_DISK=' "$PROF_CONF" 2>/dev/null | tail -1 || true)"
	case "${line#REQUIRES_HOME_DISK=}" in
	1|yes|YES|y|Y|true|TRUE) requires_home=1 ;;
	esac
fi

out_arch="${ROOT}/out/${ARCH}"
root_disk="${out_arch}/images/${PROFILE}/disk.img"
home_disk="${out_arch}/images/${PROFILE}/home.ext2.img"
rootfs="${out_arch}/rootfs/${PROFILE}"
rootfs_stamp="${out_arch}/stamps/rootfs/${PROFILE}"
variant_id="$(PROFILE="${PROFILE}" ARCH="${ARCH}" IR0_ROOT="${IR0_ROOT:-}" \
	bash "${ROOT}/scripts/compute-variant-id.sh" 2>/dev/null || echo "${PROFILE}")"

emit() {
	printf '%s=%s\n' "$1" "$2"
}

emit ROOT_DISK "$root_disk"
emit HOME_DISK "$home_disk"
emit ROOTFS "$rootfs"
emit ROOTFS_STAMP "$rootfs_stamp"
emit REQUIRES_HOME_DISK "$requires_home"
emit VARIANT_ID "$variant_id"
emit ARCH "$ARCH"
emit PROFILE "$PROFILE"
