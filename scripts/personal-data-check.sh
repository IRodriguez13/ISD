#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Fail if the canonical product tree contains known personal/lab identities.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE="${PROFILE:-minimal}"
ARCH="${ARCH:-x86_64}"
TREE="${1:-${ROOTFS_OUT:-${ROOT}/out/${ARCH}/rootfs}/${PROFILE}}"

# Always scan shipped base overlays for canonical profiles.
scan_paths=("${ROOT}/rootfs/base" "${ROOT}/rootfs/etc")
if [ -d "$TREE" ]; then
	scan_paths+=("$TREE")
fi
if [ "$PROFILE" = "minimal" ] || [ "$PROFILE" = "desktop" ] || \
   [ "$PROFILE" = "desktop-console" ] || [ "$PROFILE" = "appliance" ]; then
	:
fi

patterns='ivan|/home/ivan|ir0devivan|password[[:space:]]*=[[:space:]]*ivan'
fail=0
for p in "${scan_paths[@]}"; do
	[ -e "$p" ] || continue
	if grep -RInE "$patterns" "$p" 2>/dev/null | grep -vE 'tests/fixtures|smoke/overlays|Documentation/' ; then
		fail=1
	fi
done

# Base account files must not list the maintainer identity.
for f in passwd group shadow; do
	base="${ROOT}/rootfs/base/etc/${f}"
	legacy="${ROOT}/rootfs/etc/${f}"
	for candidate in "$base" "$legacy"; do
		[ -f "$candidate" ] || continue
		if grep -qiE 'ivan' "$candidate"; then
			echo "✗ personal identity in $candidate" >&2
			fail=1
		fi
	done
done

if [ -d "${ROOT}/rootfs/home/ivan" ] || [ -d "${ROOT}/rootfs/base/home/ivan" ]; then
	echo "✗ product home /home/ivan must not ship" >&2
	fail=1
fi

if [ "$fail" -ne 0 ]; then
	exit 1
fi
echo "✓ personal-data-check OK"
