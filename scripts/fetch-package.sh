#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Fetch and unpack one package from packages/<name>/{url,version,sha256,srcroot}.
# Downloads land in packages/<name>/dist and the verified tree in
# packages/<name>/src. Already-unpacked trees are left untouched so `make build`
# works offline.

set -euo pipefail

NAME="${1:?usage: fetch-package.sh <package>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="${ROOT}/packages/${NAME}"

[ -d "$PKG" ] || { echo "✗ unknown package: $NAME" >&2; exit 1; }

# Optional custom fetch (e.g. packages/doom from IR0_ROOT — no tarball).
if [ -x "$PKG/fetch.sh" ] || [ -f "$PKG/fetch.sh" ]; then
	chmod +x "$PKG/fetch.sh"
	exec bash "$PKG/fetch.sh"
fi

URL="$(cat "$PKG/url")"
SRCROOT="$(cat "$PKG/srcroot")"
TARBALL="$(basename "$URL")"
# Upstream file names do not always match the archive URL (GitHub tag tarballs).
CHECKED_NAME="$(awk '{print $2}' "$PKG/sha256")"
[ -n "$CHECKED_NAME" ] && TARBALL="$CHECKED_NAME"

mkdir -p "$PKG/dist"

if [ ! -f "$PKG/dist/$TARBALL" ]; then
	echo "  FETCH   $NAME → $TARBALL"
	curl -fsSL "$URL" -o "$PKG/dist/$TARBALL"
fi

( cd "$PKG/dist" && \
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum -c "$PKG/sha256" >/dev/null
	elif command -v shasum >/dev/null 2>&1; then
		# macOS/some BSDs — accept if present on exotic hosts
		awk '{print $1"  "$2}' "$PKG/sha256" | shasum -a 256 -c >/dev/null
	else
		echo "✗ need sha256sum (or shasum) to verify $NAME" >&2
		exit 1
	fi )
echo "  FETCH   $NAME checksum OK"


if [ -d "$PKG/src" ]; then
	echo "  FETCH   $NAME already unpacked (packages/$NAME/src)"
	exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
tar -xf "$PKG/dist/$TARBALL" -C "$TMP"
[ -d "$TMP/$SRCROOT" ] || { echo "✗ $NAME: missing $SRCROOT in archive" >&2; exit 1; }
mv "$TMP/$SRCROOT" "$PKG/src"

chmod +x "$ROOT/scripts/apply-isd-patches.sh"
"$ROOT/scripts/apply-isd-patches.sh" "$NAME"

echo "✓ fetch $NAME OK"
