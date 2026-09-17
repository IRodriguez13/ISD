#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export XORG_EXTRA_LIBS="-Wl,--start-group -lXaw -lXmu -lXpm -lXt -lSM -lICE -lXext -lX11 -lxcb -lXau -lXdmcp -Wl,--end-group"
"$ROOT/scripts/build-xorg-autotools.sh" xclock \
	--without-xft --without-xkb
mkdir -p "$PRODUCT_OUT/stage-bin"
install -m 0755 "$ROOT/packages/xclock/prefix/$ARCH/usr/bin/xclock" \
	"$PRODUCT_OUT/stage-bin/xclock"
