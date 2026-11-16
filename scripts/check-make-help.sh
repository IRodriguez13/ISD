#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Keep the Make interface honest: every target the Makefile defines must be
# classified in mk/targets.mk (public, internal, deprecated or selector), every
# public target must be described by `make help`, and every deprecated name
# must be an alias that names its replacement.
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
unset MAKEFLAGS MFLAGS

fail=0
err() { echo "✗ $*" >&2; fail=1; }

# Targets Make knows about without resolving a profile or probing a compiler.
db="$(make -pRrn help 2>/dev/null)"
defined="$(awk '
	/^# Not a target/ { skip = 1; next }
	/^[a-zA-Z0-9][a-zA-Z0-9_.-]*:([^=]|$)/ {
		if (!skip) { split($0, a, ":"); print a[1] }
	}
	{ skip = 0 }' <<<"$db" | grep -vx 'Makefile' | sort -u)"

classes="$(make -s targets 2>/dev/null)" || {
	err "make targets failed (mk/targets.mk missing?)"
	exit 1
}
help="$(make -s help)"

class_of() { awk -v t="$1" '$2 == t { print $1; exit }' <<<"$classes"; }

while IFS= read -r t; do
	[ -n "$t" ] || continue
	[ -n "$(class_of "$t")" ] || err "unclassified Make target: $t (add it to mk/targets.mk)"
done <<<"$defined"

while read -r class t replacement; do
	[ -n "${t:-}" ] || continue
	case "$t" in
	build-\<pkg\>) ;;
	*) grep -qx -- "$t" <<<"$defined" || err "$class target $t is not defined" ;;
	esac
	case "$class" in
	public)
		grep -Eq "^  ${t//./\\.}[[:space:]]+[^[:space:]]" <<<"$help" \
			|| err "public target $t has no description in make help"
		;;
	deprecated)
		[ -n "${replacement:-}" ] || { err "deprecated $t names no replacement"; continue; }
		out="$(awk -v t="$t" 'index($0, t ":") == 1' <<<"$db")"
		grep -qw -- "$replacement" <<<"$out" \
			|| err "deprecated $t is not an alias of $replacement"
		;;
	esac
done <<<"$classes"

[ "$fail" -eq 0 ] || exit 1
echo "✓ make help documents every public target; all targets classified"
