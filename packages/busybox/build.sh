#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Build BusyBox variants with a package-local lock (no /tmp global lock).
# Outputs land under out/<arch>/product/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/toolchain.sh"
PKG="${ROOT}/packages/busybox"
SRC="${PKG}/src"
OUT_DIR="${PRODUCT_OUT:-${ROOT}/out/${ARCH}/product}"
LOCK="${PKG}/.build-${ARCH}.lock"

if [ ! -f "$SRC/Makefile" ]; then
	echo "✗ missing BusyBox source; run: make fetch" >&2
	exit 1
fi

# IR0 BusyBox patches (flag tab-completion, etc.). Skip if already in tree.
if [ -d "${PKG}/ir0-patches" ]; then
	if grep -q complete_command_flags "$SRC/libbb/lineedit.c" 2>/dev/null; then
		echo "  BUSYBOX IR0 patches already applied (complete_command_flags present)"
	else
		shopt -s nullglob
		for p in "${PKG}/ir0-patches/"*.patch; do
			echo "  BUSYBOX applying $(basename "$p")"
			patch -p1 -N -d "$SRC" -i "$p"
		done
		shopt -u nullglob
	fi
fi

mkdir -p "$OUT_DIR"
chmod +x "${ROOT}/scripts/busybox_apply_fragment.sh"

build_variant()
{
	local fragment="$1"
	local out="$2"

	echo "  BUSYBOX Building $(basename "$out") ARCH=${ARCH}"
	"${ROOT}/scripts/busybox_apply_fragment.sh" "$SRC" "$fragment"
	# Musl sysroot lacks linux/*.h; expose host UAPI after musl (idirafter)
	# so bits/ioctl.h wins over asm-generic/ioctl.h.
	local uapi="${PKG}/.linux-uapi"
	rm -rf "$uapi"
	mkdir -p "$uapi"
	if [ -d /usr/include/linux ]; then
		ln -sfn /usr/include/linux "${uapi}/linux"
	fi
	if [ -d /usr/include/asm-generic ]; then
		ln -sfn /usr/include/asm-generic "${uapi}/asm-generic"
	fi
	if [ -d /usr/include/x86_64-linux-gnu/asm ]; then
		ln -sfn /usr/include/x86_64-linux-gnu/asm "${uapi}/asm"
	elif [ -d /usr/include/asm ]; then
		ln -sfn /usr/include/asm "${uapi}/asm"
	else
		mkdir -p "${uapi}/asm"
		printf '%s\n' '#pragma once' '#include <asm-generic/types.h>' \
			> "${uapi}/asm/types.h"
	fi
	if [ -d /usr/include/mtd ]; then
		ln -sfn /usr/include/mtd "${uapi}/mtd"
	fi
	# Upstream BusyBox emits -Wunused-result / -Wformat-security noise (target
	# and host helpers like applets/usage); keep our tree log clean.
	local bb_cflags="-fno-pie -Wno-unused-result -Wno-format-security -idirafter ${uapi}"
	local bb_hostcflags="-Wno-unused-result -Wno-format-security"
	make -C "$SRC" CC="$CC" -s clean >/dev/null 2>&1 || true
	make -C "$SRC" CC="$CC" CFLAGS="$bb_cflags" HOSTCFLAGS="$bb_hostcflags" \
		LDFLAGS="-no-pie" -s -j"$(nproc)"
	cp -f "$SRC/busybox" "$out"
	file "$out" | grep -q ELF
}

(
	flock 9
	build_variant "${PKG}/ir0_full.config" "${OUT_DIR}/busybox-full"
	"${OUT_DIR}/busybox-full" --list | grep -qx sh
	if "${OUT_DIR}/busybox-full" --list | grep -qxE 'login|su|passwd'; then
		echo "✗ privileged applet inside the general binary" >&2
		exit 1
	fi
	echo "✓ busybox-full OK ($("${OUT_DIR}/busybox-full" --list | wc -l) applets)"

	build_variant "${PKG}/ir0_auth.config" "${OUT_DIR}/busybox-auth"
	auth_list="$(mktemp "${TMPDIR:-/tmp}/ir0-bb-auth.XXXXXX")"
	"${OUT_DIR}/busybox-auth" --list | sort > "$auth_list"
	printf 'login\nsu\n' | sort | diff -u - "$auth_list" >/dev/null || {
		echo "✗ auth binary applet set drifted (expected login + su only)" >&2
		rm -f "$auth_list"
		exit 1
	}
	rm -f "$auth_list"
	echo "✓ busybox-auth OK (login, su)"
) 9>"$LOCK"
