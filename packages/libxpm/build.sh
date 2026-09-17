#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export XORG_EXTRA_LIBS="-Wl,--start-group -lXt -lSM -lICE -lXext -lX11 -lxcb -lXau -lXdmcp -Wl,--end-group"
exec "$ROOT/scripts/build-xorg-autotools.sh" libxpm --disable-open-zfile
