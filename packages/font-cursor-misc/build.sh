#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="${ROOT}/packages/font-cursor-misc/src"
DEST="${PRODUCT_OUT}/stage-x11-fonts/misc"
[ -f "${SRC}/cursor.bdf" ] || {
	echo "✗ missing font-cursor-misc source; run: make fetch PROFILE=desktop" >&2
	exit 1
}
mkdir -p "$DEST"
install -m 0644 "${SRC}/cursor.bdf" "${DEST}/cursor.bdf"
echo "✓ font-cursor-misc core cursor font OK → ${DEST}"
