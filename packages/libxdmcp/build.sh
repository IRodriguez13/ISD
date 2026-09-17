#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "${ROOT}/scripts/toolchain.sh"
PKG="${ROOT}/packages/libxdmcp"
PREFIX="${PKG}/prefix/${ARCH}"
PROTO="${ROOT}/packages/xorgproto/prefix/${ARCH}/usr"
[ -d "${PKG}/src" ] || { echo "✗ missing libXdmcp source; run: make fetch PROFILE=desktop" >&2; exit 1; }
mkdir -p "$PREFIX"
cd "${PKG}/src"
make distclean >/dev/null 2>&1 || true
PKG_CONFIG_LIBDIR="$PROTO/lib/pkgconfig:$PROTO/share/pkgconfig" \
CC="$CC" AR="$AR" RANLIB="$RANLIB" CPPFLAGS="-I$PROTO/include" \
CFLAGS="-Os -fno-pie" LDFLAGS="-static -no-pie" \
./configure --prefix=/usr --host="$TARGET_TRIPLE" --disable-shared --enable-static --disable-docs
make -s -j"$(nproc)"
make -s DESTDIR="$PREFIX" install
find "$PREFIX/usr/lib" -maxdepth 1 -name '*.la' -delete
test -f "$PREFIX/usr/lib/libXdmcp.a"
echo "✓ libXdmcp OK → $PREFIX"
