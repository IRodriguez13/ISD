#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "${ROOT}/scripts/toolchain.sh"
PKG="${ROOT}/packages/zlib"
PREFIX="${PKG}/prefix/${ARCH}/usr"
[ -d "${PKG}/src" ] || { echo "✗ missing zlib source; run: make fetch PROFILE=desktop" >&2; exit 1; }
mkdir -p "$PREFIX"
cd "${PKG}/src"
make distclean >/dev/null 2>&1 || true
CHOST="$TARGET_TRIPLE" CC="$CC" AR="$AR" RANLIB="$RANLIB" CFLAGS="-Os -fno-pie" \
./configure --static --prefix=/usr
make -s -j"$(nproc)" libz.a
mkdir -p "$PREFIX/lib/pkgconfig" "$PREFIX/include"
install -m 0644 libz.a "$PREFIX/lib/libz.a"
install -m 0644 zlib.h zconf.h "$PREFIX/include/"
sed -e "s|^prefix=.*|prefix=$PREFIX|" zlib.pc >"$PREFIX/lib/pkgconfig/zlib.pc"
echo "✓ zlib OK → $PREFIX"
