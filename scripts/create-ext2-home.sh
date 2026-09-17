#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Build the seed volume used as persistent /home by the desktop profile.

set -euo pipefail

out="${1:?output ext2 image}"
size_mb="${HOME_DISK_MB:-64}"

case "$size_mb" in
	''|*[!0-9]*)
		echo "create-ext2-home.sh: HOME_DISK_MB must be numeric" >&2
		exit 2
		;;
esac
if [ "$size_mb" -lt 16 ] || [ "$size_mb" -gt 128 ]; then
	echo "create-ext2-home.sh: supported size is 16..128 MiB" >&2
	exit 2
fi
command -v mkfs.ext2 >/dev/null 2>&1 || {
	echo "create-ext2-home.sh: install e2fsprogs (mkfs.ext2)" >&2
	exit 1
}

mkdir -p "$(dirname "$out")"
truncate -s "${size_mb}M" "$out"
# 4 KiB blocks keep this volume inside one block group up to 128 MiB, which is
# the deliberately enforced writable subset currently supported by IR0.
mkfs.ext2 -q -F -b 4096 -L IR0HOME "$out"
echo "✓ desktop ext2 /home image: $out (${size_mb} MiB)"
