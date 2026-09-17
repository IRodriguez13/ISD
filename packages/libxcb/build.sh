#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export XCBPROTO_XCBINCLUDEDIR="$ROOT/packages/xcb-proto/prefix/${ARCH:-x86_64}/usr/share/xcb"
export XCBPROTO_XCBPYTHONDIR="$ROOT/packages/xcb-proto/prefix/${ARCH:-x86_64}/usr/local/lib/python3.12/dist-packages"
exec "$ROOT/scripts/build-xorg-autotools.sh" libxcb --without-doxygen
