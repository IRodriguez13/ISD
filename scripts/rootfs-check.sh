#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TREE="${1:?usage: rootfs-check.sh TREE}"
PROFILE="${PROFILE:-minimal}"
ARCH="${ARCH:-x86_64}"
fail=0

check()
{
	if ! "$@"; then
		echo "✗ $*" >&2
		fail=1
	fi
}

[ -d "$TREE" ] || { echo "✗ missing tree $TREE" >&2; exit 1; }

# Layout
for d in bin sbin usr/bin etc proc sys heart run tmp var home root; do
	[ -d "${TREE}/${d}" ] || { echo "✗ missing /${d}" >&2; fail=1; }
done

mode_tmp=$(stat -c '%a' "${TREE}/tmp")
[ "$mode_tmp" = "1777" ] || { echo "✗ /tmp mode $mode_tmp want 1777" >&2; fail=1; }
mode_root=$(stat -c '%a' "${TREE}/root")
[ "$mode_root" = "700" ] || { echo "✗ /root mode $mode_root want 700" >&2; fail=1; }

[ -f "${TREE}/etc/os-release" ] || { echo "✗ missing os-release" >&2; fail=1; }
[ -f "${TREE}/etc/shadow" ] || { echo "✗ missing shadow" >&2; fail=1; }
sm=$(stat -c '%a' "${TREE}/etc/shadow")
[ "$sm" = "600" ] || { echo "✗ shadow mode $sm" >&2; fail=1; }

# No personal / smoke artifacts in canonical profiles
	if [ "$PROFILE" = "minimal" ] || [ "$PROFILE" = "desktop" ] || \
	   [ "$PROFILE" = "desktop-console" ] || [ "$PROFILE" = "appliance" ]; then
	if grep -RInE 'ivan|/home/ivan|FASE|doom-smoke|f52-harness' "$TREE" 2>/dev/null | head -20; then
		echo "✗ forbidden content in canonical rootfs" >&2
		fail=1
	fi
	if [ -e "${TREE}/etc/ir0-autologin" ]; then
		echo "✗ autologin must not ship in $PROFILE" >&2
		fail=1
	fi
fi

# Banner commands exist when announced
if [ -x "${TREE}/etc/runit/sv/console/run" ] || [ -f "${TREE}/etc/issue" ]; then
	for cmd in ir0-status; do
		if [ ! -e "${TREE}/bin/${cmd}" ] && [ ! -e "${TREE}/usr/bin/${cmd}" ]; then
			echo "✗ banner command missing: $cmd" >&2
			fail=1
		fi
	done
fi

# Broken symlinks
while IFS= read -r -d '' l; do
	if [ ! -e "$l" ]; then
		echo "✗ broken symlink: ${l#"${TREE}"}" >&2
		fail=1
	fi
done < <(find "$TREE" -type l -print0)

# No host absolute paths in text configs
if grep -RInE '/home/ivanr013|/Escritorio' "$TREE/etc" 2>/dev/null | head -5; then
	echo "✗ host absolute path in /etc" >&2
	fail=1
fi

if [ "$fail" -ne 0 ]; then
	exit 1
fi
echo "✓ rootfs-check OK $TREE"
