#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export XORG_EXTRA_LIBS="-lXmu -lXt -lSM -lICE -lXext -lX11 -lxcb -lXau -lXdmcp"
"$ROOT/scripts/build-xorg-autotools.sh" twm
mkdir -p "$PRODUCT_OUT/stage-bin"
install -m 0755 "$ROOT/packages/twm/prefix/$ARCH/usr/bin/twm" \
	"$PRODUCT_OUT/stage-bin/twm"
