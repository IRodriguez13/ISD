#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Print one "<pkg>:<dep>:<dep>..." word per package of the argument
# list that declares DEPENDS in packages/<pkg>/package.conf.  package.conf is
# the only place a build-order edge is written; the Makefile derives its
# stamp prerequisites from this output.
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
for pkg in "$@"; do
	deps="$(sed -n 's/^DEPENDS=//p' "${ROOT}/packages/${pkg}/package.conf" 2>/dev/null || true)"
	[ -n "$deps" ] && echo "${pkg}:${deps// /:}"
done
exit 0
