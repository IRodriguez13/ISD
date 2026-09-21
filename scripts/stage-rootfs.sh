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
# Fallback when PRODUCT_OUT is not passed (variant-aware layout).
if [ -z "${PRODUCT_OUT:-}" ]; then
	_variant_id="$(PROFILE="${PROFILE}" ARCH="${ARCH}" IR0_ROOT="${IR0_ROOT:-}" \
		bash "${ROOT}/scripts/compute-variant-id.sh" 2>/dev/null || echo "${PROFILE}")"
	PRODUCT_OUT="${ROOT}/out/${ARCH}/variants/${_variant_id}/product"
fi
RUNIT_BIN="${PRODUCT_OUT}/bin"
STAGE_BIN="${PRODUCT_OUT}/stage-bin"
STAGE_SCRIPTS="${PRODUCT_OUT}/stage-scripts"
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
	"${DEST}/var/run" \
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

# BusyBox exposes one invariant command surface in every product profile.
# Profiles select packages/services/policy, never BusyBox applets. Snapshot the
# binary's authoritative list once instead of maintaining divergent manifests.
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
	# MINIX v1 names are 14 bytes; skip overlong applets (cannot argv0 on disk).
	if [ "${#ap}" -gt 14 ]; then
		echo "  SKIP    applet '$ap' (name >14 chars; MINIX v1 limit)" >&2
		return 0
	fi
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
	[ -n "$ap" ] || continue
	link_applet "$ap" || exit 1
done <<< "$BB_APPLETS"

# Optional applets from the profile-local configuration.
ISD_CFG="${ISD_CONFIG:-${ROOT}/.isdconfig.d/${PROFILE}}"
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
if manifest_has tinyx && [ -x "${STAGE_BIN}/Xfbdev" ]; then
	mkdir -p "${DEST}/usr/bin"
	# TinyX performs the Linux VT/KD/framebuffer setup itself and drops back to
	# the invoking uid after initialization.  Its upstream LinuxInit path
	# therefore requires the server entry point to be setuid-root.
	install -m 4755 "${STAGE_BIN}/Xfbdev" "${DEST}/usr/bin/Xfbdev"
	ln -sf Xfbdev "${DEST}/usr/bin/X"
fi
if manifest_has xinit && [ -x "${STAGE_BIN}/xinit" ]; then
	mkdir -p "${DEST}/usr/bin" "${DEST}/etc/X11/xinit"
	install -m 0755 "${STAGE_BIN}/xinit" "${DEST}/usr/bin/xinit"
	install -m 0755 "${STAGE_SCRIPTS}/startx" "${DEST}/usr/bin/startx"
	cat > "${DEST}/etc/X11/xinit/xinitrc" <<'EOF'
#!/bin/sh
# IR0 desktop session assembled exclusively from unmodified X.Org clients.
if [ -f /usr/share/backgrounds/ir0desk.xbm ]; then
	/usr/bin/xsetroot -bitmap /usr/share/backgrounds/ir0desk.xbm \
	    -fg '#78909c' -bg '#263238' -name 'IR0 Desktop'
else
	/usr/bin/xsetroot -mod 3 3 -fg '#78909c' -bg '#263238'
fi
sleep 1
/usr/bin/xclock -geometry 100x100+12+12 \
    -bg '#263238' -fg '#eceff1' -bd '#87a9b5' &
sleep 1
/usr/bin/xmessage -timeout 0 -buttons "One:0","Two:0","Three:0","Four:0" \
    -geometry 280x32+372-58 -bg '#263238' -fg '#eceff1' -bd '#87a9b5' ' ' &
sleep 1
/usr/bin/xeyes -geometry 150x90-22+150 &
sleep 1
/usr/bin/xlogo -geometry 160x120-24-30 &
sleep 1
/usr/bin/xcalc -geometry 226x304-210+170 &
sleep 1
(/usr/bin/xterm -ls -fa 9x15 -fb 9x15bold -geometry 100x30+42+72 \
    -title "IR0 Terminal" || \
 /usr/bin/xterm -ls -geometry 100x30+42+72 -title "IR0 Terminal") &
