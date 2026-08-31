#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Build static musl iv (line-oriented editor) → $PRODUCT_OUT/stage-bin/iv
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/toolchain.sh"
PKG="${ROOT}/packages/iv"
SRC="${PKG}/src"
OUT_DIR="${PRODUCT_OUT}/stage-bin"

if [ ! -f "${SRC}/main.c" ]; then
	echo "✗ missing iv source; run: make fetch" >&2
	exit 1
fi

mkdir -p "$OUT_DIR"
cd "$SRC"

echo "  IV      Building static (${TARGET_TRIPLE})..."
make clean >/dev/null 2>&1 || true
make -s CC="$CC" \
	CFLAGS="-Wall -Wextra -Os -fno-pie -static" \
	LDFLAGS="-static -no-pie"

install -m 0755 iv "${OUT_DIR}/iv"
file "${OUT_DIR}/iv" | grep -q ELF
if file "${OUT_DIR}/iv" | grep -q dynamically; then
	echo "⚠ iv is dynamically linked (unexpected for musl -static)" >&2
	ldd "${OUT_DIR}/iv" || true
fi
echo "✓ iv OK → ${OUT_DIR}/iv"
