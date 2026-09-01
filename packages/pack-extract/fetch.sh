#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Fetch pack/unpack sources from sibling ../pack-unpack + zlib/libarchive deps.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PKG="$(cd "$(dirname "$0")" && pwd)"
# Upstream renamed the project pack-unpack and moved sources under src/ in
# 1.6.0; PACK_EXTRACT_ROOT still works for older checkouts.
PE_ROOT="${PACK_UNPACK_ROOT:-${PACK_EXTRACT_ROOT:-${ROOT}/../pack-unpack}}"
SRC="${PKG}/src"
DEPS="${PKG}/deps"
DIST="${PKG}/dist"

ZLIB_VER="${ZLIB_VER:-1.3.1}"
LIBARCHIVE_VER="${LIBARCHIVE_VER:-3.7.7}"
ZLIB_URL="https://github.com/madler/zlib/releases/download/v${ZLIB_VER}/zlib-${ZLIB_VER}.tar.gz"
LIBARCHIVE_URL="https://github.com/libarchive/libarchive/releases/download/v${LIBARCHIVE_VER}/libarchive-${LIBARCHIVE_VER}.tar.gz"

if [ ! -f "${PE_ROOT}/src/pack.c" ] || [ ! -f "${PE_ROOT}/src/unpack.c" ]; then
	echo "✗ pack-unpack: missing src/pack.c or src/unpack.c at ${PE_ROOT}" >&2
	echo "  clone https://github.com/IRodriguez13/pack-unpack" >&2
	exit 1
fi

rm -rf "$SRC"
mkdir -p "$SRC/src" "$SRC/include" "$DIST" "$DEPS"
cp -a "${PE_ROOT}/src/pack.c" "${PE_ROOT}/src/unpack.c" "$SRC/src/"
cp -a "${PE_ROOT}/Makefile" "${PE_ROOT}/VERSION" "$SRC/"
cp -a "${PE_ROOT}/include/." "$SRC/include/"
[ -f "${PE_ROOT}/COPYING" ] && cp -a "${PE_ROOT}/COPYING" "$SRC/"
echo "  FETCH   pack-unpack $(tr -d '[:space:]' < "${PE_ROOT}/VERSION") from ${PE_ROOT}"

fetch_tarball()
{
	local url="$1"
	local name="$2"
	local out="${DIST}/${name}"
	if [ ! -f "$out" ]; then
		echo "  FETCH   ${name}"
		curl -fsSL "$url" -o "$out"
	else
		echo "  FETCH   ${name} (cached)"
	fi
}

unpack_dep()
{
	local tarball="$1"
	local srcroot="$2"
	local dest="$3"
	if [ -d "$dest" ]; then
		echo "  FETCH   $(basename "$dest") already unpacked"
		return 0
	fi
	local tmp
	tmp="$(mktemp -d)"
	tar -xf "$tarball" -C "$tmp"
	[ -d "${tmp}/${srcroot}" ] || {
		echo "✗ missing ${srcroot} in $(basename "$tarball")" >&2
		rm -rf "$tmp"
		exit 1
	}
	mv "${tmp}/${srcroot}" "$dest"
	rm -rf "$tmp"
}

fetch_tarball "$ZLIB_URL" "zlib-${ZLIB_VER}.tar.gz"
fetch_tarball "$LIBARCHIVE_URL" "libarchive-${LIBARCHIVE_VER}.tar.gz"
unpack_dep "${DIST}/zlib-${ZLIB_VER}.tar.gz" "zlib-${ZLIB_VER}" "${DEPS}/zlib"
unpack_dep "${DIST}/libarchive-${LIBARCHIVE_VER}.tar.gz" \
	"libarchive-${LIBARCHIVE_VER}" "${DEPS}/libarchive"

echo "✓ fetch pack-extract OK"
