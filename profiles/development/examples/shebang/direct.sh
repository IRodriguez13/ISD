#!/bin/sh

[ "$1" = "alpha" ] || exit 41
[ "$2" = "beta" ] || exit 42
echo SHEBANG_SH_ARGV_OK
