#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Build GNU sudo static musl (no PAM). Partial install: sudo binary only.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/toolchain.sh"
PKG="${ROOT}/packages/sudo"
SRC="${PKG}/src"
OUT_DIR="${PRODUCT_OUT:-${ROOT}/out/${ARCH}/product}/stage-bin"
LOG="${PKG}/configure-${ARCH}.log"

if [ ! -d "$SRC" ]; then
	echo "✗ missing sudo source; run: make fetch" >&2
	exit 1
fi

chmod +x "${ROOT}/scripts/apply-isd-patches.sh"
"${ROOT}/scripts/apply-isd-patches.sh" sudo

mkdir -p "$OUT_DIR"
cd "$SRC"

SUDO_VER=$(cat "${PKG}/version")
echo "  SUDO    Configuring ${SUDO_VER} host=${TARGET_TRIPLE} (static, no PAM)..."
make distclean >/dev/null 2>&1 || true
if ! CC="$CC" CFLAGS="-Os -fno-pie" LDFLAGS="-static -no-pie" \
	./configure \
	--prefix=/usr \
	--libexecdir=/usr/lib \
	--sysconfdir=/etc \
	--without-pam \
	--without-selinux \
	--without-ldap \
	--disable-openssl \
	--disable-zlib \
	--disable-nls \
	--disable-shared \
	--enable-static \
	--disable-pie \
	--disable-log-server \
	--disable-log-client \
	--enable-static-sudoers \
	--disable-shared-libutil \
	--disable-hardening \
	--without-sendmail \
	--with-env-editor \
	--with-passprompt="[sudo] password for %p: " \
	>"$LOG" 2>&1; then
	echo "✗ sudo configure failed (see ${LOG})" >&2
	cat "$LOG" >&2
	exit 1
fi

build_args=(CC="$CC" CFLAGS="-Os -fno-pie" LDFLAGS="-static -no-pie -pthread" LIBS="-lpthread")
for sub in lib/util lib/eventlog lib/iolog lib/protobuf-c; do
	if ! make -s "${build_args[@]}" -C "$sub" all; then
		echo "✗ sudo build failed in ${sub} (see ${LOG})" >&2
		exit 1
	fi
done
if ! make -s "${build_args[@]}" -C plugins/sudoers libparsesudoers.la sudoers.la; then
	echo "✗ sudo build failed in plugins/sudoers (see ${LOG})" >&2
	exit 1
fi
if ! make -s "${build_args[@]}" -C src $(printf '%s.o ' conversation copy_file edit_open env_hooks exec \
	exec_common exec_intercept exec_iolog exec_monitor exec_nopty exec_preload exec_ptrace \
	exec_pty get_pty hooks limits load_plugins net_ifs parse_args preserve_fds signal sudo \
	sudo_edit suspend_parent tgetpass ttyname utmp preload); then
	echo "✗ sudo object build failed in src (see ${LOG})" >&2
	exit 1
fi

SUDOERS_A="${SRC}/plugins/sudoers/.libs/sudoers.a"
if [ ! -f "$SUDOERS_A" ]; then
	echo "✗ missing ${SUDOERS_A}" >&2
	exit 1
fi

(
	cd "${SRC}/src"
	# libtool link omits -static; manual link matches opendoas static musl pattern.
	$CC -static -no-pie -o sudo *.o "$SUDOERS_A" -lpthread -pthread
)

if [ ! -x "${SRC}/src/sudo" ]; then
	echo "✗ sudo build did not produce src/sudo" >&2
	exit 1
fi

install -m 04755 "${SRC}/src/sudo" "$OUT_DIR/sudo"
file "$OUT_DIR/sudo" | grep -q ELF
if file "$OUT_DIR/sudo" | grep -q dynamically; then
	echo "✗ sudo is dynamically linked (expected static musl)" >&2
	exit 1
fi
strip "$OUT_DIR/sudo" 2>/dev/null || true
echo "✓ build sudo OK → $OUT_DIR/sudo"
