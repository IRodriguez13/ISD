#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Inject the BusyBox multicall binary and its applets. MINIX v1 stores the link
# count in one byte, so a complete BusyBox cannot share one inode: shard links
# across identical hidden copies before reaching the on-disk limit.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IR0_ROOT="${IR0_ROOT:-$(cd "${ROOT}/../IR0" 2>/dev/null && pwd || true)}"

DISK="${1:?usage: busybox_inject_manifest.sh DISK [BUSYBOX_BIN] [MANIFEST]}"
BUSYBOX_BIN="${2:-${FASE50_BUSYBOX_BIN:-$ROOT/out/busybox-full}}"
MANIFEST="${3:-$ROOT/packages/busybox/required_applets.txt}"
INJECT="python3 ${IR0_ROOT}/scripts/inject_init_minix.py"

if [[ ! -f "$DISK" ]]; then
	echo "✗ missing disk: $DISK" >&2
	exit 1
fi
if [[ ! -f "$BUSYBOX_BIN" ]]; then
	echo "✗ missing BusyBox: $BUSYBOX_BIN" >&2
	exit 1
fi
if [[ ! -f "$MANIFEST" ]]; then
	echo "✗ missing manifest: $MANIFEST" >&2
	exit 1
fi

chmod +x "${ROOT}/scripts/busybox_check_manifest.sh"
"${ROOT}/scripts/busybox_check_manifest.sh" "$BUSYBOX_BIN" "$MANIFEST"

echo "  BUSYBOX /bin/busybox + applet hardlinks"
$INJECT "$DISK" "$BUSYBOX_BIN" bin/busybox

paths=("/bin/busybox")
link_source="bin/busybox"
link_count=0
shard=1
links_per_inode=200
# These applets get shell wrappers (not hardlinks): bare BusyBox halt/poweroff/
# reboot without -f only kill(1, SIG*) and expect SysV init — runit has none.
FORCE_REBOOT_APPLETS="halt poweroff reboot"
while IFS= read -r line || [[ -n "$line" ]]; do
	applet="${line%%#*}"
	applet="$(echo "$applet" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
	[[ -z "$applet" ]] && continue
	if [[ "$applet" == "busybox" ]]; then
		continue
	fi
	case " $FORCE_REBOOT_APPLETS " in
	*" $applet "*) continue ;;
	esac
	# MINIX v1 directory entries are 14-byte names (inject truncates).
	# Skip overlong applet names — they cannot be invoked by full argv0 on disk.
	if [[ "${#applet}" -gt 14 ]]; then
		echo "  SKIP    applet '$applet' (name >14 chars; MINIX v1 limit)" >&2
		continue
	fi
	if (( link_count >= links_per_inode )); then
		shard=$((shard + 1))
		link_source="bin/.busybox${shard}"
		$INJECT "$DISK" "$BUSYBOX_BIN" "$link_source"
		paths+=("/$link_source")
		link_count=0
	fi
	$INJECT --hardlink "$DISK" "$link_source" "bin/$applet"
	link_count=$((link_count + 1))
	paths+=("/bin/$applet")
done < "$MANIFEST"

FORCE_POWER_BIN="${IR0_FORCE_POWER_BIN:-}"
if [[ -z "$FORCE_POWER_BIN" ]]; then
	for cand in \
		"${PRODUCT_OUT:-${ROOT}/out/${ARCH:-x86_64}/product}/stage-bin/ir0_force_power" \
		"${ROOT}/out/${ARCH:-x86_64}/product/stage-bin/ir0_force_power" \
		"${ROOT}/out/stage-bin/ir0_force_power"
	do
		if [[ -f "$cand" ]]; then
			FORCE_POWER_BIN="$cand"
			break
		fi
	done
fi
if [[ ! -f "$FORCE_POWER_BIN" ]]; then
	echo "✗ missing ir0_force_power (run: make build-services)" >&2
	exit 1
fi
# One ELF, three names: argv[0] selects halt / poweroff / reboot.
$INJECT --mode 0755 "$DISK" "$FORCE_POWER_BIN" bin/poweroff
$INJECT --hardlink "$DISK" bin/poweroff bin/halt
$INJECT --hardlink "$DISK" bin/poweroff bin/reboot
paths+=("/bin/poweroff" "/bin/halt" "/bin/reboot")

python3 "${IR0_ROOT}/scripts/verify_minix_rootfs.py" --gate "$DISK" "${paths[@]}"
echo "  BUSYBOX ${#paths[@]} paths verified"
