#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Central toolchain resolution for IR0-userspace. Source this file; do not
# search for x86_64-linux-musl-gcc inside individual package recipes.
#
# Usage:
#   ARCH=x86_64 source scripts/toolchain.sh
#   # exports ARCH TARGET_TRIPLE CROSS_COMPILE CC AR RANLIB STRIP READELF OBJCOPY
#   #        OUT_ARCH PRODUCT_OUT TESTS_OUT SMOKE_OUT ROOTFS_OUT IR0_UAPI_SYSROOT

set -euo pipefail

_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ARCH="${ARCH:-x86_64}"
case "$ARCH" in
x86_64|amd64)
	ARCH=x86_64
	TARGET_TRIPLE="${TARGET_TRIPLE:-x86_64-linux-musl}"
	;;
aarch64|arm64)
	ARCH=aarch64
	TARGET_TRIPLE="${TARGET_TRIPLE:-aarch64-linux-musl}"
	;;
*)
	echo "✗ unsupported ARCH=$ARCH (x86_64|aarch64)" >&2
	return 1 2>/dev/null || exit 1
	;;
esac

CROSS_COMPILE="${CROSS_COMPILE:-}"

_resolve_cc()
{
	# Ignore bare host cc/gcc inherited from Make's default CC.
	case "${CC:-}" in
	""|cc|gcc|clang|/usr/bin/cc|/usr/bin/gcc|/usr/bin/clang|/bin/cc|/bin/gcc)
		CC=""
		;;
	esac
	if [ -n "${CC:-}" ]; then
		command -v "$CC" >/dev/null 2>&1 || {
			echo "✗ CC=$CC not found" >&2
			return 1
		}
		return 0
	fi
	local cand
	# Prefer the musl triple compiler. Never treat bare "gcc" as a match
	# when CROSS_COMPILE is empty ("${CROSS_COMPILE}gcc" → "gcc").
	for cand in \
		"${TARGET_TRIPLE}-gcc" \
		"${ARCH}-linux-musl-gcc"
	do
		if command -v "$cand" >/dev/null 2>&1; then
			CC="$(command -v "$cand")"
			return 0
		fi
	done
	if [ -n "${CROSS_COMPILE}" ]; then
		cand="${CROSS_COMPILE}gcc"
		if command -v "$cand" >/dev/null 2>&1; then
			CC="$(command -v "$cand")"
			return 0
		fi
	fi
	# Host musl-gcc only when targeting the host arch.
	if [ "$ARCH" = "x86_64" ] && command -v musl-gcc >/dev/null 2>&1; then
		local host
		host="$(uname -m)"
		if [ "$host" = "x86_64" ] || [ "$host" = "amd64" ]; then
			CC="$(command -v musl-gcc)"
			return 0
		fi
	fi
	echo "✗ no toolchain for ARCH=$ARCH TARGET_TRIPLE=$TARGET_TRIPLE" >&2
	echo "  set CC= or CROSS_COMPILE= or install ${TARGET_TRIPLE}-gcc" >&2
	return 1
}

# Allow status-only sourcing without a cross compiler (e.g. aarch64 matrix).
if [ "${IR0_TOOLCHAIN_OPTIONAL:-0}" = "1" ]; then
	_resolve_cc 2>/dev/null || CC=""
else
	_resolve_cc || return 1 2>/dev/null || exit 1
fi

_tool()
{
	local name="$1"
	local from_cc
	if [ -n "$CROSS_COMPILE" ] && command -v "${CROSS_COMPILE}${name}" >/dev/null 2>&1; then
		echo "${CROSS_COMPILE}${name}"
		return
	fi
	if command -v "${TARGET_TRIPLE}-${name}" >/dev/null 2>&1; then
		echo "${TARGET_TRIPLE}-${name}"
		return
	fi
	from_cc="$(dirname "$CC")/${TARGET_TRIPLE}-${name}"
	if [ -x "$from_cc" ]; then
		echo "$from_cc"
		return
	fi
	if command -v "$name" >/dev/null 2>&1; then
		echo "$(command -v "$name")"
		return
	fi
	echo "$name"
}

AR="${AR:-$(_tool ar)}"
RANLIB="${RANLIB:-$(_tool ranlib)}"
STRIP="${STRIP:-$(_tool strip)}"
READELF="${READELF:-$(_tool readelf)}"
OBJCOPY="${OBJCOPY:-$(_tool objcopy)}"

OUT_ARCH="${OUT_ARCH:-${_ROOT}/out/${ARCH}}"
PRODUCT_OUT="${PRODUCT_OUT:-${OUT_ARCH}/product}"
TESTS_OUT="${TESTS_OUT:-${OUT_ARCH}/tests}"
SMOKE_OUT="${SMOKE_OUT:-${OUT_ARCH}/smoke}"
ROOTFS_OUT="${ROOTFS_OUT:-${OUT_ARCH}/rootfs}"
IR0_UAPI_SYSROOT="${IR0_UAPI_SYSROOT:-${_ROOT}/sysroot}"
SYSROOT="${SYSROOT:-${IR0_UAPI_SYSROOT}}"

# Compat aliases used by older recipes
MUSL_CC="$CC"
OUT="${PRODUCT_OUT}"

export ARCH TARGET_TRIPLE CROSS_COMPILE CC AR RANLIB STRIP READELF OBJCOPY
export OUT_ARCH PRODUCT_OUT TESTS_OUT SMOKE_OUT ROOTFS_OUT
export IR0_UAPI_SYSROOT SYSROOT MUSL_CC OUT

# Package support matrix (honest classification)
toolchain_pkg_status()
{
	local pkg="$1"
	case "$ARCH" in
	x86_64)
		echo "supported"
		;;
	aarch64)
		case "$pkg" in
		busybox|runit)
			echo "buildable"
			;;
		opendoas|ncurses|nano|tinycc|gnumake|doom|iv|pack-extract)
			echo "blocked-by-package"
			;;
		*)
			echo "unsupported"
			;;
		esac
		;;
	*)
		echo "unsupported"
		;;
	esac
}

export -f toolchain_pkg_status 2>/dev/null || true
