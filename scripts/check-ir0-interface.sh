#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Verify IR0_ROOT publishes a compatible IR0_ISD_INTERFACE for ISD builds.
set -euo pipefail

ISD_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IR0_ROOT="${1:-${IR0_ROOT:-}}"

if [ -z "$IR0_ROOT" ]; then
	echo "✗ IR0_ROOT is not set" >&2
	echo "  export IR0_ROOT=/path/to/IR0" >&2
	exit 1
fi

if [ -n "${IR0_UAPI_TARBALL:-}" ] || [ -n "${IR0_UAPI_SYSROOT:-}" ]; then
	echo "  SKIP  check-ir0-interface (IR0_UAPI_TARBALL/SYSROOT offline path)"
	exit 0
fi

iface="${IR0_ROOT}/IR0_ISD_INTERFACE"
if [ ! -f "$iface" ]; then
	echo "✗ missing ${iface}" >&2
	echo "  This ISD checkout requires IR0 with IR0_ISD_INTERFACE (interface >= 1)." >&2
	exit 1
fi

kernel_ver=""
required_scripts=()
public_targets=()
while IFS= read -r line || [ -n "$line" ]; do
	line="${line%%#*}"
	line="${line#"${line%%[![:space:]]*}"}"
	line="${line%"${line##*[![:space:]]}"}"
	[ -z "$line" ] && continue
	case "$line" in
	VERSION=*)
		kernel_ver="${line#VERSION=}"
		;;
	REQUIRED_SCRIPT=*)
		required_scripts+=("${line#REQUIRED_SCRIPT=}")
		;;
	PUBLIC_TARGET=*)
		public_targets+=("${line#PUBLIC_TARGET=}")
		;;
	esac
done < "$iface"

if [ -z "$kernel_ver" ]; then
	echo "✗ ${iface}: missing VERSION=" >&2
	exit 1
fi

supported="$(tr -d '[:space:]' < "${ISD_ROOT}/IR0_ISD_INTERFACE_SUPPORTED")"
if [ -z "$supported" ]; then
	echo "✗ missing ${ISD_ROOT}/IR0_ISD_INTERFACE_SUPPORTED" >&2
	exit 1
fi

if [ "$kernel_ver" -gt "$supported" ] 2>/dev/null; then
	echo "✗ IR0/ISD interface mismatch" >&2
	echo "  kernel IR0_ISD_INTERFACE VERSION=${kernel_ver}" >&2
	echo "  ISD supports up to ${supported}" >&2
	echo "  Update ISD or use a matching IR0 checkout." >&2
	exit 1
fi

for script in "${required_scripts[@]}"; do
	if [ ! -f "${IR0_ROOT}/${script}" ]; then
		echo "✗ IR0 missing required script: ${script}" >&2
		exit 1
	fi
done

for target in "${public_targets[@]}"; do
	if ! make -C "$IR0_ROOT" -n "$target" >/dev/null 2>&1; then
		echo "✗ IR0 missing public make target: ${target}" >&2
		exit 1
	fi
done

echo "✓ IR0/ISD interface OK (kernel=${kernel_ver}, ISD supports<=${supported})"
