#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export XORG_EXTRA_LIBS="-Wl,--start-group -lXaw -lXmu -lXpm -lXt -lSM -lICE -lXext -lX11 -lxcb -lXau -lXdmcp -Wl,--end-group"
"$ROOT/scripts/build-xorg-autotools.sh" xmessage
mkdir -p "$PRODUCT_OUT/stage-bin"
install -m 0755 "$ROOT/packages/xmessage/prefix/$ARCH/usr/bin/xmessage" \
	"$PRODUCT_OUT/stage-bin/xmessage"