sleep 1
(/usr/bin/xterm -fa 9x15 -fb 9x15bold -geometry 72x16+520+300 \
    -title "IR0 Chat" -e /bin/sh -c 'echo IR0 Chat AST-4 pending; exec /bin/sh' || \
 /usr/bin/xterm -geometry 72x16+520+300 -title "IR0 Chat" \
    -e /bin/sh -c 'echo IR0 Chat AST-4 pending; exec /bin/sh') &
if [ -f /etc/X11/twm/system.twmrc ]; then
	exec /usr/bin/twm -f /etc/X11/twm/system.twmrc
fi
exec /usr/bin/twm
EOF
	chmod 0755 "${DEST}/etc/X11/xinit/xinitrc"
fi
if manifest_has xauth && [ -x "${STAGE_BIN}/xauth" ]; then
	install -m 0755 "${STAGE_BIN}/xauth" "${DEST}/usr/bin/xauth"
fi
for xclient in twm xterm xclock xeyes xlogo xcalc xmessage xload xsetroot; do
	if manifest_has "$xclient" && [ -x "${STAGE_BIN}/${xclient}" ]; then
		install -m 0755 "${STAGE_BIN}/${xclient}" "${DEST}/usr/bin/${xclient}"
	fi
done
if manifest_has xterm; then
	xterm_defaults="${ROOT}/packages/xterm/prefix/${ARCH}/etc/X11/app-defaults"
	if [ -d "$xterm_defaults" ]; then
		mkdir -p "${DEST}/etc/X11/app-defaults" "${DEST}/usr/share/X11/app-defaults"
		for ad in XTerm XTerm-color; do
			if [ -f "${xterm_defaults}/${ad}" ]; then
				install -m 0644 "${xterm_defaults}/${ad}" \
					"${DEST}/etc/X11/app-defaults/${ad}"
				install -m 0644 "${xterm_defaults}/${ad}" \
					"${DEST}/usr/share/X11/app-defaults/${ad}"
			fi
		done
	fi
fi
if manifest_has ncurses; then
	terminfo_src="${ROOT}/packages/ncurses/prefix/${ARCH}/share/terminfo"
	if [ ! -d "$terminfo_src" ]; then
		terminfo_src="${ROOT}/packages/ncurses/prefix/${ARCH}/usr/share/terminfo"
	fi
	if [ -d "$terminfo_src" ]; then
		mkdir -p "${DEST}/usr/share"
		rm -rf "${DEST}/usr/share/terminfo"
		cp -a "$terminfo_src" "${DEST}/usr/share/terminfo"
	fi
fi
for xclient in xlogo xcalc xmessage xload; do
	app_defaults="${ROOT}/packages/${xclient}/prefix/${ARCH}/usr/share/X11/app-defaults"
	if manifest_has "$xclient" && [ -d "$app_defaults" ]; then
		mkdir -p "${DEST}/usr/share/X11/app-defaults"
		find "$app_defaults" -maxdepth 1 -type f -exec \
			install -m 0644 '{}' "${DEST}/usr/share/X11/app-defaults/" \;
	fi
