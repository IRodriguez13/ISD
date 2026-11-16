#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Build static musl GNU make for in-guest IR0 toolchain use.
# Output: $PRODUCT_OUT/stage-bin/make
set -euo pipefail
JOBS="${ISD_JOBS:-2}"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/toolchain.sh"
PKG="${ROOT}/packages/gnumake"
SRC="${PKG}/src"
OUT_DIR="${PRODUCT_OUT}/stage-bin"
VER="$(cat "${PKG}/version")"

if [ ! -d "$SRC" ]; then
	echo "✗ missing gnumake source; run: make fetch" >&2
	exit 1
fi

mkdir -p "$OUT_DIR"
cd "$SRC"

echo "  GMAKE   Configuring make-${VER} static (${TARGET_TRIPLE})..."
make distclean >/dev/null 2>&1 || true
cfg_log="${PKG}/configure-${ARCH}.log"
if ! CC="$CC" \
	CFLAGS="-static -Os -fno-pie" \
	LDFLAGS="-static -no-pie" \
	./configure \
	--host="${TARGET_TRIPLE}" \
	--prefix=/usr \
	--disable-nls \
	--without-guile \
	>"${cfg_log}" 2>&1; then
	cat "${cfg_log}" >&2
	exit 1
fi

echo "  GMAKE   Building..."
make -s -j"$JOBS"

if [ -x make ]; then
	install -m 0755 make "${OUT_DIR}/make"
elif [ -x make/make ]; then
	install -m 0755 make/make "${OUT_DIR}/make"
else
	echo "✗ make binary missing after build" >&2
	exit 1
fi

file "${OUT_DIR}/make" | grep -q ELF
if file "${OUT_DIR}/make" | grep -q dynamically; then
	echo "⚠ gnumake is dynamically linked (unexpected for musl -static)" >&2
	ldd "${OUT_DIR}/make" || true
fi
echo "✓ gnumake OK → ${OUT_DIR}/make"
