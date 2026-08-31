#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Build product and/or smoke service ELFs into separate output trees.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/toolchain.sh"
MODE="${1:-product}"
SVC="${ROOT}/services"
NATIVES="${ROOT}/natives"
LIB="${ROOT}/lib"
SYSROOT="${IR0_UAPI_SYSROOT:-${ROOT}/sysroot}"
AUTH_LIB="${LIB}/ir0_auth.c"
KEYMAP_LIB="${LIB}/ir0_keymap.c"
CFLAGS="-static -Os -I${LIB}"
[ -d "${SYSROOT}/usr/include" ] && CFLAGS="$CFLAGS -isystem ${SYSROOT}/usr/include"

PRODUCT_STAGE="${PRODUCT_OUT}/stage-bin"
SMOKE_STAGE="${SMOKE_OUT}/stage-bin"

# Native utilities live in natives/ and must build on Linux too (natives/README.md).
cc_native()
{
	local outdir="$1" name="$2" src="$3"
	shift 3
	# shellcheck disable=SC2086
	"$CC" $CFLAGS -o "${outdir}/${name}" "${NATIVES}/${src}" "$@"
}

cc_one()
{
	local outdir="$1" name="$2" src="$3"
	shift 3
	# shellcheck disable=SC2086
	"$CC" $CFLAGS -o "${outdir}/${name}" "${SVC}/${src}" "$@"
}

build_product()
{
	mkdir -p "$PRODUCT_STAGE"
	cc_one "$PRODUCT_STAGE" runit_stage1 runit_stage1.c
	cc_one "$PRODUCT_STAGE" runit_stage2 runit_stage2.c
	cc_one "$PRODUCT_STAGE" runit_stage3 runit_stage3.c
	cc_one "$PRODUCT_STAGE" runit_console_run runit_console_run.c "$AUTH_LIB" "$KEYMAP_LIB"
	cc_one "$PRODUCT_STAGE" runit_logger_run runit_logger_run.c
	cc_one "$PRODUCT_STAGE" fsck.ir0 fsck.ir0.c
	cc_one "$PRODUCT_STAGE" ir0_firstboot ir0_firstboot.c "$AUTH_LIB" "$KEYMAP_LIB"
	cc_one "$PRODUCT_STAGE" ir0_passwd ir0_passwd.c "$AUTH_LIB"
	cc_one "$PRODUCT_STAGE" ir0_adduser ir0_adduser.c "$AUTH_LIB"
	cc_one "$PRODUCT_STAGE" ir0_status ir0_status.c
	cc_native "$PRODUCT_STAGE" lsblk lsblk.c
	cc_one "$PRODUCT_STAGE" ir0_keymap ir0_keymap.c "$KEYMAP_LIB"
	cc_one "$PRODUCT_STAGE" ir0_recovery ir0_recovery.c
	cc_one "$PRODUCT_STAGE" mount_root_rw mount_root_rw.c
	cc_one "$PRODUCT_STAGE" runit_pause_run runit_pause_run.c
	# argv[0]-dispatch stand-ins for halt/poweroff/reboot under runit.
	cc_one "$PRODUCT_STAGE" ir0_force_power ir0_force_power.c
	# Optional network oneshot helper (product)
	if [ -f "${SVC}/ir0_network_run.c" ]; then
		cc_one "$PRODUCT_STAGE" ir0_network_run ir0_network_run.c
	fi
	for bin in "$PRODUCT_STAGE"/*; do
		[ -e "$bin" ] || continue
		# compat-links may leave smoke/package symlinks here; follow them.
		if ! file -L "$bin" 2>/dev/null | grep -q ELF; then
			echo "✗ not an ELF: $bin" >&2
			file -L "$bin" >&2 || true
			exit 1
		fi
	done
	echo "✓ build services product OK ($(ls -1 "$PRODUCT_STAGE" | wc -l) binaries)"
}

build_smoke()
{
	mkdir -p "$SMOKE_STAGE"
	cc_one "$SMOKE_STAGE" runit_fase55d_init runit_fase55d_init.c
	cc_one "$SMOKE_STAGE" runit_power_smoke runit_power_smoke.c
	cc_one "$SMOKE_STAGE" runit_power_run runit_power_run.c
	cc_one "$SMOKE_STAGE" runit_busybox_halt_smoke runit_busybox_halt_smoke.c
	cc_one "$SMOKE_STAGE" runit_busybox_poweroff_smoke runit_busybox_poweroff_smoke.c
	cc_one "$SMOKE_STAGE" runit_busybox_reboot_smoke runit_busybox_reboot_smoke.c
	cc_one "$SMOKE_STAGE" runit_hostshare_payload_run runit_hostshare_payload_run.c
	exec_run()
	{
		# shellcheck disable=SC2086
		"$CC" $CFLAGS -DRUNIT_EXEC_PATH="\"$2\"" -DRUNIT_START_TAG="\"$3\\n\"" \
			-o "${SMOKE_STAGE}/$1" "${SVC}/runit_exec_run.c"
	}
	exec_run runit_fase52_run /bin/f52-harness RUNSV_FASE52_START
	exec_run runit_tcc_power_run /bin/tccph RUNSV_TCC_POWER_START
	exec_run runit_fase55d_run /bin/doom-smoke RUNSV_FASE55D_START
	exec_run runit_busybox_halt_run /bin/bb-halt RUNSV_BUSYBOX_HALT_START
	exec_run runit_busybox_poweroff_run /bin/bb-pwroff RUNSV_BUSYBOX_POWEROFF_START
	exec_run runit_busybox_reboot_run /bin/bb-reboot RUNSV_BUSYBOX_REBOOT_START
	echo "✓ build services smoke OK ($(ls -1 "$SMOKE_STAGE" | wc -l) binaries)"
}

case "$MODE" in
product) build_product ;;
smoke) build_smoke ;;
all) build_product; build_smoke ;;
*) echo "usage: build-services.sh product|smoke|all" >&2; exit 1 ;;
esac
