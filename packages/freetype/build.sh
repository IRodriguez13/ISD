#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "${ROOT}/scripts/toolchain.sh"
PKG="${ROOT}/packages/freetype"
PREFIX="${PKG}/prefix/${ARCH}"
[ -d "${PKG}/src" ] || { echo "✗ missing freetype source; run: make fetch PROFILE=desktop" >&2; exit 1; }
mkdir -p "$PREFIX"
cd "${PKG}/src"
make distclean >/dev/null 2>&1 || true
CC="$CC" AR="$AR" RANLIB="$RANLIB" CFLAGS="-Os -fno-pie" LDFLAGS="-static -no-pie" \
./configure --prefix=/usr --host="$TARGET_TRIPLE" --disable-shared --enable-static \
  --without-zlib --without-bzip2 --without-png --without-harfbuzz --without-brotli
make -s -j"$(nproc)"
make -s DESTDIR="$PREFIX" install
find "$PREFIX/usr/lib" -maxdepth 1 -name '*.la' -delete
test -f "$PREFIX/usr/lib/libfreetype.a"
echo "✓ freetype OK → $PREFIX"
