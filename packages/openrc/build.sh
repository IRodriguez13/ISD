#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/toolchain.sh"
PKG="${ROOT}/packages/openrc"
SRC_DIR="${PKG}/src"
RC_DIR="${SRC_DIR}/src/rc"
STAGE="${PRODUCT_OUT:-${ROOT}/out/${ARCH}/product}/openrc-tree"
DESTDIR="${PKG}/.DESTDIR"

if [ ! -f "$SRC_DIR/Makefile" ]; then
	echo "✗ missing openrc source; run: make fetch" >&2
	exit 1
fi

echo "  OPENRC  Building with $CC ARCH=${ARCH}..."
cd "$SRC_DIR"
make clean >/dev/null 2>&1 || true
# IR0 guest: avoid popen(gendepends) on every sysinit; use baked libexec/rc/cache/deptree.
sed -i 's/_rc_deptree_load(1, NULL)/_rc_deptree_load(0, NULL)/' "$SRC_DIR/src/rc/rc.c"
make -s CC="$CC" \
	MKPAM= MKCAP=no MKNET=no MKSYSVINIT=no MKBASHCOMP=no MKZSHCOMP=no \
	MKPKGCONFIG=no MKSELINUX=no MKSTATICLIBS=yes

rm -rf "$DESTDIR" "$STAGE"
make install DESTDIR="$DESTDIR" PREFIX=/usr SBINDIR=/usr/sbin BINDIR=/usr/bin

mkdir -p "$STAGE"/{sbin,bin,libexec/rc}
cp -a "$DESTDIR/usr/libexec/rc/." "$STAGE/libexec/rc/"

static_link() {
	local out="$1"
	shift
	"$CC" -static -no-pie \
		-I"${RC_DIR}/../includes" -I"${RC_DIR}/../librc" -I"${RC_DIR}/../libeinfo" \
		-o "$out" "$@" \
		-L"${RC_DIR}/../librc" -L"${RC_DIR}/../libeinfo" -lrc -leinfo
}

cd "$RC_DIR"
static_link "$STAGE/sbin/openrc-init" openrc-init.o rc-plugin.o rc-wtmp.o
static_link "$STAGE/sbin/orc-shutdn" \
	openrc-shutdown.o rc-misc.o _usage.o broadcast.o rc-wtmp.o rc-sysvinit.o rc-plugin.o
static_link "$STAGE/sbin/openrc-run" openrc-run.o _usage.o rc-misc.o rc-plugin.o
static_link "$STAGE/sbin/openrc" rc.o rc-logger.o rc-misc.o rc-plugin.o _usage.o

for f in "$STAGE/sbin/openrc-init" "$STAGE/sbin/openrc" "$STAGE/sbin/openrc-run"; do
	file "$f" | grep -q 'statically linked' || {
		echo "✗ expected static $f: $(file "$f")" >&2
		exit 1
	}
done

# libexec/rc/bin helpers from `make install` are dynamic PIE; relink boot-critical
# ones statically so MINIX images do not need ld-musl on disk.
mkdir -p "$STAGE/libexec/rc/bin"
static_install_bin() {
	local out="$1"
	shift
	static_link "$STAGE/libexec/rc/bin/$out" "$@"
}

cd "$RC_DIR"
for e in eval_ecolors ebegin eend eerror einfo einfon ewarn ewarnn ewend \
	eindent eoutdent esyslog ewaitfile \
	vebegin veend veinfo vewarn vewend veindent veoutdent; do
	static_install_bin "$e" do_e.o rc-misc.o
done
static_install_bin checkpath checkpath.o _usage.o rc-misc.o
static_install_bin fstabinfo fstabinfo.o _usage.o rc-misc.o
static_install_bin mountinfo mountinfo.o _usage.o rc-misc.o
static_install_bin rc-depend rc-depend.o _usage.o rc-misc.o
static_install_bin shell_var shell_var.o rc-misc.o
static_install_bin get_options do_value.o rc-misc.o
static_install_bin save_options do_value.o rc-misc.o
static_install_bin is_newer_than is_newer_than.o rc-misc.o
static_install_bin is_older_than is_older_than.o rc-misc.o
static_install_bin rc-abort rc-abort.o
static_install_bin swclock swclock.o _usage.o rc-misc.o

for f in "$STAGE/libexec/rc/bin/"{checkpath,fstabinfo,mountinfo,rc-depend,eval_ecolors}; do
	file "$f" | grep -q 'statically linked' || {
		echo "✗ expected static $f: $(file "$f")" >&2
		exit 1
	}
done
echo "✓ build openrc OK (static PID1 + libexec/rc/bin boot helpers)"
