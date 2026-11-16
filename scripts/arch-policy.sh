#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Sole reader of the ISA registry under packages/arch/<isa>/.
#
# Every ISA-specific fact used to locate or build packages lives in data files
# there; this file only interprets them, so adding an ISA means adding a
# directory, never a branch here.
#
#   packages/arch/<isa>/arch.conf   ISD_ARCH_TRIPLE, ISD_ARCH_ELF_MACHINE
#   packages/arch/<isa>/aliases     other names accepted for <isa>
#   packages/arch/<isa>/support     "<package> <status>" rows, `*` = default
#
# Source it for the isd_arch_* functions, or run it:
#   scripts/arch-policy.sh list
#   scripts/arch-policy.sh canonical <name>
#   scripts/arch-policy.sh status <isa> <package>...

ISD_ARCH_REGISTRY="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/packages/arch"

# Print every registered ISA, one per line.
isd_arch_list()
{
	local conf
	for conf in "$ISD_ARCH_REGISTRY"/*/arch.conf; do
		[ -f "$conf" ] || continue
		conf="${conf%/arch.conf}"
		echo "${conf##*/}"
	done
}

# Map an ISA name or alias to its registry directory name.
isd_arch_canonical()
{
	local name="${1:-}" isa alias
	[ -n "$name" ] || return 1
	while IFS= read -r isa; do
		if [ "$name" = "$isa" ]; then
			echo "$isa"
			return 0
		fi
		for alias in $(cat "$ISD_ARCH_REGISTRY/$isa/aliases" 2>/dev/null); do
			if [ "$name" = "$alias" ]; then
				echo "$isa"
				return 0
			fi
		done
	done < <(isd_arch_list)
	return 1
}

# Load arch.conf for one canonical ISA into the caller's shell.
isd_arch_load()
{
	local conf="$ISD_ARCH_REGISTRY/${1:-}/arch.conf"
	[ -f "$conf" ] || return 1
	# shellcheck source=/dev/null
	source "$conf"
}

# Print the support status of one package on one canonical ISA.
isd_arch_package_status()
{
	local isa="$1" pkg="$2"
	awk -v pkg="$pkg" '
		/^[[:space:]]*(#|$)/ { next }
		$1 == pkg { print $2; found = 1; exit }
		$1 == "*" && def == "" { def = $2 }
		END { if (!found) print (def != "" ? def : "unsupported") }
	' "$ISD_ARCH_REGISTRY/$isa/support" 2>/dev/null || echo unsupported
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
	set -euo pipefail
	cmd="${1:-}"
	shift || true
	case "$cmd" in
	list)
		isd_arch_list
		;;
	canonical)
		isd_arch_canonical "${1:-}" || {
			echo "✗ unknown ISA ${1:-}; registered: $(isd_arch_list | tr '\n' ' ')" >&2
			exit 1
		}
		;;
	status)
		isa="$(isd_arch_canonical "${1:-}")" || {
			echo "✗ unknown ISA ${1:-}" >&2
			exit 1
		}
		shift
		for pkg in "$@"; do
			echo "$pkg $(isd_arch_package_status "$isa" "$pkg")"
		done
		;;
	*)
		echo "usage: $0 list | canonical <name> | status <isa> <package>..." >&2
		exit 2
		;;
	esac
fi
