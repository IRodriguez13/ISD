#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Verify staged rootfs matches profile identity and package manifest (postcondition).
set -euo pipefail

TREE="${1:?usage: verify-profile-rootfs.sh ROOTFS_TREE}"
PROFILE="${PROFILE:-minimal}"
ARCH="${ARCH:-x86_64}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

err() { echo "✗ $*" >&2; fail=1; }

[ -d "$TREE" ] || { echo "✗ missing staged rootfs: $TREE" >&2; exit 2; }

got_profile="$(tr -d '[:space:]' < "${TREE}/etc/ir0-profile" 2>/dev/null || true)"
if [ "$got_profile" != "$PROFILE" ]; then
	err "etc/ir0-profile=${got_profile:-missing} expected ${PROFILE}"
fi

manifest="${ROOT}/profiles/${PROFILE}/verify-paths.txt"
if [ ! -f "$manifest" ]; then
	manifest="${ROOT}/profiles/minimal/verify-paths.txt"
fi

while IFS= read -r line || [ -n "$line" ]; do
	line="${line%%#*}"
	line="${line#"${line%%[![:space:]]*}"}"
	line="${line%"${line##*[![:space:]]}"}"
	[ -z "$line" ] && continue
	pkg="${line%% *}"
	rel="${line#* }"
	if [ -z "$rel" ] || [ "$rel" = "$pkg" ]; then
		continue
	fi
	if [ ! -e "${TREE}/${rel}" ]; then
		err "package ${pkg}: missing ${rel} in staged rootfs"
	fi
done < "$manifest"

if [ "$PROFILE" = "desktop" ] || [ "$PROFILE" = "desktop-console" ]; then
	if [ ! -f "${TREE}/usr/share/terminfo/x/xterm" ]; then
		err "desktop: missing usr/share/terminfo/x/xterm (ncurses terminfo)"
	fi
	clients="${ROOT}/profiles/desktop/x-session-clients.txt"
	while IFS= read -r client || [ -n "$client" ]; do
		client="${client%%#*}"
		client="${client#"${client%%[![:space:]]*}"}"
		client="${client%"${client##*[![:space:]]}"}"
		[ -z "$client" ] && continue
		if ! grep -qx "$client" "${ROOT}/profiles/${PROFILE}/packages.txt" 2>/dev/null \
			&& ! grep -qx "$client" "${ROOT}/profiles/desktop/packages.txt" 2>/dev/null; then
			err "x-session client ${client} not in profile packages.txt"
		fi
	done < "$clients"
fi

if grep -F '[ "$_ir0_profile" = "desktop" ] && _auto_x=1' "${ROOT}/rootfs/base/etc/profile" >/dev/null \
	&& grep -F 'terminal) _auto_x=0 ;;' "${ROOT}/rootfs/base/etc/profile" >/dev/null; then
	:
else
	err "login session auto-X contract missing in rootfs/base/etc/profile"
fi

if [ "$fail" -ne 0 ]; then
	exit 1
fi

# Init implementation must match profile INIT_SYSTEM (auditable; usmang/TUI rely on this).
PROF_CONF="${ROOT}/profiles/${PROFILE}/profile.conf"
INIT_SYSTEM=runit
if [ -f "$PROF_CONF" ]; then
	INIT_SYSTEM="$(grep -E '^INIT_SYSTEM=' "$PROF_CONF" | tail -1 | cut -d= -f2- | tr -d '[:space:]')"
fi
CFG="${ISD_CONFIG:-${ROOT}/.isdconfig.d/${PROFILE}}"
if [ "$PROFILE" = "custom" ] && [ -f "$CFG" ]; then
	cfg_init="$(grep -E '^INIT_SYSTEM=' "$CFG" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '[:space:]' || true)"
	[ -n "$cfg_init" ] && INIT_SYSTEM="$cfg_init"
fi
INIT_SYSTEM="${INIT_SYSTEM:-runit}"

if [ ! -x "${TREE}/sbin/init" ]; then
	err "missing executable sbin/init for INIT_SYSTEM=${INIT_SYSTEM}"
fi

case "$INIT_SYSTEM" in
runit)
	[ -x "${TREE}/sbin/runit" ] || err "runit: missing sbin/runit"
	[ -x "${TREE}/bin/runit-init" ] || err "runit: missing bin/runit-init"
	[ -f "${TREE}/etc/runit/1" ] || err "runit: missing etc/runit/1"
	;;
sysvinit)
	[ -f "${TREE}/etc/inittab" ] || err "sysvinit: missing etc/inittab"
	[ -x "${TREE}/etc/init.d/rcS" ] || err "sysvinit: missing etc/init.d/rcS"
	;;
openrc)
	[ -x "${TREE}/sbin/openrc-init" ] || err "openrc: missing sbin/openrc-init"
	[ -f "${TREE}/etc/rc.conf" ] || err "openrc: missing etc/rc.conf"
	[ -f "${TREE}/etc/fstab" ] || err "openrc: missing etc/fstab"
	grep -Eq '^proc[[:space:]]+/proc[[:space:]]+proc' "${TREE}/etc/fstab" \
		|| err "openrc: /etc/fstab lacks proc mount"
	grep -Eq '^tmpfs[[:space:]]+/run[[:space:]]+tmpfs' "${TREE}/etc/fstab" \
		|| err "openrc: /etc/fstab lacks /run tmpfs mount"
	[ -x "${TREE}/sbin/ir0-boot" ] || err "openrc: missing sbin/ir0-boot"
	[ -d "${TREE}/etc/runlevels/default" ] || err "openrc: missing etc/runlevels/default"
	;;
*)
	err "unknown INIT_SYSTEM=${INIT_SYSTEM}"
	;;
esac

echo "✓ verify-profile-rootfs OK PROFILE=${PROFILE} INIT_SYSTEM=${INIT_SYSTEM} tree=${TREE}"
