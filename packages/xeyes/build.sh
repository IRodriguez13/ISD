#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export XORG_EXTRA_LIBS="-Wl,--start-group -lXmu -lXt -lSM -lICE -lXext -lXrender -lX11 -lxcb -lXau -lXdmcp -Wl,--end-group"
"$ROOT/scripts/build-xorg-autotools.sh" xeyes
mkdir -p "$PRODUCT_OUT/stage-bin"
install -m 0755 "$ROOT/packages/xeyes/prefix/$ARCH/usr/bin/xeyes" \
	"$PRODUCT_OUT/stage-bin/xeyes"
