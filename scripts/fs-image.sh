#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# ISD root FS image backend — dispatch create/populate/verify/inspect by ROOT_FS.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ACTION="${1:?usage: fs-image.sh create|populate|verify|inspect ROOT_FS [args…]}"
ROOT_FS="${2:?usage: fs-image.sh ACTION ROOT_FS …}"
shift 2

resolve_root_fs() {
	local from_profile="${ROOT_FS:-}"
	local prof="${PROFILE:-minimal}"
	local conf="${ROOT}/profiles/${prof}/profile.conf"
	if [ -f "$conf" ]; then
		local line
		line="$(grep -E '^ROOT_FS=' "$conf" 2>/dev/null | tail -1 || true)"
		if [ -n "$line" ]; then
			from_profile="${line#ROOT_FS=}"
		fi
		if [ -z "$from_profile" ]; then
			line="$(grep -E '^ROOTFS_PACK=' "$conf" 2>/dev/null | tail -1 || true)"
			[ -n "$line" ] && from_profile="${line#ROOTFS_PACK=}"
		fi
	fi
	case "${from_profile:-minix}" in
	minix|ext2) printf '%s' "$from_profile" ;;
	*) echo "✗ unknown ROOT_FS=${from_profile}" >&2; exit 2 ;;
	esac
}

if [ "$ROOT_FS" = "auto" ]; then
	ROOT_FS="$(resolve_root_fs)"
fi

backend="${ROOT}/scripts/fs-backends/${ROOT_FS}/${ACTION}.sh"
if [ ! -f "$backend" ]; then
	echo "✗ missing backend: $backend" >&2
	exit 2
fi
chmod +x "$backend"
exec "$backend" "$@"
