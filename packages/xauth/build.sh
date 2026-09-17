#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export XORG_EXTRA_LIBS="-lXmuu -lXt -lSM -lICE -lXext -lX11 -lxcb -lXau -lXdmcp"
"$ROOT/scripts/build-xorg-autotools.sh" xauth
mkdir -p "$PRODUCT_OUT/stage-bin"
install -m 0755 "$ROOT/packages/xauth/prefix/$ARCH/usr/bin/xauth" "$PRODUCT_OUT/stage-bin/xauth"
