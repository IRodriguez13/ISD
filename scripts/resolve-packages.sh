#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Resolve the package set for PROFILE:
#   core ∪ profile packages ∪ profile-local .isdconfig extras
# Auto-dep: nano → ncurses. Missing recipes are hard errors (no silent omit).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE="${PROFILE:-minimal}"
CFG="${ISD_CONFIG:-${ROOT}/.isdconfig.d/${PROFILE}}"
PROF_PKGS="${ROOT}/profiles/${PROFILE}/packages.txt"

fail() {
	echo "✗ resolve-packages: $*" >&2
	exit 1
}

if [ ! -f "$PROF_PKGS" ]; then
	fail "unknown PROFILE=${PROFILE} (missing ${PROF_PKGS})"
fi

declare -A WANT=()

add() {
	local p
	for p in "$@"; do
		[ -n "$p" ] || continue
		WANT["$p"]=1
	done
}

require_recipe() {
	local pkg="$1"
	local ctx="$2"
	if [ ! -f "${ROOT}/packages/${pkg}/build.sh" ]; then
		fail "${ctx}: packages/${pkg}/ missing build.sh"
	fi
}

# Core always present.
for core in busybox runit; do
	require_recipe "$core" "core"
	add "$core"
done

while read -r line || [ -n "${line:-}" ]; do
	[[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
	require_recipe "$line" "profiles/${PROFILE}/packages.txt"
	add "$line"
done <"$PROF_PKGS"

cfg_val() {
	local key="$1"
	local line
	[ -f "$CFG" ] || return 1
	line="$(grep -E "^${key}=" "$CFG" 2>/dev/null | tail -1 || true)"
	[ -n "$line" ] || return 1
	echo "${line#*=}"
}

# Map CONFIG_PKG_FOO=y → package directory name.
if [ -f "$CFG" ]; then
	while IFS= read -r line || [ -n "${line:-}" ]; do
		[[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
		case "$line" in
		CONFIG_PKG_*=y|CONFIG_PKG_*=Y)
			key="${line%%=*}"
			name="${key#CONFIG_PKG_}"
			case "$name" in
			PACK_EXTRACT) pkg="pack-extract" ;;
			*) pkg="$(echo "$name" | tr '[:upper:]' '[:lower:]')" ;;
			esac
			require_recipe "$pkg" "${CFG}: ${line}"
			add "$pkg"
			;;
		esac
	done <"$CFG"
fi

# Auto-dep: nano → ncurses
if [ -n "${WANT[nano]:-}" ]; then
	require_recipe ncurses "auto-dep nano→ncurses"
	add ncurses
fi

for pkg in "${!WANT[@]}"; do
	require_recipe "$pkg" "resolved set"
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

if [ "${#ordered[@]}" -eq 0 ]; then
	fail "empty package set for PROFILE=${PROFILE}"
fi

printf '%s\n' "${ordered[*]}"
