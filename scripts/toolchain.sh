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

_ROOT="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ISA facts (aliases, triple, package policy) live in packages/arch/<isa>/.
# shellcheck source=scripts/arch-policy.sh
source "${_ROOT}/scripts/arch-policy.sh"
if ! _isd_arch="$(isd_arch_canonical "${ARCH:-x86_64}")"; then
	echo "✗ unsupported ARCH=${ARCH:-} ($(isd_arch_list | paste -sd '|'))" >&2
	return 1 2>/dev/null || exit 1
fi
ARCH="$_isd_arch"
isd_arch_load "$ARCH"
TARGET_TRIPLE="${TARGET_TRIPLE:-$ISD_ARCH_TRIPLE}"

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
	if command -v musl-gcc >/dev/null 2>&1 && \
		[ "$(isd_arch_canonical "$(uname -m)" || true)" = "$ARCH" ]; then
		CC="$(command -v musl-gcc)"
		return 0
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
IR0_UAPI_SYSROOT="${IR0_UAPI_SYSROOT:-${_ROOT}/sysroot/${ARCH}}"
SYSROOT="${SYSROOT:-${IR0_UAPI_SYSROOT}}"

# Compat aliases used by older recipes
MUSL_CC="$CC"
OUT="${PRODUCT_OUT}"

export ARCH TARGET_TRIPLE CROSS_COMPILE CC AR RANLIB STRIP READELF OBJCOPY
export OUT_ARCH PRODUCT_OUT TESTS_OUT SMOKE_OUT ROOTFS_OUT
export IR0_UAPI_SYSROOT SYSROOT MUSL_CC OUT

# Package support status for this ISA (packages/arch/<isa>/support).
toolchain_pkg_status()
{
	isd_arch_package_status "$ARCH" "$1"
}

export ISD_ARCH_REGISTRY ISD_ARCH_ELF_MACHINE
export -f toolchain_pkg_status isd_arch_package_status 2>/dev/null || true
