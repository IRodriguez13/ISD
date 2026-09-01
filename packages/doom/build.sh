#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Build IR0 doomgeneric (static musl) + stage IWAD for the desktop profile.
#
# Outputs (when IWAD available):
#   $PRODUCT_OUT/stage-bin/doom
#   $PRODUCT_OUT/doom-runtime/doom1.wad
#
# Without an IWAD: do not compile Doom. Prompt (TTY) whether to continue
# the ISD build without Doom until the tester provides one.
#
# Env:
#   ISD_DOOM_IWAD=/path/to/doom1.wad   — optional; else scripts/find-doom-iwad.sh
#   ISD_DOOM_REQUIRE=1                 — missing IWAD → hard fail (CI)
#   ISD_DOOM_SKIP=1                    — missing IWAD → skip, no prompt
#
# Sources: $IR0_ROOT/setup/doom/ (sibling kernel tree).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/toolchain.sh"

IR0_ROOT="${IR0_ROOT:-${ROOT}/../IR0}"
DOOM_DIR="${IR0_ROOT}/setup/doom"
PORT="${DOOM_DIR}/doomgeneric_ir0.c"
UPSTREAM="${DOOM_DIR}/upstream/doomgeneric"
OUT_DIR="${PRODUCT_OUT}/stage-bin"
RUNTIME="${PRODUCT_OUT}/doom-runtime"
FIND_IWAD="${ROOT}/scripts/find-doom-iwad.sh"

doom_skip()
{
	local why="$1"
	mkdir -p "$RUNTIME"
	rm -f "${OUT_DIR}/doom" "${RUNTIME}/doom1.wad"
	printf '%s\n' "$why" >"${RUNTIME}/SKIPPED"
	echo "  SKIP    doom ($why)"
	echo "  HINT    later: ISD_DOOM_IWAD=/path/to/doom1.wad \\"
	echo "          rm -f ${ROOT}/out/${ARCH}/stamps/packages/doom; \\"
	echo "          make build-doom PROFILE=desktop"
	echo "✓ doom skipped (rootfs will omit /usr/ken/games/doom)"
	exit 0
}

doom_ask_continue_without()
{
	# Non-interactive / CI defaults.
	case "${ISD_DOOM_REQUIRE:-0}" in
	1|y|Y|yes|YES)
		echo "✗ doom: no IWAD and ISD_DOOM_REQUIRE=1" >&2
		echo "  set ISD_DOOM_IWAD to an existing doom1.wad / DOOM.WAD" >&2
		exit 1
		;;
	esac
	case "${ISD_DOOM_SKIP:-0}" in
	1|y|Y|yes|YES)
		doom_skip "no IWAD (ISD_DOOM_SKIP=1)"
		;;
	esac

	if [ ! -t 0 ] || [ ! -t 1 ]; then
		echo "⚠ doom: no IWAD and no TTY — continuing without Doom" >&2
		echo "  set ISD_DOOM_IWAD=/path/to/doom1.wad to include it" >&2
		doom_skip "no IWAD (non-interactive)"
	fi

	echo ""
	echo "⚠ doom: no IWAD found."
	echo "  Desktop profile lists Doom, but the binary is not built without a WAD."
	echo "  Provide one with:  export ISD_DOOM_IWAD=/path/to/doom1.wad"
	echo ""
	printf "Continue building ISD without Doom until you have a WAD? [Y/n] "
	local ans
	read -r ans || ans=Y
	case "${ans:-Y}" in
	""|y|Y|yes|YES)
		doom_skip "no IWAD (user chose continue without Doom)"
		;;
	*)
		echo "✗ doom: aborted — set ISD_DOOM_IWAD and re-run make build" >&2
		exit 1
		;;
	esac
}

if [ ! -f "$PORT" ] || [ ! -d "$UPSTREAM" ]; then
	echo "✗ doom: missing IR0 sources (IR0_ROOT=${IR0_ROOT})" >&2
	echo "  expected ${PORT}" >&2
	exit 1
fi

# Resolve IWAD via shared finder (env, rootfs/local, ../universal-doom, …).
IWAD=""
if [ -x "$FIND_IWAD" ] || [ -f "$FIND_IWAD" ]; then
	IWAD="$("$FIND_IWAD" 2>/dev/null || true)"
fi
if [ -z "${IWAD:-}" ] || [ ! -f "$IWAD" ]; then
	doom_ask_continue_without
fi
echo "  DOOM    IWAD=${IWAD}"

mkdir -p "$OUT_DIR" "$RUNTIME"
rm -f "${RUNTIME}/SKIPPED"

shopt -s nullglob
SRCS=("$PORT" "$UPSTREAM"/*.c)
shopt -u nullglob
if [ "${#SRCS[@]}" -lt 2 ]; then
	echo "✗ doom: no upstream .c under $UPSTREAM" >&2
	exit 1
fi

echo "  DOOM    Building doomgeneric (IR0 port, ${TARGET_TRIPLE})..."
"$CC" -static -Os -s -ffunction-sections -fdata-sections \
	-Wl,--gc-sections -Wl,--strip-all -std=gnu99 \
	-DFASE55E_INTERACTIVE=1 -DIR0_DOOM_PORT -DFEATURE_SOUND \
	-I"$UPSTREAM" \
	"${SRCS[@]}" \
	-o "${OUT_DIR}/doom" -lm

if [ ! -x "${OUT_DIR}/doom" ]; then
	echo "✗ doom binary missing after build" >&2
	exit 1
fi
file "${OUT_DIR}/doom" | grep -q ELF

install -m 0644 "$IWAD" "${RUNTIME}/doom1.wad"
echo "✓ doom OK → ${OUT_DIR}/doom (+ IWAD ${RUNTIME}/doom1.wad from ${IWAD})"
