#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Resolve the package set for PROFILE:
#   core (busybox runit) ∪ profiles/PROFILE/packages.txt ∪ .isdconfig CONFIG_PKG_*=y
# Auto-dep: nano → ncurses. Validate packages/<name> exists.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE="${PROFILE:-minimal}"
CFG="${ISD_CONFIG:-${ROOT}/.isdconfig}"
PROF_PKGS="${ROOT}/profiles/${PROFILE}/packages.txt"

declare -A WANT=()

add() {
	local p
	for p in "$@"; do
		[ -n "$p" ] || continue
		WANT["$p"]=1
	done
}

# Core always present.
add busybox runit

if [ -f "$PROF_PKGS" ]; then
	while read -r line || [ -n "${line:-}" ]; do
		[[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
		add "$line"
	done <"$PROF_PKGS"
fi

cfg_val() {
	local key="$1"
	local line
	[ -f "$CFG" ] || return 1
	line="$(grep -E "^${key}=" "$CFG" 2>/dev/null | tail -1 || true)"
	[ -n "$line" ] || return 1
	echo "${line#*=}"
}

# Map CONFIG_PKG_FOO=y → package directory name.
# Skip names without packages/<name>/build.sh (warn; do not fail) so a stale
# .isdconfig with TINYCC=y cannot wedge first-boot.
if [ -f "$CFG" ]; then
	while IFS= read -r line || [ -n "${line:-}" ]; do
		[[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
		case "$line" in
		CONFIG_PKG_*=y|CONFIG_PKG_*=Y)
			key="${line%%=*}"
			name="${key#CONFIG_PKG_}"
			# Non-lowercase dirs (must match isdconfig.FUTURE_PACKAGES).
			case "$name" in
			PACK_EXTRACT) pkg="pack-extract" ;;
			*) pkg="$(echo "$name" | tr '[:upper:]' '[:lower:]')" ;;
			esac
			if [ ! -f "${ROOT}/packages/${pkg}/build.sh" ]; then
				echo "⚠ resolve-packages: skip CONFIG_PKG_${name}=y (packages/${pkg}/ missing)" >&2
				continue
			fi
			add "$pkg"
			;;
		esac
	done <"$CFG"
fi

# Auto-dep: nano → ncurses
if [ -n "${WANT[nano]:-}" ]; then
	add ncurses
fi

# Drop any mandatory/profile entries that lack a recipe (warn).
for pkg in "${!WANT[@]}"; do
	if [ ! -f "${ROOT}/packages/${pkg}/build.sh" ]; then
		echo "⚠ resolve-packages: omit ${pkg} (no packages/${pkg}/build.sh)" >&2
		unset "WANT[$pkg]"
	fi
done

# Stable order: core first, then alpha.
ordered=()
for core in busybox runit; do
	if [ -n "${WANT[$core]:-}" ]; then
		ordered+=("$core")
		unset "WANT[$core]"
	fi
done
while IFS= read -r pkg; do
	[ -n "$pkg" ] && ordered+=("$pkg")
done < <(printf '%s\n' "${!WANT[@]}" | LC_ALL=C sort)

printf '%s\n' "${ordered[*]}"
