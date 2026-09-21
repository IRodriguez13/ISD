#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
exec "${ROOT}/scripts/pack-minix.sh" "$@"
