#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Apply ISD root patches/patches/<pkg>/*.patch and packages/<pkg>/patches/*.patch.
# Idempotent (-N): safe on every fetch/build when sources already exist.

set -euo pipefail

NAME="${1:?usage: apply-isd-patches.sh <package>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${ROOT}/packages/${NAME}/src"

[ -d "$SRC" ] || {
	echo "  PATCH   skip $NAME (no packages/$NAME/src)" >&2
	exit 0
}

apply_dir() {
	local label="$1"
	local dir="$2"
	local p

	[ -d "$dir" ] || return 0
	shopt -s nullglob
	for p in "$dir"/*.patch; do
		if patch -p1 -N --dry-run -d "$SRC" -i "$p" >/dev/null 2>&1; then
			echo "  PATCH   $NAME $(basename "$p") [$label]"
			patch -p1 -N -d "$SRC" -i "$p" --no-backup-if-mismatch
		else
			echo "  PATCH   $NAME $(basename "$p") [$label] already applied"
		fi
	done
}

apply_dir "package" "${ROOT}/packages/${NAME}/patches"
apply_dir "root" "${ROOT}/patches/${NAME}"
