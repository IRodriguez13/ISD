#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Verify xterm-411 MapSelections issue on Linux baseline (no IR0/QEMU).
#
# 1) Source audit — vanilla tarball lacks InvalidSelectionParam guard.
# 2) Dynamic repro — minimal C program crashes in strcmp on Linux glibc/musl.
# 3) Patch sanity — ISD patch applies cleanly to vanilla tree.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PATCH_DIR="${ROOT}/patches/xterm"
TARBALL="${ROOT}/packages/xterm/dist/xterm-411.tgz"
REPRO_SRC="${PATCH_DIR}/linux-baseline-repro.c"
REPRO_BIN="$(mktemp /tmp/xterm-linux-repro.XXXXXX)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" "$REPRO_BIN"' EXIT

fail() { echo "✗ $*" >&2; exit 1; }

[ -f "$TARBALL" ] || fail "missing $TARBALL (run: make fetch PROFILE=desktop)"
[ -f "${PATCH_DIR}/0001-button-MapSelections-guard-invalid-selection-param.patch" ] || \
	fail "missing ISD xterm patch"

echo "== 1/3 Source audit (vanilla xterm-411 button.c) =="
tar -xf "$TARBALL" -C "$TMP"
SRC="${TMP}/xterm-411"
if rg -q 'InvalidSelectionParam' "$SRC/button.c"; then
	fail "upstream already contains InvalidSelectionParam"
fi
if ! rg -q 'MapSelections' "$SRC/button.c"; then
	fail "MapSelections not found in vanilla button.c"
fi
echo "  OK      vanilla lacks InvalidSelectionParam (vulnerable code present)"

echo "== 2/3 Patch applies to vanilla tree =="
patch -p1 -N -d "$SRC" \
	-i "${PATCH_DIR}/0001-button-MapSelections-guard-invalid-selection-param.patch" \
	--no-backup-if-mismatch
rg -q 'InvalidSelectionParam' "$SRC/button.c" || fail "patch did not add guard"
echo "  OK      patch applies cleanly"

echo "== 3/3 Linux dynamic repro (strcmp on param=9) =="
cc -O0 -g -o "$REPRO_BIN" "$REPRO_SRC"
set +e
"$REPRO_BIN" >/dev/null 2>&1
rc=$?
set -e
if [ "$rc" -ne 139 ] && [ "$rc" -ne 132 ] && [ "$rc" -ne 134 ]; then
	fail "expected SIGSEGV (139/132/134), got exit $rc"
fi
echo "  OK      vanilla logic SIGSEGV on Linux (exit $rc) — not IR0-specific"

echo "✓ verify-xterm-patch-linux-baseline OK"
