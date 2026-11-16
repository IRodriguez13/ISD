#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# STO-1: pack a finished rootfs tree into an EXT2 root disk (host mkfs.ext2 -d).
# Parallel to pack-minix.sh — no MINIX 14-char dentry limit.
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
TREE="${1:?usage: pack-ext2-root.sh ROOTFS_TREE DISK}"
DISK="${2:?usage: pack-ext2-root.sh ROOTFS_TREE DISK}"

if [ ! -d "$TREE" ]; then
	echo "✗ missing rootfs tree: $TREE" >&2
	exit 1
fi

command -v mkfs.ext2 >/dev/null 2>&1 || {
	echo "✗ install e2fsprogs (mkfs.ext2)" >&2
	exit 1
}
command -v e2fsck >/dev/null 2>&1 || {
	echo "✗ install e2fsprogs (e2fsck)" >&2
	exit 1
}

# Same hygiene as MINIX format-large: never ship stale firstboot marker in a fresh image.
rm -f "${TREE}/var/lib/ir0/firstboot.done"

for d in var/lib/ir0 var/log tmp run run/doas mnt heart; do
	mkdir -p "${TREE}/${d}"
	touch "${TREE}/${d}/.keep"
done
# Mount points must stay empty — no .keep under proc/sys/dev (OpenRC proc cruft test).
for d in dev proc sys; do
	mkdir -p "${TREE}/${d}"
done

if ! estimate="$("${ROOT}/scripts/estimate-rootfs-ext2.sh" "$TREE")"; then
	exit 1
fi
# The estimator emits only shell assignments under this script's control.
eval "$estimate"
size_mb="${EXT2_SIZE_MB:?}"

mkdir -p "$(dirname "$DISK")"
echo "  EXT2    packing tree $TREE → $DISK (${size_mb}MiB)"
rm -f "$DISK"
truncate -s "${size_mb}M" "$DISK"

# 4 KiB blocks — matches IR0 ext2 backend and home.ext2.img policy.
# ^dir_index: kernel ext2_lookup is linear-only (STO-2); htree is a follow-up.
mkfs.ext2 -q -F -b 4096 -L IR0ROOT -O ^dir_index -d "$TREE" "$DISK"

# `mkfs.ext2 -d` copies host ownership.  A staged tree is built by the host
# developer, not by guest root, so leaking those numeric IDs into /etc (most
# importantly sudoers) would make policy files writable by a guest user with
# the same UID.  Normalize the immutable root image first; firstboot owns any
# per-user state it creates later.
command -v debugfs >/dev/null 2>&1 || {
	echo "✗ install e2fsprogs (debugfs required to normalize rootfs ownership)" >&2
	exit 1
}
owner_commands="$(mktemp "${TMPDIR:-/tmp}/isd-ext2-owners.XXXXXX")"
trap 'rm -f "$owner_commands"' EXIT
while IFS= read -r -d '' host_path; do
	rel="${host_path#"${TREE}"}"
	[ -n "$rel" ] || rel="/"
	printf 'set_inode_field %s uid 0\nset_inode_field %s gid 0\n' \
		"$rel" "$rel" >> "$owner_commands"
done < <(find "$TREE" -xdev -print0)
debugfs -w -f "$owner_commands" "$DISK" >/dev/null

# Preserve setuid mode and root ownership for the explicit, audited allowlist.
SETUID_ALLOW="${ROOT}/packages/setuid.allowlist"
if [ -f "$SETUID_ALLOW" ]; then
	while IFS= read -r path; do
		[[ "$path" =~ ^#.*$ || -z "$path" ]] && continue
		case "$path" in
		/*) rel="$path" ;;
		*) rel="/$path" ;;
		esac
		if debugfs -R "stat ${rel}" "$DISK" 2>/dev/null | grep -q 'Type: regular'; then
			debugfs -w -R "set_inode_field ${rel} uid 0" "$DISK" >/dev/null
			debugfs -w -R "set_inode_field ${rel} gid 0" "$DISK" >/dev/null
		fi
	done < "$SETUID_ALLOW"
fi

e2fsck -fn "$DISK" >/dev/null
echo "  EXT2    packed $DISK (e2fsck -fn OK)"
