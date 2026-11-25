#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Content fingerprint of the UAPI headers IR0 would export for one ISA goal.
# Usage: uapi-fingerprint.sh IR0_ROOT GOAL
set -euo pipefail

ir0="${1:?usage: $0 IR0_ROOT GOAL}"
goal="${2:?usage: $0 IR0_ROOT GOAL}"

{
	echo "goal:${goal}"
	for d in includes/uapi "arch/${goal}/include/uapi"; do
		[ -d "${ir0}/${d}" ] || continue
		(cd "${ir0}/${d}" && find . -type f -print0 | LC_ALL=C sort -z \
			| xargs -0 -r sha256sum)
	done
} | sha256sum | cut -c1-16
