#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
DISK="${1:?verify DISK [PATH …]}"
shift
IR0_ROOT="${IR0_ROOT:-${ROOT}/../IR0}"
VERIFY="${IR0_ROOT}/scripts/verify_ext2_rootfs.sh"
if [ ! -x "$VERIFY" ]; then
	chmod +x "$VERIFY" 2>/dev/null || true
fi
if [ "$#" -eq 0 ]; then
	set -- sbin/init bin/busybox etc/passwd var/lib/ir0
fi
exec "$VERIFY" "$DISK" "$@"
