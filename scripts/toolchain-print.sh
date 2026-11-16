#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Print Make assignments for the resolved toolchain.  Output paths are owned
# by mk/paths.mk (variant-scoped); never re-emit them here.
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/toolchain.sh"
cat <<EOF
CC := ${CC}
TARGET_TRIPLE := ${TARGET_TRIPLE}
AR := ${AR}
RANLIB := ${RANLIB}
STRIP := ${STRIP}
READELF := ${READELF}
OBJCOPY := ${OBJCOPY}
MUSL_CC := ${CC}
EOF
