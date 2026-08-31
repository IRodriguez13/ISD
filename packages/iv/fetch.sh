#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# iv sources live in sibling ../iv (or IV_ROOT). No tarball fetch.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
IV_ROOT="${IV_ROOT:-${ROOT}/../iv}"
PKG="$(cd "$(dirname "$0")" && pwd)"
SRC="${PKG}/src"

if [ ! -f "${IV_ROOT}/main.c" ] || [ ! -f "${IV_ROOT}/iv.h" ]; then
	echo "✗ iv: missing source at IV_ROOT=${IV_ROOT} (clone IRodriguez13/iv)" >&2
	exit 1
fi

rm -rf "$SRC"
mkdir -p "$SRC"
# Copy only the build inputs (no .git / completions noise).
cp -a "${IV_ROOT}/main.c" "${IV_ROOT}/view.c" "${IV_ROOT}/edit.c" \
	"${IV_ROOT}/range.c" "${IV_ROOT}/iv.h" "${IV_ROOT}/Makefile" "$SRC/"
[ -f "${IV_ROOT}/iv.1" ] && cp -a "${IV_ROOT}/iv.1" "$SRC/"
echo "  FETCH   iv from IV_ROOT=${IV_ROOT}"
echo "✓ fetch iv OK"
