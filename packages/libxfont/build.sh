#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "${ROOT}/scripts/toolchain.sh"
PKG="${ROOT}/packages/libxfont"
PREFIX="${PKG}/prefix/${ARCH}"
DEPS=(xorgproto xtrans zlib freetype libfontenc)
pc=""
cpp=""
ld=""
for dep in "${DEPS[@]}"; do
  base="${ROOT}/packages/${dep}/prefix/${ARCH}/usr"
  pc="${pc:+$pc:}$base/lib/pkgconfig:$base/share/pkgconfig"
  cpp="$cpp -I$base/include"
  ld="$ld -L$base/lib"
done
[ -d "${PKG}/src" ] || { echo "✗ missing libXfont source; run: make fetch PROFILE=desktop" >&2; exit 1; }
mkdir -p "$PREFIX"
cd "${PKG}/src"
make distclean >/dev/null 2>&1 || true
PKG_CONFIG_LIBDIR="$pc" CC="$CC" AR="$AR" RANLIB="$RANLIB" \
CPPFLAGS="$cpp" LDFLAGS="-static -no-pie $ld" CFLAGS="-Os -fno-pie" \
./configure --prefix=/usr --host="$TARGET_TRIPLE" --disable-shared --enable-static \
  --disable-devel-docs --without-xmlto --without-fop
make -s -j"$(nproc)"
make -s DESTDIR="$PREFIX" install
find "$PREFIX/usr/lib" -maxdepth 1 -name '*.la' -delete
test -f "$PREFIX/usr/lib/libXfont.a"
echo "✓ libXfont OK → $PREFIX"
