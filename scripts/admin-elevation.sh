#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Resolve ADMIN_ELEVATION (doas|sudo) and ADMIN_PKG (opendoas|sudo) for PROFILE.
# Profile default: profiles/<profile>/profile.conf ADMIN_ELEVATION=…
# Override: .isdconfig.d/<profile> ADMIN_ELEVATION=… or CONFIG_PKG_SUDO=y.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${PROFILE:-minimal}"
CFG="${ISD_CONFIG:-${ROOT}/.isdconfig.d/${PROFILE}}"
PROF_CONF="${ROOT}/profiles/${PROFILE}/profile.conf"

resolve_admin_elevation() {
	ADMIN_ELEVATION=doas
	if [ -f "$PROF_CONF" ]; then
		local val
		val="$(grep -E '^ADMIN_ELEVATION=' "$PROF_CONF" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '[:space:]' || true)"
		[ -n "$val" ] && ADMIN_ELEVATION="$val"
	fi
	if [ -f "$CFG" ]; then
		local val
		val="$(grep -E '^ADMIN_ELEVATION=' "$CFG" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '[:space:]' || true)"
		[ -n "$val" ] && ADMIN_ELEVATION="$val"
		if grep -E '^CONFIG_PKG_SUDO=[yY1]' "$CFG" >/dev/null 2>&1; then
			ADMIN_ELEVATION=sudo
		elif grep -E '^CONFIG_PKG_OPENDOAS=[yY1]' "$CFG" >/dev/null 2>&1 \
			&& ! grep -E '^ADMIN_ELEVATION=sudo' "$CFG" >/dev/null 2>&1; then
			ADMIN_ELEVATION=doas
		fi
	fi
	case "$ADMIN_ELEVATION" in
	doas|sudo) ;;
	*)
		echo "✗ unknown ADMIN_ELEVATION=${ADMIN_ELEVATION} (PROFILE=${PROFILE})" >&2
		return 1
		;;
	esac
	ADMIN_PKG=opendoas
	[ "$ADMIN_ELEVATION" = "sudo" ] && ADMIN_PKG=sudo
	export ADMIN_ELEVATION ADMIN_PKG
}
