#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "${ROOT}/scripts/toolchain.sh"
PKG="${ROOT}/packages/tinyx"
SRC="${PKG}/src"
DEPS=(xorgproto xtrans libxau libxdmcp libx11 libxext libxi libxtst zlib freetype libfontenc libxfont)
pc=""
cpp="-I${SYSROOT}/usr/include"
ld=""
for dep in "${DEPS[@]}"; do
  base="${ROOT}/packages/${dep}/prefix/${ARCH}/usr"
  pc="${pc:+$pc:}$base/lib/pkgconfig:$base/share/pkgconfig"
  cpp="$cpp -I$base/include"
  ld="$ld -L$base/lib"
done
[ -d "$SRC" ] || { echo "✗ missing TinyX source; run: make fetch PROFILE=desktop" >&2; exit 1; }
mkdir -p "${PRODUCT_OUT}/stage-bin"
cd "$SRC"
if [ ! -x configure ]; then
  ACLOCAL_PATH="${ROOT}/packages/xtrans/prefix/${ARCH}/usr/share/aclocal" autoreconf -fi
fi
make distclean >/dev/null 2>&1 || true
PKG_CONFIG_LIBDIR="$pc" ACLOCAL_PATH="${ROOT}/packages/xtrans/prefix/${ARCH}/usr/share/aclocal" \
CC="$CC" AR="$AR" RANLIB="$RANLIB" CPPFLAGS="$cpp" CFLAGS="-Os -fno-pie" \
LDFLAGS="-static -no-pie $ld" \
FREETYPE_CFLAGS="-I${ROOT}/packages/freetype/prefix/${ARCH}/usr/include/freetype2" \
FREETYPE_LIBS="-lfreetype" \
LIBS="-lfreetype -lfontenc -lXau -lXdmcp -lm" \
./configure --prefix=/usr --host="$TARGET_TRIPLE" --enable-kdrive --enable-xfbdev \
  --disable-xvesa --disable-xdmcp --disable-xdm-auth-1 --disable-install-setuid \
  --disable-xres --disable-screensaver --disable-dbe --disable-xf86bigfont \
  --disable-dpms \
  --with-int10=stub \
  --with-default-font-path=/usr/share/fonts/X11/misc,/usr/share/fonts/X11/75dpi
make -s -j"$(nproc)" \
  LDFLAGS="-all-static -no-pie $ld" \
  LIBS="-lfreetype -lfontenc -lz -lXau -lXdmcp -lm"
server="$(find . -type f -name Xfbdev -perm -u+x | head -1)"
[ -n "$server" ] || { echo "✗ TinyX build did not produce Xfbdev" >&2; exit 1; }
install -m 0755 "$server" "${PRODUCT_OUT}/stage-bin/Xfbdev"
echo "✓ TinyX Xfbdev OK → ${PRODUCT_OUT}/stage-bin/Xfbdev"