done
if manifest_has font-misc-misc && [ -d "${PRODUCT_OUT}/stage-x11-fonts" ]; then
	mkdir -p "${DEST}/usr/share/fonts/X11"
	cp -a "${PRODUCT_OUT}/stage-x11-fonts/." "${DEST}/usr/share/fonts/X11/"
	font_dir="${DEST}/usr/share/fonts/X11/misc"
	count=0
	: > "${font_dir}/fonts.dir"
	for bdf in "${font_dir}"/*.bdf; do
		[ -f "$bdf" ] || continue
		xlfd="$(sed -n 's/^FONT[[:space:]]\+//p' "$bdf" | head -n 1)"
		[ -n "$xlfd" ] || { echo "✗ font has no XLFD: $bdf" >&2; exit 1; }
		printf '%s %s\n' "$(basename "$bdf")" "$xlfd" >> "${font_dir}/fonts.dir"
		count=$((count + 1))
	done
	sed -i "1i${count}" "${font_dir}/fonts.dir"
	fixed_xlfd="$(sed -n 's/^FONT[[:space:]]\+//p' "${font_dir}/6x13.bdf" | head -n 1)"
	printf 'fixed %s\n' "$fixed_xlfd" > "${font_dir}/fonts.alias"
	for bdf in "${font_dir}"/*.bdf; do
		xlfd="$(sed -n 's/^FONT[[:space:]]\+//p' "$bdf" | head -n 1)"
		case "$xlfd" in
			*-ISO10646-1|*-iso10646-1) ;;
			*) continue ;;
		esac
		short_name="$(basename "$bdf" .bdf)"
		latin1_xlfd="$(printf '%s\n' "$xlfd" | sed 's/-ISO10646-1$/-ISO8859-1/I')"
		printf '%s %s\n%s %s\n' "$short_name" "$xlfd" \
			"$latin1_xlfd" "$xlfd" >> "${font_dir}/fonts.alias"
	done
fi
if manifest_has font-adobe-75dpi && [ -d "${DEST}/usr/share/fonts/X11/75dpi" ]; then
	font_dir="${DEST}/usr/share/fonts/X11/75dpi"
	count=0
	: > "${font_dir}/fonts.dir"
	for bdf in "${font_dir}"/*.bdf; do
		[ -f "$bdf" ] || continue
		xlfd="$(sed -n 's/^FONT[[:space:]]\+//p' "$bdf" | head -n 1)"
		[ -n "$xlfd" ] || { echo "✗ font has no XLFD: $bdf" >&2; exit 1; }
		printf '%s %s\n' "$(basename "$bdf")" "$xlfd" >> "${font_dir}/fonts.dir"
		count=$((count + 1))
	done
	sed -i "1i${count}" "${font_dir}/fonts.dir"
fi
if manifest_has libx11; then
	x11_locale_src="${ROOT}/packages/libx11/prefix/${ARCH}/usr/share/X11/locale"
	if [ -d "${x11_locale_src}/C" ]; then
		mkdir -p "${DEST}/usr/share/X11/locale"
		install -m 0644 "${x11_locale_src}/locale.alias" \
			"${x11_locale_src}/locale.dir" \
			"${x11_locale_src}/compose.dir" \
			"${DEST}/usr/share/X11/locale/"
		cp -a "${x11_locale_src}/C" "${DEST}/usr/share/X11/locale/"
	fi
fi
if manifest_has xbitmaps; then
	bitmap_src="${ROOT}/packages/xbitmaps/prefix/${ARCH}/usr/include/X11/bitmaps"
	if [ -d "$bitmap_src" ]; then
		mkdir -p "${DEST}/usr/include/X11/bitmaps"
		cp -a "$bitmap_src/." "${DEST}/usr/include/X11/bitmaps/"
	fi
fi

# Account policy by profile
case "$PROFILE" in
minimal|desktop|desktop-console|appliance)
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
	mkdir -p "${DEST}/root/Developer" "${DEST}/home/labuser/Developer"
	cp -a "${ROOT}/profiles/development/examples/." "${DEST}/root/Developer/"
	cp -a "${ROOT}/profiles/development/examples/." "${DEST}/home/labuser/Developer/"
	;;
esac

if [ "$PROFILE" = "desktop" ] || [ "$PROFILE" = "desktop-console" ] || [ "${ROOT_POLICY:-}" = "noroot_login" ]; then
	printf '1\n' > "${DEST}/etc/ir0-noroot"
fi
if [ "$PROFILE" = "desktop" ] || [ "$PROFILE" = "desktop-console" ]; then
	printf 'ext2 /dev/hdb /home\n' > "${DEST}/etc/ir0-home"
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
