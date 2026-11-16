#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Populate IR0_UAPI_SYSROOT from sibling IR0, a tarball, or a prefilled tree.
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
ARCH="${ARCH:-x86_64}"
DEST="${IR0_UAPI_SYSROOT:-${ROOT}/sysroot/${ARCH}}"
IR0_ROOT="${IR0_ROOT:-${ROOT}/../IR0}"

mkdir -p "$DEST"

if [ -n "${IR0_UAPI_TARBALL:-}" ]; then
	if [ ! -f "$IR0_UAPI_TARBALL" ]; then
		echo "✗ IR0_UAPI_TARBALL not found: $IR0_UAPI_TARBALL" >&2
		exit 1
	fi
	echo "  UAPI    extracting $IR0_UAPI_TARBALL → $DEST"
	tar -xf "$IR0_UAPI_TARBALL" -C "$DEST"
elif [ -d "${DEST}/usr/include" ] && [ -n "$(find "${DEST}/usr/include" -name '*.h' 2>/dev/null | head -1)" ]; then
	echo "  UAPI    using existing $DEST"
elif [ -f "${IR0_ROOT}/Makefile" ]; then
	echo "  UAPI    headers_install from IR0_ROOT=$IR0_ROOT"
	# Drop inherited ARCH=x86_64 from ISD Make — IR0 headers_install is arch-agnostic.
	env -u ARCH make -C "$IR0_ROOT" headers_install DESTDIR="$DEST"
else
	echo "✗ no UAPI source: set IR0_ROOT, IR0_UAPI_TARBALL, or prefill IR0_UAPI_SYSROOT" >&2
	exit 1
fi

if [ ! -d "${DEST}/usr/include" ]; then
	echo "✗ UAPI missing usr/include under $DEST" >&2
	exit 1
fi

# Record version metadata for releases.
ver="unknown"
if [ -f "${IR0_ROOT}/VERSION" ]; then
	ver="$(tr -d '\n' < "${IR0_ROOT}/VERSION")"
elif [ -f "${ROOT}/VERSION" ]; then
	ver="userspace-$(tr -d '\n' < "${ROOT}/VERSION")"
fi
mkdir -p "${DEST}/usr/share/ir0"
{
	echo "IR0_UAPI_VERSION=${ver}"
	echo "IR0_UAPI_FEATURES=posix,proc,sys,dev,heart"
	echo "IR0_KERNEL_MIN=0.0.1"
} > "${DEST}/usr/share/ir0/uapi-release.txt"
echo "✓ headers → $DEST/usr/include"
