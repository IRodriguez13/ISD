#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export XORG_EXTRA_LIBS="-lxcb -lXau -lXdmcp"
# Generate the MIT-MAGIC-COOKIE locally from the kernel RNG using BusyBox
# applets already guaranteed by every ISD profile; no host /usr/bin/mcookie
# path may leak into the guest script.
export MCOOKIE="/bin/od -An -N16 -tx1 /dev/urandom | /bin/tr -d ' \\n'"
"$ROOT/scripts/build-xorg-autotools.sh" xinit --with-xinitdir=/etc/X11/xinit
mkdir -p "$PRODUCT_OUT/stage-bin" "$PRODUCT_OUT/stage-scripts"
install -m 0755 "$ROOT/packages/xinit/prefix/$ARCH/usr/bin/xinit" "$PRODUCT_OUT/stage-bin/xinit"
install -m 0755 "$ROOT/packages/xinit/prefix/$ARCH/usr/bin/startx" "$PRODUCT_OUT/stage-scripts/startx"
