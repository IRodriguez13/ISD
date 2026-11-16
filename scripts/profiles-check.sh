#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Validate profile applets ⊆ busybox-full and required profile files exist.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/toolchain.sh"
FULL="${PRODUCT_OUT}/busybox-full"
if [ ! -x "$FULL" ]; then
ARCH="${ARCH:-x86_64}"
FULL="${ROOT}/out/${ARCH}/busybox-full"
fi
if [ ! -x "$FULL" ]; then
	echo "✗ missing busybox-full (make build)" >&2
	exit 1
fi

list="$(mktemp "${TMPDIR:-/tmp}/ir0-us-applets.XXXXXX")"
trap 'rm -f "$list"' EXIT
"$FULL" --list | sort > "$list"

check_applets()
{
	local prof="$1"
	local missing
	missing="$(comm -23 <(grep -vE '^\s*(#|$)' "$prof" | sort -u) "$list" || true)"
	if [ -n "$missing" ]; then
		echo "✗ $prof requires applets absent from busybox-full:" >&2
		echo "$missing" >&2
		return 1
	fi
	echo "  $(basename "$(dirname "$prof")")/$(basename "$prof"): $(grep -cvE '^\s*(#|$)' "$prof") applets"
}

# New layout
for applets in "${ROOT}/profiles"/*/applets.txt; do
	[ -f "$applets" ] || continue
	check_applets "$applets"
	dir="$(dirname "$applets")"
	for req in profile.conf packages.txt services.txt; do
		if [ ! -f "${dir}/${req}" ]; then
			echo "✗ missing ${dir}/${req}" >&2
			exit 1
		fi
	done
done

# Legacy flat lists (compat)
for prof in "${ROOT}/profiles"/*.txt; do
	[ -f "$prof" ] || continue
	check_applets "$prof"
done

echo "✓ profiles-check OK"
