#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Compose a finished rootfs tree (no MINIX knowledge).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:?usage: stage-rootfs.sh DEST_DIR}"
PROFILE="${IR0_PRODUCT_PROFILE:-minimal}"
ARCH="${ARCH:-x86_64}"
# shellcheck disable=SC1091
source "${ROOT}/scripts/toolchain.sh"
PRODUCT_OUT="${PRODUCT_OUT:-${ROOT}/out/${ARCH}/product}"
RUNIT_BIN="${PRODUCT_OUT}/bin"
STAGE_BIN="${PRODUCT_OUT}/stage-bin"
BUSYBOX="${PRODUCT_OUT}/busybox-full"
BUSYBOX_AUTH="${PRODUCT_OUT}/busybox-auth"
PROF_DIR="${ROOT}/profiles/${PROFILE}"
SETUID_ALLOW="${ROOT}/packages/setuid.allowlist"

if [ ! -f "${PROF_DIR}/profile.conf" ]; then
	echo "✗ unknown profile: $PROFILE (expected ${PROF_DIR}/profile.conf)" >&2
	exit 1
fi
# shellcheck disable=SC1090
source "${PROF_DIR}/profile.conf"

need_bin() {
	if [ ! -f "$1" ]; then
		echo "✗ missing $1 (run: make build ARCH=$ARCH)" >&2
		exit 1
	fi
}

need_bin "$RUNIT_BIN/runit"
need_bin "$RUNIT_BIN/runit-init"
need_bin "$STAGE_BIN/runit_stage1"
need_bin "$BUSYBOX"
need_bin "$BUSYBOX_AUTH"

rm -rf "$DEST"
mkdir -p "$DEST"

install_tree()
{
	local src="$1"
	[ -d "$src" ] || return 0
	cp -a "$src"/. "$DEST"/
}

# Layers: base → legacy etc → profile overlay → arch overlay → local (gitignored)
install_tree "${ROOT}/rootfs/base"
install_tree "${ROOT}/rootfs"
# Avoid copying old personal homes from legacy rootfs/home
rm -rf "${DEST}/home/ivan" 2>/dev/null || true
install_tree "${PROF_DIR}/overlay"
install_tree "${ROOT}/profiles/${PROFILE}/overlay"
install_tree "${ROOT}/rootfs/arch/${ARCH}"
install_tree "${ROOT}/rootfs/local"

# Directories with required modes
mkdir -p \
	"${DEST}/bin" "${DEST}/sbin" "${DEST}/usr/bin" "${DEST}/usr/sbin" \
	"${DEST}/etc" "${DEST}/dev" "${DEST}/proc" "${DEST}/sys" "${DEST}/heart" \
	"${DEST}/run" "${DEST}/run/doas" "${DEST}/tmp" "${DEST}/var/log" "${DEST}/var/lib/ir0" \
	"${DEST}/home" "${DEST}/root" "${DEST}/mnt" \
	"${DEST}/usr/ken" "${DEST}/usr/ken/games" "${DEST}/usr/share/doom" \
	"${DEST}/usr/share/man" "${DEST}/usr/share/man/cat7" \
	"${DEST}/etc/runit/sv/console" "${DEST}/etc/runit/sv/logger" \
	"${DEST}/etc/service" "${DEST}/etc/skel" \
	"${DEST}/usr/lib/ir0/defaults" "${DEST}/etc/network"
chmod 01777 "${DEST}/tmp"
chmod 0755 "${DEST}/run"
chmod 0700 "${DEST}/root"

# Version / os-release from single VERSION file
VER="$(tr -d ' \n' < "${ROOT}/VERSION")"
BUILD_ID="${SOURCE_DATE_EPOCH:-$(date -u +%Y%m%d)}"
cat > "${DEST}/etc/os-release" <<EOF
NAME="ISD"
ID=isd
PRETTY_NAME="ISD 0.1 — IR0 Software Distribution"
VERSION_ID="0.1"
KERNEL_NAME="IR0"
KERNEL_VERSION="${VER}"
HOME_URL="https://github.com/IRodriguez13/IR0"
BUILD_ID="${BUILD_ID}"
ARCH="${ARCH}"
PROFILE="${PROFILE}"
EOF

