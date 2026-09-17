#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="${ROOT}/packages/font-misc-misc/src"
DEST="${PRODUCT_OUT}/stage-x11-fonts/misc"
[ -f "${SRC}/6x13.bdf" ] || {
	echo "✗ missing font-misc-misc source; run: make fetch PROFILE=desktop" >&2
	exit 1
}
mkdir -p "$DEST"
install -m 0644 "${SRC}/6x13.bdf" "${DEST}/6x13.bdf"
echo "✓ font-misc-misc core fixed font OK → ${DEST}"
