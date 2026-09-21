#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
TREE="${1:?populate ROOTFS_TREE DISK}"
DISK="${2:?populate ROOTFS_TREE DISK}"
IR0_ROOT="${IR0_ROOT:-${ROOT}/../IR0}"
VERIFY="$(bash "${ROOT}/scripts/ir0-public-tool.sh" "${IR0_ROOT}" ir0-verify-minix-path)"
python3 "$VERIFY" "$DISK" sbin/init bin/busybox etc/passwd var/lib/ir0
