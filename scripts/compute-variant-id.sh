#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Content-aware build variant id (profile + packages + config + UAPI fingerprint).
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
ARCH="${ARCH:-x86_64}"
PROFILE="${PROFILE:-minimal}"
CFG="${ISD_CONFIG:-${ROOT}/.isdconfig.d/${PROFILE}}"

ir0_iface="0"
if [ -n "${IR0_ROOT:-}" ] && [ -f "${IR0_ROOT}/IR0_ISD_INTERFACE" ]; then
	ir0_iface="$(grep '^VERSION=' "${IR0_ROOT}/IR0_ISD_INTERFACE" | cut -d= -f2- | tr -d '[:space:]')"
fi

pkgs="$(PROFILE="$PROFILE" bash "${ROOT}/scripts/resolve-packages.sh" | tr ' ' '\n' | LC_ALL=C sort | paste -sd, -)"

cfg_fp="none"
if [ -f "$CFG" ]; then
	cfg_fp="$(sha256sum "$CFG" | awk '{print $1}' | cut -c1-8)"
fi

# Fingerprint the exported header content, not the UAPI stamp: the stamp
# records when headers were exported, so hashing it moved every package into
# a new variant (full rebuild) whenever identical headers were re-exported.
uapi_fp="none"
uapi_inc="${IR0_UAPI_SYSROOT:-${ROOT}/sysroot/${ARCH}}/usr/include"
if [ -d "$uapi_inc" ]; then
	uapi_fp="$(cd "$uapi_inc" && find . -type f -print0 | LC_ALL=C sort -z \
		| xargs -0 -r sha256sum | sha256sum | cut -c1-8)"
fi

payload="${ARCH}|${PROFILE}|pkgs:${pkgs}|cfg:${cfg_fp}|uapi:${uapi_fp}|iface:${ir0_iface}"
hash="$(printf '%s' "$payload" | sha256sum | awk '{print $1}' | cut -c1-12)"
echo "${PROFILE}-${hash}"
