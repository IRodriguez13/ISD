#!/bin/busybox ash

[ "$1" = "alpha" ] || exit 51
[ "$2" = "beta" ] || exit 52
echo SHEBANG_BUSYBOX_ARGV_OK
