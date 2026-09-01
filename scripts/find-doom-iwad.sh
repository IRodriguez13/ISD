#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Resolve a Doom IWAD for ISD packaging.
# Prints absolute path to stdout and exits 0, or exits 1 if none found.
#
# Search order:
#   1. ISD_DOOM_IWAD (explicit)
#   2. rootfs/local lab copies under ISD
#   3. Sibling/lab trees: ../universal-doom, $HOME/Escritorio|Desktop/universal-doom
#   4. IR0_ROOT/../universal-doom
#
# Env:
#   ISD_DOOM_SKIP_AUTODISCOVER=1 — only honour ISD_DOOM_IWAD (contracts/CI)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IR0_ROOT="${IR0_ROOT:-${ROOT}/../IR0}"

_names=(doom1.wad DOOM1.WAD doom.wad DOOM.WAD)

_try_file()
{
	local f="$1"
	if [ -n "$f" ] && [ -f "$f" ]; then
		# Prefer realpath when available for a stable absolute path.
		if command -v realpath >/dev/null 2>&1; then
			realpath "$f"
		else
			(cd "$(dirname "$f")" && echo "$(pwd)/$(basename "$f")")
		fi
		return 0
	fi
	return 1
}

_try_dir()
{
	local d="$1"
	local n
	[ -d "$d" ] || return 1
	for n in "${_names[@]}"; do
		_try_file "${d}/${n}" && return 0
	done
	return 1
}

# Explicit override always wins.
if [ -n "${ISD_DOOM_IWAD:-}" ]; then
	if _try_file "$ISD_DOOM_IWAD"; then
		exit 0
	fi
	echo "✗ find-doom-iwad: ISD_DOOM_IWAD set but not a file: $ISD_DOOM_IWAD" >&2
	exit 1
fi

case "${ISD_DOOM_SKIP_AUTODISCOVER:-0}" in
1|y|Y|yes|YES)
	exit 1
	;;
esac

# Lab copies inside the ISD tree (opt-in drop for packaging).
for n in "${_names[@]}"; do
	_try_file "${ROOT}/rootfs/local/usr/share/doom/${n}" && exit 0
	_try_file "${ROOT}/rootfs/local/usr/ken/games/${n}" && exit 0
done

# Maintainer lab: universal-doom next to ISD / IR0 / under home Desktop.
_try_dir "${ROOT}/../universal-doom" && exit 0
_try_dir "${IR0_ROOT}/../universal-doom" && exit 0
_try_dir "${HOME}/Escritorio/universal-doom" && exit 0
_try_dir "${HOME}/Desktop/universal-doom" && exit 0

exit 1
