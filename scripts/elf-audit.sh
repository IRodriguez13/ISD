#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/toolchain.sh"
PRODUCT_OUT="${PRODUCT_OUT:-${ROOT}/out/${ARCH}/product}"
READELF="${READELF:-readelf}"

export LC_ALL=C LANG=C
fail=0
shopt -s nullglob
for bin in \
	"${PRODUCT_OUT}/busybox-full" \
	"${PRODUCT_OUT}/busybox-auth" \
	"${PRODUCT_OUT}/bin/"* \
	"${PRODUCT_OUT}/stage-bin/"*
do
	[ -f "$bin" ] || continue
	[ -x "$bin" ] || continue
	info="$(LC_ALL=C "$READELF" -h "$bin" 2>/dev/null || true)"
	if ! echo "$info" | grep -qE 'Type:[[:space:]]*(EXEC|DYN)'; then
		echo "✗ not ELF EXEC/DYN: $bin" >&2
		fail=1
		continue
	fi
	if ! echo "$info" | grep -qiE "$ISD_ARCH_ELF_MACHINE"; then
		echo "✗ wrong machine for ARCH=$ARCH: $bin" >&2
		echo "$info" | grep -i machine || true
		fail=1
	fi
	# Static policy: product ELFs should not carry a host dynamic interpreter.
	if echo "$info" | grep -q 'Type:[[:space:]]*DYN'; then
		interp="$(LC_ALL=C "$READELF" -l "$bin" 2>/dev/null | awk '/Requesting program interpreter/{print $NF}' || true)"
		if [ -n "$interp" ] && [[ "$interp" == /lib/* || "$interp" == /lib64/* ]]; then
			echo "✗ host interpreter on $bin: $interp" >&2
			fail=1
		fi
	fi
done

if [ "$fail" -ne 0 ]; then
	exit 1
fi
echo "✓ elf-audit OK ARCH=$ARCH"
