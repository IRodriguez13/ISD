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
# zlib's configure links its vsnprintf probe using CFLAGS only.  On PIE-by-
# default hosts, -fno-pie without -no-pie makes that probe fail at link time
# and silently enables the unsafe NO_vsnprintf/vsprintf fallback.
CHOST="$TARGET_TRIPLE" CC="$CC" AR="$AR" RANLIB="$RANLIB" \
CFLAGS="-Os -fno-pie -no-pie" \
./configure --static --prefix=/usr
grep -q 'Checking for vsnprintf() in stdio.h... Yes.' configure.log || {
	echo "✗ zlib refused: secure vsnprintf probe failed" >&2
	exit 1
}
if grep -q -- '-DNO_vsnprintf' configure.log; then
	echo "✗ zlib refused: configure selected unsafe vsprintf fallback" >&2
	exit 1
fi
make -s -j"$(nproc)" libz.a
mkdir -p "$PREFIX/lib/pkgconfig" "$PREFIX/include"
install -m 0644 libz.a "$PREFIX/lib/libz.a"
install -m 0644 zlib.h zconf.h "$PREFIX/include/"
sed -e "s|^prefix=.*|prefix=$PREFIX|" zlib.pc >"$PREFIX/lib/pkgconfig/zlib.pc"
echo "✓ zlib OK → $PREFIX"
