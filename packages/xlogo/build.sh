#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export XORG_EXTRA_LIBS="-Wl,--start-group -lXaw -lXmu -lXpm -lXt -lSM -lICE -lXext -lXrender -lX11 -lxcb -lXau -lXdmcp -Wl,--end-group"
"$ROOT/scripts/build-xorg-autotools.sh" xlogo
mkdir -p "$PRODUCT_OUT/stage-bin"
install -m 0755 "$ROOT/packages/xlogo/prefix/$ARCH/usr/bin/xlogo" \
	"$PRODUCT_OUT/stage-bin/xlogo"
