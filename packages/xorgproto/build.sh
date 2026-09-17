#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "${ROOT}/scripts/toolchain.sh"
PKG="${ROOT}/packages/xorgproto"
PREFIX="${PKG}/prefix/${ARCH}"
[ -d "${PKG}/src" ] || { echo "✗ missing xorgproto source; run: make fetch PROFILE=desktop" >&2; exit 1; }
mkdir -p "$PREFIX"
cd "${PKG}/src"
make distclean >/dev/null 2>&1 || true
./configure --prefix=/usr --host="$TARGET_TRIPLE" --disable-specs
make -s -j"$(nproc)"
make -s DESTDIR="$PREFIX" install
test -f "$PREFIX/usr/include/X11/Xproto.h"
echo "✓ xorgproto OK → $PREFIX"
