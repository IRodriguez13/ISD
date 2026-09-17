#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
"$ROOT/scripts/build-xorg-autotools.sh" xcb-proto
pc="$ROOT/packages/xcb-proto/prefix/${ARCH:-x86_64}/usr/share/pkgconfig/xcb-proto.pc"
sed -i "s|^prefix=/usr$|prefix=$ROOT/packages/xcb-proto/prefix/${ARCH:-x86_64}/usr|" "$pc"
