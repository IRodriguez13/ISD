#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export XORG_EXTRA_LIBS="-Wl,--start-group -lXaw -lXmu -lXpm -lXt -lSM -lICE -lXext -lX11 -lxcb -lXau -lXdmcp -lncurses -Wl,--end-group"
"$ROOT/scripts/build-xorg-autotools.sh" xterm \
	--enable-wide-chars --disable-toolbar --disable-freetype \
	--disable-luit --disable-sixel-graphics --with-app-defaults=/etc/X11/app-defaults
mkdir -p "$PRODUCT_OUT/stage-bin"
install -m 0755 "$ROOT/packages/xterm/prefix/$ARCH/usr/bin/xterm" \
	"$PRODUCT_OUT/stage-bin/xterm"
