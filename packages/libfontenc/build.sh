#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "${ROOT}/scripts/toolchain.sh"
PKG="${ROOT}/packages/libfontenc"
PREFIX="${PKG}/prefix/${ARCH}"
PROTO="${ROOT}/packages/xorgproto/prefix/${ARCH}/usr"
ZLIB="${ROOT}/packages/zlib/prefix/${ARCH}/usr"
[ -d "${PKG}/src" ] || { echo "✗ missing libfontenc source; run: make fetch PROFILE=desktop" >&2; exit 1; }
mkdir -p "$PREFIX"
cd "${PKG}/src"
make distclean >/dev/null 2>&1 || true
PKG_CONFIG_LIBDIR="$PROTO/lib/pkgconfig:$PROTO/share/pkgconfig:$ZLIB/lib/pkgconfig" \
CC="$CC" AR="$AR" RANLIB="$RANLIB" CPPFLAGS="-I$PROTO/include -I$ZLIB/include" \
CFLAGS="-Os -fno-pie" LDFLAGS="-static -no-pie -L$ZLIB/lib" \
./configure --prefix=/usr --host="$TARGET_TRIPLE" --disable-shared --enable-static
make -s -j"$(nproc)"
make -s DESTDIR="$PREFIX" install
find "$PREFIX/usr/lib" -maxdepth 1 -name '*.la' -delete
test -f "$PREFIX/usr/lib/libfontenc.a"
echo "✓ libfontenc OK → $PREFIX"
