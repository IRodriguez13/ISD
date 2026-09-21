#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "${ROOT}/scripts/toolchain.sh"
name="${1:?package name required}"
shift
PKG="${ROOT}/packages/${name}"
PREFIX="${PKG}/prefix/${ARCH}"
[ -d "${PKG}/src" ] || { echo "✗ missing ${name} source; run: make fetch PROFILE=desktop" >&2; exit 1; }

chmod +x "${ROOT}/scripts/apply-isd-patches.sh"
"${ROOT}/scripts/apply-isd-patches.sh" "${name}"

deps="$(sed -n 's/^DEPENDS=//p' "${PKG}/package.conf")"
pc=""
cpp="-I${SYSROOT}/usr/include"
ld=""
for dep in $deps; do
	base="${ROOT}/packages/${dep}/prefix/${ARCH}/usr"
	pc="${pc:+$pc:}$base/lib/pkgconfig:$base/share/pkgconfig"
	cpp="$cpp -I$base/include"
	ld="$ld -L$base/lib"
done

# pkg-config must resolve transitive Requires entries (for example xau →
# xproto). Expose only package prefixes produced by ISD, never host .pc files.
for libdir in "${ROOT}"/packages/*/prefix/"${ARCH}"/usr/lib/pkgconfig \
	"${ROOT}"/packages/*/prefix/"${ARCH}"/usr/share/pkgconfig; do
	[ -d "$libdir" ] || continue
	pc="${pc:+$pc:}$libdir"
done
for pkgroot in "${ROOT}"/packages/*/prefix/"${ARCH}"/usr; do
	[ -d "$pkgroot" ] || continue
	[ ! -d "$pkgroot/include" ] || cpp="$cpp -I$pkgroot/include"
	[ ! -d "$pkgroot/lib" ] || ld="$ld -L$pkgroot/lib"
done

pythonpath=""
for pydir in "${ROOT}"/packages/xcb-proto/prefix/"${ARCH}"/usr/local/lib/python*/dist-packages; do
	[ -d "$pydir" ] || continue
	pythonpath="${pythonpath:+$pythonpath:}$pydir"
done

mkdir -p "$PREFIX"
cd "${PKG}/src"
make distclean >/dev/null 2>&1 || true
PKG_CONFIG_LIBDIR="$pc" PYTHONPATH="$pythonpath" \
	CC="$CC" AR="$AR" RANLIB="$RANLIB" \
	CPPFLAGS="$cpp" CFLAGS="-Os -fno-pie" LDFLAGS="-static -no-pie $ld" \
	LIBS="${XORG_EXTRA_LIBS:-}" \
	./configure --prefix=/usr --host="$TARGET_TRIPLE" \
		--disable-shared --enable-static "$@"
make -s -j"$(nproc)"
make -s DESTDIR="$PREFIX" install
find "$PREFIX/usr/lib" -maxdepth 1 -name '*.la' -delete 2>/dev/null || true
echo "✓ ${name} OK → ${PREFIX}"
