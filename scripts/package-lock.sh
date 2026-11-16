#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Serialize mutations of one package source tree across ISA builds.
set -euo pipefail

LOCK_PATH="${1:?usage: package-lock.sh LOCK_PATH -- COMMAND [ARG…]}"
shift
[ "${1:-}" = "--" ] || {
	echo "✗ package-lock.sh: expected -- before command" >&2
	exit 2
}
shift
[ "$#" -gt 0 ] || {
	echo "✗ package-lock.sh: missing command" >&2
	exit 2
}

mkdir -p "$(dirname "$LOCK_PATH")"
if command -v flock >/dev/null 2>&1; then
	(
		flock 9
		exec "$@"
	) 9>"$LOCK_PATH"
	exit $?
fi

# Portable fallback for hosts without util-linux flock. A bounded wait avoids
# a stale lock consuming the machine forever after a killed build.
LOCK_DIR="${LOCK_PATH}.dir"
attempt=0
until mkdir "$LOCK_DIR" 2>/dev/null; do
	attempt=$((attempt + 1))
	if [ "$attempt" -ge 300 ]; then
		echo "✗ timed out waiting for package lock: $LOCK_PATH" >&2
		exit 1
	fi
	sleep 1
done
trap 'rmdir "$LOCK_DIR"' EXIT HUP INT TERM
"$@"
