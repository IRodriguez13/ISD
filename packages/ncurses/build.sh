#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Build static ncurses (narrowc) + terminfo database for xterm/ash/nano.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/toolchain.sh"
PKG="${ROOT}/packages/ncurses"
SRC="${PKG}/src"
PREFIX="${PKG}/prefix/${ARCH}"
terminfo_mark="${PREFIX}/share/terminfo/x/xterm"
if [ ! -f "$terminfo_mark" ] && [ -f "${PREFIX}/usr/share/terminfo/x/xterm" ]; then
	terminfo_mark="${PREFIX}/usr/share/terminfo/x/xterm"
fi

if [ ! -d "$SRC" ]; then
	echo "✗ missing ncurses source; run: make fetch" >&2
	exit 1
fi

if [ -f "${PREFIX}/lib/libncurses.a" ] && [ -f "${PREFIX}/include/ncurses.h" ] \
	&& [ -f "$terminfo_mark" ]; then
	echo "✓ ncurses already installed → ${PREFIX}"
	exit 0
fi

mkdir -p "$PREFIX"
cd "$SRC"

echo "  NCURSES Configuring $(cat "$PKG/version") (static + terminfo)..."
make distclean >/dev/null 2>&1 || true
cfg_log="${PKG}/configure-${ARCH}.log"
if ! CC="$CC" CFLAGS="-Os -fno-pie" LDFLAGS="-static -no-pie" \
	./configure \
	--prefix=/usr \
	--host="${TARGET_TRIPLE}" \
	--with-build-cc=gcc \
	--without-shared \
	--with-normal \
	--without-debug \
	--without-ada \
	--without-cxx \
	--without-cxx-binding \
	--without-progs \
	--without-tests \
	--without-manpages \
	--with-fallbacks=linux,vt100,xterm,screen \
	--disable-widec \
	--enable-termcap \
	>"${cfg_log}" 2>&1; then
	cat "${cfg_log}" >&2
	exit 1
fi

echo "  NCURSES Building..."
make -s -j"$(nproc)"
make -s DESTDIR="${PREFIX}" install.libs install.includes install.data
# DESTDIR+/usr → flatten for consumers
if [ -d "${PREFIX}/usr" ]; then
	mkdir -p "${PREFIX}/lib" "${PREFIX}/include" "${PREFIX}/share"
	cp -a "${PREFIX}/usr/lib/." "${PREFIX}/lib/" 2>/dev/null || true
	cp -a "${PREFIX}/usr/include/." "${PREFIX}/include/" 2>/dev/null || true
	if [ -d "${PREFIX}/usr/share/terminfo" ]; then
		cp -a "${PREFIX}/usr/share/terminfo" "${PREFIX}/share/"
	fi
fi

test -f "${PREFIX}/lib/libncurses.a" || test -f "${PREFIX}/usr/lib/libncurses.a"
test -f "${PREFIX}/share/terminfo/x/xterm" \
	|| test -f "${PREFIX}/usr/share/terminfo/x/xterm" \
	|| { echo "✗ terminfo database missing after ncurses install" >&2; exit 1; }
echo "✓ build ncurses OK → ${PREFIX}"
