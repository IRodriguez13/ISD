#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Build GNU nano (tiny) static musl against packages/ncurses.

set -euo pipefail
JOBS="${ISD_JOBS:-2}"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/toolchain.sh"
PKG="${ROOT}/packages/nano"
SRC="${PKG}/src"
NCURSES_PREFIX="${ROOT}/packages/ncurses/prefix/${ARCH}"
OUT_DIR="${PRODUCT_OUT}/stage-bin"
if [ ! -d "$SRC" ]; then
	echo "✗ missing nano source; run: make fetch" >&2
	exit 1
fi

# Ensure ncurses is built first.
chmod +x "${ROOT}/packages/ncurses/build.sh"
"${ROOT}/packages/ncurses/build.sh"

LIBDIR="${NCURSES_PREFIX}/lib"
INCDIR="${NCURSES_PREFIX}/include"
if [ ! -f "${LIBDIR}/libncurses.a" ] && [ -f "${NCURSES_PREFIX}/usr/lib/libncurses.a" ]; then
	LIBDIR="${NCURSES_PREFIX}/usr/lib"
	INCDIR="${NCURSES_PREFIX}/usr/include"
fi
if [ ! -f "${LIBDIR}/libncurses.a" ]; then
	echo "✗ libncurses.a missing under ${NCURSES_PREFIX}" >&2
	exit 1
fi
# nano/pkg-config often wants -ltinfo; narrowc folds terminfo into ncurses.
if [ ! -e "${LIBDIR}/libtinfo.a" ]; then
	ln -sf libncurses.a "${LIBDIR}/libtinfo.a"
fi

mkdir -p "$OUT_DIR"
cd "$SRC"

# musl bits/vt.h → #include <linux/vt.h>; host UAPI via -idirafter.
NANO_CPPFLAGS="-I${INCDIR} -idirafter /usr/include"
NANO_CFLAGS="-Os -fno-pie ${NANO_CPPFLAGS}"
NANO_LDFLAGS="-static -no-pie -L${LIBDIR}"

NANO_VER=$(cat "${PKG}/version")
echo "  NANO    Configuring ${NANO_VER} tiny static..."
make distclean >/dev/null 2>&1 || true
cfg_log="${PKG}/configure-${ARCH}.log"
if ! CC="$CC" \
	CFLAGS="$NANO_CFLAGS" \
	CPPFLAGS="$NANO_CPPFLAGS" \
	LDFLAGS="$NANO_LDFLAGS" \
	LIBS="-lncurses" \
	./configure \
	--host="${TARGET_TRIPLE}" \
	--prefix=/usr \
	--enable-tiny \
	--disable-nls \
	--disable-libmagic \
	--enable-utf8=no \
	>"${cfg_log}" 2>&1; then
	cat "${cfg_log}" >&2
	exit 1
fi

echo "  NANO    Building lib + src..."
make -s -j"$JOBS" -C lib \
	CFLAGS="$NANO_CFLAGS" \
	CPPFLAGS="$NANO_CPPFLAGS"
make -s -j"$JOBS" -C src \
	CFLAGS="$NANO_CFLAGS" \
	CPPFLAGS="$NANO_CPPFLAGS" \
	LDFLAGS="$NANO_LDFLAGS"
install -m 0755 src/nano "$OUT_DIR/nano"
file "$OUT_DIR/nano" | grep -q ELF
if file "$OUT_DIR/nano" | grep -q dynamically; then
	echo "⚠ nano is dynamically linked (unexpected for musl -static)" >&2
	ldd "$OUT_DIR/nano" || true
fi
strip "$OUT_DIR/nano" 2>/dev/null || true
echo "✓ build nano OK → $OUT_DIR/nano ($(wc -c < "$OUT_DIR/nano") bytes)"
