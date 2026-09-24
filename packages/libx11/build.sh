#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ARCH="${ARCH:-x86_64}"
KEYSYM_DIR="$ROOT/packages/xorgproto/prefix/$ARCH/usr/include/X11"
exec "$ROOT/scripts/build-xorg-autotools.sh" libx11 \
  --with-keysymdefdir="$KEYSYM_DIR" --without-xmlto --disable-specs
