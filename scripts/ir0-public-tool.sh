#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Resolve a documented IR0 public make target path (IR0_ISD_INTERFACE PUBLIC_TARGET).
set -euo pipefail

IR0_ROOT="${1:?IR0_ROOT}"
target="${2:?PUBLIC_TARGET name}"

if [ ! -f "${IR0_ROOT}/Makefile" ]; then
	echo "✗ IR0_ROOT missing Makefile: ${IR0_ROOT}" >&2
	exit 1
fi

path="$(make -C "$IR0_ROOT" -s "$target" 2>/dev/null || true)"
if [ -z "$path" ] || [ ! -e "$path" ]; then
	echo "✗ IR0 public target ${target} did not resolve to a path" >&2
	exit 1
fi
printf '%s\n' "$path"