printf '%s\n' "$PROFILE" > "${DEST}/etc/ir0-profile"
[ -f "${DEST}/etc/hostname" ] || echo ir0 > "${DEST}/etc/hostname"
[ -f "${DEST}/etc/hosts" ] || printf '127.0.0.1\tlocalhost ir0\n::1\tlocalhost\n' > "${DEST}/etc/hosts"
[ -f "${DEST}/etc/shells" ] || printf '/bin/sh\n/bin/ash\n' > "${DEST}/etc/shells"
[ -f "${DEST}/etc/console.conf" ] || cat > "${DEST}/etc/console.conf" <<'EOF'
DEVICE=/dev/console
TERM=linux
LOGIN_ENABLED=yes
BANNER=yes
EOF
[ -f "${DEST}/etc/network/interfaces" ] || cat > "${DEST}/etc/network/interfaces" <<EOF
# NETWORK_MODE=${NETWORK_MODE:-none}
auto lo
iface lo inet loopback
EOF

# Product binaries
install -m 0755 "$RUNIT_BIN/runit-init" "${DEST}/sbin/init"
install -m 0755 "$RUNIT_BIN/runit" "${DEST}/sbin/runit"
install -m 0755 "$RUNIT_BIN/runit-init" "${DEST}/bin/runit-init"
install -m 0755 "$RUNIT_BIN/runsvdir" "${DEST}/bin/runsvdir"
install -m 0755 "$RUNIT_BIN/runsv" "${DEST}/bin/runsv"
install -m 0755 "$RUNIT_BIN/sv" "${DEST}/bin/sv"
install -m 0755 "$STAGE_BIN/fsck.ir0" "${DEST}/sbin/fsck.ir0"
install -m 0755 "$STAGE_BIN/ir0_firstboot" "${DEST}/sbin/ir0-firstboot"
install -m 0755 "$STAGE_BIN/ir0_recovery" "${DEST}/sbin/ir0-recovery"
install -m 0755 "$STAGE_BIN/mount_root_rw" "${DEST}/sbin/mount-root-rw"
install -m 0755 "$STAGE_BIN/ir0_status" "${DEST}/bin/ir0-status"
# BusyBox has no lsblk applet; ship the product one.
install -m 0755 "$STAGE_BIN/lsblk" "${DEST}/bin/lsblk"
if [ -x "$STAGE_BIN/ir0_keymap" ]; then
	install -m 0755 "$STAGE_BIN/ir0_keymap" "${DEST}/usr/bin/keymap"
	ln -sf ../usr/bin/keymap "${DEST}/bin/keymap"
fi
if [ -f "$STAGE_BIN/ir0_force_power" ]; then
	install -m 0755 "$STAGE_BIN/ir0_force_power" "${DEST}/bin/poweroff"
	ln -f "${DEST}/bin/poweroff" "${DEST}/bin/halt"
	ln -f "${DEST}/bin/poweroff" "${DEST}/bin/reboot"
fi
install -m 04755 "$STAGE_BIN/ir0_passwd" "${DEST}/bin/passwd"
install -m 04755 "$STAGE_BIN/ir0_adduser" "${DEST}/usr/sbin/adduser"
ln -f "${DEST}/usr/sbin/adduser" "${DEST}/sbin/adduser"
install -m 0755 "$BUSYBOX" "${DEST}/bin/busybox"
install -m 04755 "$BUSYBOX_AUTH" "${DEST}/usr/bin/busybox-auth"
ln -f "${DEST}/usr/bin/busybox-auth" "${DEST}/bin/login"
ln -f "${DEST}/usr/bin/busybox-auth" "${DEST}/bin/su"

