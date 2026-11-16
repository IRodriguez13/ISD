#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Print Make assignments for the resolved toolchain.
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
PRODUCT_OUT := ${PRODUCT_OUT}
TESTS_OUT := ${TESTS_OUT}
SMOKE_OUT := ${SMOKE_OUT}
ROOTFS_OUT := ${ROOTFS_OUT}
OUT_ARCH := ${OUT_ARCH}
MUSL_CC := ${CC}
EOF
