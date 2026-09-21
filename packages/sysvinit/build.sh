#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/toolchain.sh"
PKG="${ROOT}/packages/sysvinit"
SRC_DIR="${PKG}/src/src"
OUT_DIR="${PRODUCT_OUT:-${ROOT}/out/${ARCH}/product}/bin"

if [ ! -f "$SRC_DIR/init.c" ]; then
	echo "✗ missing sysvinit source; run: make fetch" >&2
	exit 1
fi

mkdir -p "$OUT_DIR"
echo "  SYSVINIT Building with $CC (static) ARCH=${ARCH}..."
cd "$SRC_DIR"

make -s clean 2>/dev/null || true
BUILD_CFLAGS="-Os -static -I${PKG}/stubs"
if [ -d "${IR0_UAPI_SYSROOT:-}/usr/include" ]; then
	BUILD_CFLAGS="$BUILD_CFLAGS -isystem ${IR0_UAPI_SYSROOT}/usr/include"
fi
make -s CC="$CC" CFLAGS="$BUILD_CFLAGS" LDFLAGS="-static" init shutdown

for bin in init shutdown; do
	install -m 0755 "$bin" "$OUT_DIR/$bin"
	file "$OUT_DIR/$bin" | grep -q ELF
done
ln -sf shutdown "$OUT_DIR/halt"
ln -sf shutdown "$OUT_DIR/reboot"

echo "✓ build sysvinit OK (init shutdown halt→shutdown reboot→shutdown)"
