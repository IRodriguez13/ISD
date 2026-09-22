#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Resolve the package set for PROFILE:
#   core ∪ profile packages ∪ profile-local .isdconfig extras
# Auto-dep: nano → ncurses. Missing recipes are hard errors (no silent omit).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/admin-elevation.sh"
PROFILE="${PROFILE:-minimal}"
CFG="${ISD_CONFIG:-${ROOT}/.isdconfig.d/${PROFILE}}"
PROF_PKGS="${ROOT}/profiles/${PROFILE}/packages.txt"
PROF_CONF="${ROOT}/profiles/${PROFILE}/profile.conf"

fail() {
	echo "✗ resolve-packages: $*" >&2
	exit 1
}

if [ ! -f "$PROF_PKGS" ]; then
	fail "unknown PROFILE=${PROFILE} (missing ${PROF_PKGS})"
fi

INIT_SYSTEM=runit
if [ -f "$PROF_CONF" ]; then
	# shellcheck disable=SC1090
	source "$PROF_CONF"
fi
INIT_SYSTEM="${INIT_SYSTEM:-runit}"
case "$INIT_SYSTEM" in
runit|sysvinit|openrc) ;;
*) fail "unknown INIT_SYSTEM=${INIT_SYSTEM} in ${PROF_CONF}" ;;
esac
INIT_PKG="$INIT_SYSTEM"

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

# Core always present: userland base + selected init implementation.
for core in busybox "$INIT_PKG"; do
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

# Admin elevation: one tool per profile (doas via opendoas, or gnu sudo).
normalize_admin_packages() {
	resolve_admin_elevation
	local want_admin=0
	if [ -n "${WANT[opendoas]:-}" ] || [ -n "${WANT[sudo]:-}" ]; then
		want_admin=1
	fi
	# Package inclusion follows packages.txt or explicit .isdconfig overrides —
	# not profile.conf ADMIN_ELEVATION alone (minimal stays core-only in resolve).
	if [ -f "$CFG" ]; then
		if grep -E '^CONFIG_PKG_SUDO=[yY1]' "$CFG" >/dev/null 2>&1 \
			|| grep -E '^CONFIG_PKG_OPENDOAS=[yY1]' "$CFG" >/dev/null 2>&1; then
			want_admin=1
		fi
		if grep -E '^ADMIN_ELEVATION=' "$CFG" >/dev/null 2>&1; then
			want_admin=1
		fi
	fi
	unset 'WANT[opendoas]' 'WANT[sudo]'
	if [ "$want_admin" -eq 1 ]; then
		require_recipe "$ADMIN_PKG" "ADMIN_ELEVATION=${ADMIN_ELEVATION}"
		add "$ADMIN_PKG"
	fi
}

normalize_admin_packages

for pkg in "${!WANT[@]}"; do
	require_recipe "$pkg" "resolved set"
done

# Stable order: core first, then alpha.
ordered=()
for core in busybox "$INIT_PKG"; do
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
