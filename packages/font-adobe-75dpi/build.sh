#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="${ROOT}/packages/font-adobe-75dpi/src"
DEST="${PRODUCT_OUT}/stage-x11-fonts/75dpi"

[ -f "${SRC}/symb12.bdf" ] || {
	echo "✗ missing font-adobe-75dpi source; run: make fetch PROFILE=desktop" >&2
	exit 1
}
mkdir -p "$DEST"
install -m 0644 "${SRC}/symb12.bdf" "${DEST}/symb12.bdf"
echo "✓ Adobe Symbol 12pt font OK → ${DEST}"
