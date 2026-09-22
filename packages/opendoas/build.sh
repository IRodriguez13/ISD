#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/toolchain.sh"
PKG="${ROOT}/packages/opendoas"
SRC="${PKG}/src"
OUT_DIR="${PRODUCT_OUT:-${ROOT}/out/${ARCH}/product}/stage-bin"
LOG="${PKG}/configure-${ARCH}.log"

if [ ! -d "$SRC" ]; then
	echo "✗ missing OpenDoas source; run: make fetch" >&2
	exit 1
fi

mkdir -p "$OUT_DIR"
cd "$SRC"

echo "  DOAS    Configuring OpenDoas $(cat "$PKG/version") host=${TARGET_TRIPLE}..."
# Do not pass --host: OpenDoas's configure probes the build CC directly;
# TARGET_TRIPLE is already encoded in $CC from scripts/toolchain.sh.
if ! CC="$CC" CFLAGS="-static -Os -fno-pie" LDFLAGS="-static -no-pie" \
	./configure --prefix=/usr --sysconfdir=/etc \
	--without-pam --with-timestamp --enable-static >"$LOG" 2>&1; then
	cat "$LOG" >&2
	exit 1
fi
if grep -q -- '-lcrypt' config.mk; then
	sed -i 's/LDLIBS +=	-lcrypt/LDLIBS +=/' config.mk
fi

make clean >/dev/null 2>&1 || true
make -s CC="$CC" CFLAGS="-static -Os -fno-pie" LDFLAGS="-static -no-pie"
install -m 04755 doas "$OUT_DIR/doas"
file "$OUT_DIR/doas" | grep -q ELF
echo "✓ build opendoas OK → $OUT_DIR/doas"