# BusyBox applet links from profile applets list
MANIFEST="${PROF_DIR}/applets.txt"
if [ ! -f "$MANIFEST" ]; then
	MANIFEST="${ROOT}/packages/busybox/required_applets.txt"
fi
# Snapshot the applet list once instead of per applet.
#
# `busybox --list | grep -qx "$ap"` is unsafe under `set -o pipefail`: grep -q
# exits on the first match, busybox then dies of SIGPIPE (141) and the pipeline
# reports failure even though the applet is present. With 131 applets the list
# fit in a single write and the race stayed hidden; at 386 it rejected a
# different, perfectly present applet on nearly every run.
BB_APPLETS="$("${DEST}/bin/busybox" --list)"

link_applet() {
	local ap="$1"
	[ -n "$ap" ] || return 0
	[ "$ap" = "busybox" ] && return 0
	case $'\n'"${BB_APPLETS}"$'\n' in
	*$'\n'"${ap}"$'\n'*) ;;
	*)
		echo "✗ applet '$ap' not in busybox-full — rebuild packages/busybox" >&2
		return 1
		;;
	esac
	ln -f "${DEST}/bin/busybox" "${DEST}/bin/${ap}"
}
while read -r ap; do
	[[ "$ap" =~ ^#.*$ || -z "$ap" ]] && continue
	link_applet "$ap" || exit 1
done < "$MANIFEST"

# Optional applets from .isdconfig (CONFIG_APPLET_*=y)
ISD_CFG="${ISD_CONFIG:-${ROOT}/.isdconfig}"
if [ -f "$ISD_CFG" ]; then
	while IFS= read -r line || [ -n "${line:-}" ]; do
		[[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
		case "$line" in
		CONFIG_APPLET_*=y|CONFIG_APPLET_*=Y)
			key="${line%%=*}"
			name="${key#CONFIG_APPLET_}"
			ap="$(echo "$name" | tr '[:upper:]' '[:lower:]')"
			link_applet "$ap" || exit 1
			;;
		esac
	done <"$ISD_CFG"
fi

install -m 0755 "$STAGE_BIN/runit_stage1" "${DEST}/etc/runit/1"
install -m 0755 "$STAGE_BIN/runit_stage2" "${DEST}/etc/runit/2"
install -m 0755 "$STAGE_BIN/runit_stage3" "${DEST}/etc/runit/3"
install -m 0755 "$STAGE_BIN/runit_console_run" "${DEST}/etc/runit/sv/console/run"
install -m 0755 "$STAGE_BIN/runit_logger_run" "${DEST}/etc/runit/sv/logger/run"

# Enable services from profile
while read -r svc; do
	[[ "$svc" =~ ^#.*$ || -z "$svc" ]] && continue
	ln -sfr "${DEST}/etc/runit/sv/${svc}" "${DEST}/etc/service/${svc}"
done < "${PROF_DIR}/services.txt"

# Optional packages: ISD_PACKAGES_MANIFEST (resolved set) wins; legacy
# INSTALL_* from profile.conf remains a fallback. Binary must exist.
manifest_has() {
	local name="$1"
	[ -n "${ISD_PACKAGES_MANIFEST:-}" ] || return 1
	case " ${ISD_PACKAGES_MANIFEST} " in
	*" ${name} "*) return 0 ;;
	*) return 1 ;;
	esac
}

if [ -f "${STAGE_BIN}/doas" ] && { manifest_has opendoas || [ "${INSTALL_DOAS:-0}" = "1" ]; }; then
	install -m 04755 "${STAGE_BIN}/doas" "${DEST}/usr/bin/doas"
	install -m 0440 "${ROOT}/rootfs/base/etc/doas.conf" "${DEST}/etc/doas.conf" 2>/dev/null || \
		install -m 0440 "${ROOT}/rootfs/etc/doas.conf" "${DEST}/etc/doas.conf"
fi
if [ -f "${STAGE_BIN}/nano" ] && { manifest_has nano || [ "${INSTALL_NANO:-0}" = "1" ]; }; then
	install -m 0755 "${STAGE_BIN}/nano" "${DEST}/usr/bin/nano"
fi
if [ -f "${STAGE_BIN}/iv" ] && manifest_has iv; then
	install -m 0755 "${STAGE_BIN}/iv" "${DEST}/usr/bin/iv"
	ln -sf ../usr/bin/iv "${DEST}/bin/iv"
fi
if manifest_has pack-extract; then
	if [ -f "${STAGE_BIN}/pack" ]; then
		install -m 0755 "${STAGE_BIN}/pack" "${DEST}/usr/bin/pack"
		ln -sf ../usr/bin/pack "${DEST}/bin/pack"
	fi
	if [ -f "${STAGE_BIN}/unpack" ]; then
		install -m 0755 "${STAGE_BIN}/unpack" "${DEST}/usr/bin/unpack"
		ln -sf ../usr/bin/unpack "${DEST}/bin/unpack"
	fi
	# `extract` is the pre-1.6 name, kept as an alias.
	if [ -f "${STAGE_BIN}/extract" ]; then
		install -m 0755 "${STAGE_BIN}/extract" "${DEST}/usr/bin/extract"
		ln -sf ../usr/bin/extract "${DEST}/bin/extract"
	fi
fi
if [ -f "${STAGE_BIN}/make" ] && manifest_has gnumake; then
	install -m 0755 "${STAGE_BIN}/make" "${DEST}/usr/bin/make"
	ln -sf ../usr/bin/make "${DEST}/bin/make"
fi
if manifest_has tinycc; then
	TCC_RT="${PRODUCT_OUT}/tcc-runtime"
	if [ -x "${STAGE_BIN}/tcc" ]; then
		install -m 0755 "${STAGE_BIN}/tcc" "${DEST}/usr/bin/tcc"
		ln -sf ../usr/bin/tcc "${DEST}/bin/tcc"
	fi
	if [ -d "${TCC_RT}/lib/tcc" ]; then
		mkdir -p "${DEST}/lib/tcc"
		cp -a "${TCC_RT}/lib/tcc/." "${DEST}/lib/tcc/"
	fi
	if [ -d "${TCC_RT}/usr/lib" ]; then
		mkdir -p "${DEST}/usr/lib"
		cp -a "${TCC_RT}/usr/lib/." "${DEST}/usr/lib/"
	fi
	if [ -d "${TCC_RT}/usr/include" ]; then
		mkdir -p "${DEST}/usr/include"
		cp -a "${TCC_RT}/usr/include/." "${DEST}/usr/include/"
	fi
fi
if manifest_has doom; then
	if [ -x "${STAGE_BIN}/doom" ]; then
		install -m 0755 "${STAGE_BIN}/doom" "${DEST}/usr/ken/games/doom"
		ln -sf ../ken/games/doom "${DEST}/usr/bin/doom"
		ln -sf ../usr/ken/games/doom "${DEST}/bin/doom"
		ln -sf ../usr/ken/games/doom "${DEST}/bin/doomgeneric"
	fi
	DOOM_RT="${PRODUCT_OUT}/doom-runtime"
	if [ -f "${DOOM_RT}/doom1.wad" ]; then
		install -m 0644 "${DOOM_RT}/doom1.wad" "${DEST}/usr/share/doom/doom1.wad"
		install -m 0644 "${DOOM_RT}/doom1.wad" "${DEST}/usr/ken/games/doom1.wad"
	fi
fi

# Account policy by profile
case "$PROFILE" in
minimal|desktop|appliance)
	install -m 0644 "${ROOT}/rootfs/base/etc/passwd" "${DEST}/etc/passwd"
	install -m 0600 "${ROOT}/rootfs/base/etc/shadow" "${DEST}/etc/shadow"
	install -m 0644 "${ROOT}/rootfs/base/etc/group" "${DEST}/etc/group"
	rm -f "${DEST}/etc/ir0-autologin"
	;;
development)
	# Lab overlay from fixtures — never the maintainer identity in base.
	install -m 0644 "${ROOT}/tests/fixtures/development/passwd" "${DEST}/etc/passwd"
	install -m 0600 "${ROOT}/tests/fixtures/development/shadow" "${DEST}/etc/shadow"
	install -m 0644 "${ROOT}/tests/fixtures/development/group" "${DEST}/etc/group"
	printf 'root\n' > "${DEST}/etc/ir0-autologin"
	mkdir -p "${DEST}/home/labuser"
	chmod 0700 "${DEST}/home/labuser"
	;;
esac

if [ "$PROFILE" = "desktop" ] || [ "${ROOT_POLICY:-}" = "noroot_login" ]; then
	printf '1\n' > "${DEST}/etc/ir0-noroot"
fi
if [ "$PROFILE" = "appliance" ]; then
	printf '1\n' > "${DEST}/etc/ir0-noroot"
fi
if [ "${FSCK_ON_BOOT:-1}" = "0" ]; then
	printf '1\n' > "${DEST}/etc/ir0-skip-fsck"
fi

if [ -f "${ROOT}/packages/busybox/bb_status.tsv" ]; then
	mkdir -p "${DEST}/etc/busybox"
	install -m 0644 "${ROOT}/packages/busybox/bb_status.tsv" \
		"${DEST}/etc/busybox/bb_status.tsv"
fi

# BusyBox FEATURE_MTAB_SUPPORT uses /etc/mtab; without it, df/mount use /proc/mounts.
# Symlink keeps both paths consistent for applets that still open /etc/mtab.
ln -sfn /proc/mounts "${DEST}/etc/mtab"

# Optional guest mandocs (host prepare-guest-mandocs → build/guest-man/usr/share/man/cat7)
if [ -n "${IR0_GUEST_MANDOC_DIR:-}" ]; then
	man_src="${IR0_GUEST_MANDOC_DIR}/usr/share/man/cat7"
	if [ ! -d "$man_src" ] && [ -d "${IR0_GUEST_MANDOC_DIR}/cat7" ]; then
		man_src="${IR0_GUEST_MANDOC_DIR}/cat7"
	fi
	if [ -d "$man_src" ]; then
		mkdir -p "${DEST}/usr/share/man/cat7"
		cp -a "${man_src}/." "${DEST}/usr/share/man/cat7/" || true
	fi
fi

# Setuid allowlist enforcement
if [ -f "$SETUID_ALLOW" ]; then
	while IFS= read -r path; do
		[[ "$path" =~ ^#.*$ || -z "$path" ]] && continue
		f="${DEST}${path}"
		if [ -e "$f" ]; then
			mode=$(stat -c '%a' "$f")
			case "$mode" in
			4*|2*|6*) ;;
			*) echo "✗ declared setuid missing bit: $path mode=$mode" >&2; exit 1 ;;
			esac
		fi
	done < "$SETUID_ALLOW"
	# Fail on unexpected setuid
	while IFS= read -r -d '' f; do
		rel="/${f#"${DEST}/"}"
		if ! grep -qxF "$rel" "$SETUID_ALLOW"; then
			echo "✗ undeclared setuid file: $rel" >&2
			exit 1
		fi
	done < <(find "$DEST" -perm -4000 -print0 2>/dev/null || true)
fi

# build-info
mkdir -p "${DEST}/usr/lib/ir0"
{
	echo "PROFILE=${PROFILE}"
	echo "ARCH=${ARCH}"
	echo "VERSION=${VER}"
	echo "BUILD_ID=${BUILD_ID}"
	[ -f "${SYSROOT}/usr/share/ir0/uapi-release.txt" ] && cat "${SYSROOT}/usr/share/ir0/uapi-release.txt"
} > "${DEST}/usr/lib/ir0/build-info"

echo "✓ rootfs-tree ${DEST}"
