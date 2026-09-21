#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Verify staged rootfs matches profile identity and package manifest (postcondition).
set -euo pipefail

TREE="${1:?usage: verify-profile-rootfs.sh ROOTFS_TREE}"
PROFILE="${PROFILE:-minimal}"
ARCH="${ARCH:-x86_64}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

err() { echo "✗ $*" >&2; fail=1; }

[ -d "$TREE" ] || { echo "✗ missing staged rootfs: $TREE" >&2; exit 2; }

got_profile="$(tr -d '[:space:]' < "${TREE}/etc/ir0-profile" 2>/dev/null || true)"
if [ "$got_profile" != "$PROFILE" ]; then
	err "etc/ir0-profile=${got_profile:-missing} expected ${PROFILE}"
fi

manifest="${ROOT}/profiles/${PROFILE}/verify-paths.txt"
if [ ! -f "$manifest" ]; then
	manifest="${ROOT}/profiles/minimal/verify-paths.txt"
fi

while IFS= read -r line || [ -n "$line" ]; do
	line="${line%%#*}"
	line="${line#"${line%%[![:space:]]*}"}"
	line="${line%"${line##*[![:space:]]}"}"
	[ -z "$line" ] && continue
	pkg="${line%% *}"
	rel="${line#* }"
	if [ -z "$rel" ] || [ "$rel" = "$pkg" ]; then
		continue
	fi
	if [ ! -e "${TREE}/${rel}" ]; then
		err "package ${pkg}: missing ${rel} in staged rootfs"
	fi
done < "$manifest"

if [ "$PROFILE" = "desktop" ] || [ "$PROFILE" = "desktop-console" ]; then
	if [ ! -f "${TREE}/usr/share/terminfo/x/xterm" ]; then
		err "desktop: missing usr/share/terminfo/x/xterm (ncurses terminfo)"
	fi
	clients="${ROOT}/profiles/desktop/x-session-clients.txt"
	while IFS= read -r client || [ -n "$client" ]; do
		client="${client%%#*}"
		client="${client#"${client%%[![:space:]]*}"}"
		client="${client%"${client##*[![:space:]]}"}"
		[ -z "$client" ] && continue
		if ! grep -qx "$client" "${ROOT}/profiles/${PROFILE}/packages.txt" 2>/dev/null \
			&& ! grep -qx "$client" "${ROOT}/profiles/desktop/packages.txt" 2>/dev/null; then
			err "x-session client ${client} not in profile packages.txt"
		fi
	done < "$clients"
fi

if grep -F '[ "$_ir0_profile" = "desktop" ] && _auto_x=1' "${ROOT}/rootfs/base/etc/profile" >/dev/null \
	&& grep -F 'terminal) _auto_x=0 ;;' "${ROOT}/rootfs/base/etc/profile" >/dev/null; then
	:
else
	err "login session auto-X contract missing in rootfs/base/etc/profile"
fi

if [ "$fail" -ne 0 ]; then
	exit 1
fi
echo "✓ verify-profile-rootfs OK PROFILE=${PROFILE} tree=${TREE}"
