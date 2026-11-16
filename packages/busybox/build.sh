#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Build BusyBox variants.  The top-level graph serializes mutations of this
# shared source directory across ISA builds.
# Outputs land under out/<arch>/product/.
set -euo pipefail
JOBS="${ISD_JOBS:-2}"

ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/toolchain.sh"
PKG="${ROOT}/packages/busybox"
SRC="${PKG}/src"
OUT_DIR="${PRODUCT_OUT:-${ROOT}/out/${ARCH}/product}"

if [ ! -f "$SRC/Makefile" ]; then
	echo "✗ missing BusyBox source; run: make fetch" >&2
	exit 1
fi

# ISD used to carry three IR0-specific BusyBox edits (utmp scanning, console
# colour and shell completion).  They are deliberately retired: IR0 must run
# unmodified Linux userspace.  Existing developer source caches can still
# contain those edits, so restore only their known upstream files once from
# the checksum-verified tarball. Fresh source trees are left untouched.
restore_legacy_ir0_edits()
{
	local archive="${PKG}/dist/busybox-1.36.1.tar.bz2"
	local top="busybox-1.36.1"
	local changed=0
	local file

	if grep -q 'bb_get_applet_usage' "${SRC}/include/libbb.h" 2>/dev/null || \
		grep -q 'IR0 soft FB palette' "${SRC}/coreutils/ls.c" 2>/dev/null || \
		grep -q 'fopen("/var/run/utmp"' "${SRC}/procps/uptime.c" 2>/dev/null; then
		changed=1
	fi
	[ "$changed" -eq 1 ] || return 0
	[ -f "$archive" ] || {
		echo "✗ BusyBox legacy source migration needs ${archive}; run: make fetch" >&2
		exit 1
	}
	for file in include/libbb.h libbb/appletlib.c libbb/lineedit.c \
		procps/uptime.c coreutils/ls.c; do
		tar -xOf "$archive" "${top}/${file}" > "${SRC}/${file}"
	done
	echo "  BUSYBOX restored upstream sources (retired IR0-specific edits)"
}

restore_legacy_ir0_edits

mkdir -p "$OUT_DIR"
chmod +x "${ROOT}/scripts/busybox_apply_fragment.sh"

build_variant()
{
	local fragment="$1"
	local out="$2"

	echo "  BUSYBOX Building $(basename "$out") ARCH=${ARCH}"
	"${ROOT}/scripts/busybox_apply_fragment.sh" "$SRC" "$fragment"
	# Consume only the target UAPI exported by IR0.  Never borrow /usr/include:
	# that would silently make an aarch64 image depend on the build host's x86
	# kernel ABI.  -idirafter preserves musl's libc-owned headers when a Linux
	# UAPI name overlaps with one of them.
	local uapi="${PKG}/.linux-uapi"
	rm -rf "$uapi"
	mkdir -p "$uapi"
	[ -d "${SYSROOT}/usr/include/linux" ] || {
		echo "✗ IR0 target UAPI missing: ${SYSROOT}/usr/include/linux" >&2
		exit 1
	}
	ln -sfn "${SYSROOT}/usr/include/linux" "${uapi}/linux"
	[ -d "${SYSROOT}/usr/include/asm" ] && ln -sfn "${SYSROOT}/usr/include/asm" "${uapi}/asm"
	[ -d "${SYSROOT}/usr/include/asm-generic" ] && ln -sfn "${SYSROOT}/usr/include/asm-generic" "${uapi}/asm-generic"
	[ -d "${SYSROOT}/usr/include/mtd" ] && ln -sfn "${SYSROOT}/usr/include/mtd" "${uapi}/mtd"
	# Upstream BusyBox emits -Wunused-result / -Wformat-security noise (target
	# and host helpers like applets/usage); keep our tree log clean.
	local bb_cflags="-fno-pie -Wno-unused-result -Wno-format-security -idirafter ${uapi}"
	local bb_hostcflags="-Wno-unused-result -Wno-format-security"
	make -C "$SRC" CC="$CC" -s clean >/dev/null 2>&1 || true
	make -C "$SRC" CC="$CC" CFLAGS="$bb_cflags" HOSTCFLAGS="$bb_hostcflags" \
		LDFLAGS="-no-pie" -s -j"$JOBS"
	cp -f "$SRC/busybox" "$out"
	# Do not `file | grep -q`: pipefail + SIGPIPE is 141 on a first pack.
	case "$(file -b "$out")" in
	*ELF*) ;;
	*)
		echo "✗ busybox output is not ELF: $(file -b "$out")" >&2
		exit 1
		;;
	esac
}

(
	build_variant "${PKG}/ir0_full.config" "${OUT_DIR}/busybox-full"
	full_list="$("${OUT_DIR}/busybox-full" --list)"
	case $'\n'"${full_list}"$'\n' in
	*$'\n'sh$'\n'*) ;;
	*)
		echo "✗ busybox-full missing sh applet" >&2
		exit 1
		;;
	esac
	case $'\n'"${full_list}"$'\n' in
	*$'\n'login$'\n'*|*$'\n'su$'\n'*|*$'\n'passwd$'\n'*)
		echo "✗ privileged applet inside the general binary" >&2
		exit 1
		;;
	esac
	applet_n=0
	while IFS= read -r _; do
		[ -n "$_" ] && applet_n=$((applet_n + 1))
	done <<EOF
${full_list}
EOF
	echo "✓ busybox-full OK (${applet_n} applets)"

	build_variant "${PKG}/ir0_auth.config" "${OUT_DIR}/busybox-auth"
	auth_list="$(mktemp "${TMPDIR:-/tmp}/ir0-bb-auth.XXXXXX")"
	"${OUT_DIR}/busybox-auth" --list | sort > "$auth_list"
	printf 'login\nsu\n' | sort | diff -u - "$auth_list" >/dev/null || {
		echo "✗ auth binary applet set drifted (expected login + su only)" >&2
		rm -f "$auth_list"
		exit 1
	}
	rm -f "$auth_list"
	echo "✓ busybox-auth OK (login, su)"
)
