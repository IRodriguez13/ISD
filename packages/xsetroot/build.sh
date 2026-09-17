#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export XORG_EXTRA_LIBS="-Wl,--start-group -lXmuu -lXmu -lXcursor -lXrender -lXfixes -lXt -lSM -lICE -lXext -lX11 -lxcb -lXau -lXdmcp -Wl,--end-group"
"$ROOT/scripts/build-xorg-autotools.sh" xsetroot
mkdir -p "$PRODUCT_OUT/stage-bin"
install -m 0755 "$ROOT/packages/xsetroot/prefix/$ARCH/usr/bin/xsetroot" \
	"$PRODUCT_OUT/stage-bin/xsetroot"
