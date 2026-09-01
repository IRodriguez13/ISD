#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Build static musl pack + unpack (libarchive + zlib) → stage-bin/{pack,unpack}
#
# Compression filters beyond gzip require extra libs; this build links zlib-only
# so tar / tar.gz / gz / zip work. Other formats fail at runtime with libarchive
# errors (honest ENOSYS-like behavior vs silent stubs).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/toolchain.sh"
PKG="${ROOT}/packages/pack-extract"
SRC="${PKG}/src"
DEPS="${PKG}/deps"
PREFIX="${PKG}/prefix/${ARCH}"
OUT_DIR="${PRODUCT_OUT}/stage-bin"
JOBS="${ISD_BUILD_JOBS:-$(nproc 2>/dev/null || echo 2)}"

if [ ! -f "${SRC}/src/pack.c" ] || [ ! -d "${DEPS}/zlib" ] || [ ! -d "${DEPS}/libarchive" ]; then
	echo "✗ missing pack-unpack sources/deps; run: make fetch" >&2
	exit 1
fi

mkdir -p "$OUT_DIR" "$PREFIX"

# --- zlib (static) ---
if [ ! -f "${PREFIX}/lib/libz.a" ]; then
	echo "  PACK    Building zlib static (${TARGET_TRIPLE})..."
	(
		cd "${DEPS}/zlib"
		make distclean >/dev/null 2>&1 || true
		# Library objects only — skip example/minigzip (PIE vs -fno-pie clash).
		CHOST="${TARGET_TRIPLE}" CC="$CC" AR="$AR" RANLIB="$RANLIB" \
			CFLAGS="-Os" \
			./configure --static --prefix="$PREFIX"
		make -j"$JOBS" libz.a
		mkdir -p "${PREFIX}/lib" "${PREFIX}/include" "${PREFIX}/lib/pkgconfig"
		cp -a libz.a "${PREFIX}/lib/"
		cp -a zlib.h zconf.h "${PREFIX}/include/"
		# Minimal pkg-config for libarchive configure.
		cat >"${PREFIX}/lib/pkgconfig/zlib.pc" <<EOF
prefix=${PREFIX}
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: zlib
Description: zlib compression library
Version: ${ZLIB_VER:-1.3.1}
Libs: -L\${libdir} -lz
Cflags: -I\${includedir}
EOF
	)
fi
[ -f "${PREFIX}/lib/libz.a" ] || {
	echo "✗ zlib install failed" >&2
	exit 1
}

# --- libarchive (static, zlib only) ---
if [ ! -f "${PREFIX}/lib/libarchive.a" ]; then
	echo "  PACK    Building libarchive static (${TARGET_TRIPLE})..."
	(
		cd "${DEPS}/libarchive"
		make distclean >/dev/null 2>&1 || true
		# Fresh out-of-tree build dir keeps source clean across arches.
		rm -rf "${PKG}/build-libarchive-${ARCH}"
		mkdir -p "${PKG}/build-libarchive-${ARCH}"
		cd "${PKG}/build-libarchive-${ARCH}"
		export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
		export CPPFLAGS="-I${PREFIX}/include"
		export LDFLAGS="-L${PREFIX}/lib -static"
		export CFLAGS="-Os -fno-pie ${CPPFLAGS}"
		"${DEPS}/libarchive/configure" \
			--host="${TARGET_TRIPLE}" \
			--prefix="$PREFIX" \
			--disable-shared \
			--enable-static \
			--disable-bsdtar \
			--disable-bsdcat \
			--disable-bsdcpio \
			--disable-bsdunzip \
			--without-bz2lib \
			--without-libb2 \
			--without-iconv \
			--without-lz4 \
			--without-zstd \
			--without-lzma \
			--without-lzo2 \
			--without-cng \
			--without-nettle \
			--without-openssl \
			--without-xml2 \
			--without-expat \
			--with-zlib \
			CC="$CC" AR="$AR" RANLIB="$RANLIB"
		make -j"$JOBS"
		make install
	)
fi
[ -f "${PREFIX}/lib/libarchive.a" ] || {
	echo "✗ libarchive install failed" >&2
	exit 1
}

# --- pack + unpack ---
echo "  PACK    Building pack/unpack (${TARGET_TRIPLE})..."
cd "$SRC"
make clean >/dev/null 2>&1 || true
PE_VER="$(tr -d '[:space:]' < VERSION)"
# Upstream appends -Iinclude and -DPACK_UNPACK_VERSION through `override CFLAGS +=`,
# so a command-line CFLAGS no longer drops them (that was the 1.5.2 workaround).
make -s all \
	CC="$CC" \
	CFLAGS="-Wall -Wextra -Os -fno-pie -static -I${PREFIX}/include -DPATH_MAX=4096" \
	ARCHIVE_CFLAGS="-I${PREFIX}/include" \
	ARCHIVE_LIBS="-L${PREFIX}/lib -larchive -lz" \
	LDFLAGS="-static -no-pie -L${PREFIX}/lib" \
	LDLIBS="-larchive -lz" \
	PKG_CONFIG=/bin/false

install -m 0755 build/pack "${OUT_DIR}/pack"
install -m 0755 build/unpack "${OUT_DIR}/unpack"
# `extract` was the 1.5.x name; keep it so existing rootfs paths and habits work.
install -m 0755 build/unpack "${OUT_DIR}/extract"
file "${OUT_DIR}/pack" | grep -q ELF
file "${OUT_DIR}/unpack" | grep -q ELF

# Prefer fully static; warn if dynamic (should not happen with -static musl).
for b in pack unpack extract; do
	if file "${OUT_DIR}/${b}" | grep -q dynamically; then
		echo "⚠ ${b} is dynamically linked" >&2
		ldd "${OUT_DIR}/${b}" || true
	fi
done

echo "✓ pack-unpack ${PE_VER} OK → ${OUT_DIR}/{pack,unpack,extract}"
