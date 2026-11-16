#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Build static musl TinyCC + guest runtime under PRODUCT_OUT.
#
# Outputs:
#   $PRODUCT_OUT/stage-bin/tcc
#   $PRODUCT_OUT/tcc-runtime/{lib/tcc,usr/lib,usr/include}
#
# Source trees under packages/tinycc/{src,dist} are never deleted here.
set -euo pipefail
JOBS="${ISD_JOBS:-2}"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/toolchain.sh"
PKG="${ROOT}/packages/tinycc"
SRC="${PKG}/src"
OUT_DIR="${PRODUCT_OUT}/stage-bin"
RUNTIME="${PRODUCT_OUT}/tcc-runtime"

if [ ! -d "$SRC" ]; then
	echo "✗ missing tinycc source; run: make fetch" >&2
	exit 1
fi

# Host musl sysroot for CRT / libc.a / headers staged into the guest.
MUSL_LIB="${MUSL_LIB:-}"
MUSL_INC="${MUSL_INC:-}"
if [ -z "$MUSL_LIB" ]; then
	for d in \
		/usr/lib/"${TARGET_TRIPLE}" \
		/usr/"${TARGET_TRIPLE}"/lib \
		/lib/"${TARGET_TRIPLE}"
	do
		if [ -f "${d}/libc.a" ] && [ -f "${d}/crt1.o" ]; then
			MUSL_LIB="$d"
			break
		fi
	done
fi
if [ -z "$MUSL_INC" ]; then
	for d in \
		/usr/include/"${TARGET_TRIPLE}" \
		/usr/"${TARGET_TRIPLE}"/include \
		/usr/include
	do
		if [ -f "${d}/stdio.h" ]; then
			MUSL_INC="$d"
			break
		fi
	done
fi
if [ -z "$MUSL_LIB" ] || [ ! -f "${MUSL_LIB}/libc.a" ]; then
	echo "✗ musl libc.a not found (set MUSL_LIB=…)" >&2
	exit 1
fi
if [ -z "$MUSL_INC" ] || [ ! -f "${MUSL_INC}/stdio.h" ]; then
	echo "✗ musl headers not found (set MUSL_INC=…)" >&2
	exit 1
fi

echo "  TCC     Configuring (${TARGET_TRIPLE}, musl lib=${MUSL_LIB})..."
(
	cd "$SRC"
	# Compile artefacts only — keep the fetched tree.
	make clean >/dev/null 2>&1 || true
	rm -f config-extra.mak
	CFLAGS="-static -Os" LDFLAGS="-static" \
		./configure --cc="$CC" --prefix=/usr --tccdir=/lib/tcc \
		--crtprefix="{B}:/usr/lib"
	rm -f config-extra.mak
	echo "  TCC     Building..."
	make -s -j"$JOBS"
)

if [ ! -x "${SRC}/tcc" ]; then
	echo "✗ tcc binary missing after build" >&2
	exit 1
fi

mkdir -p "$OUT_DIR" "${RUNTIME}/bin" "${RUNTIME}/lib/tcc" \
	"${RUNTIME}/usr/lib" "${RUNTIME}/usr/include"

install -m 0755 "${SRC}/tcc" "${OUT_DIR}/tcc"
install -m 0755 "${SRC}/tcc" "${RUNTIME}/bin/tcc"
install -m 0644 "${SRC}/libtcc1.a" "${RUNTIME}/lib/tcc/libtcc1.a"

for obj in runmain.o bt-exe.o bt-log.o bcheck.o; do
	if [ -f "${SRC}/${obj}" ]; then
		install -m 0644 "${SRC}/${obj}" "${RUNTIME}/lib/tcc/${obj}"
	elif [ -f "${SRC}/lib/${obj}" ]; then
		install -m 0644 "${SRC}/lib/${obj}" "${RUNTIME}/lib/tcc/${obj}"
	fi
done

if [ -d "${SRC}/include" ]; then
	mkdir -p "${RUNTIME}/lib/tcc/include"
	cp -a "${SRC}/include/." "${RUNTIME}/lib/tcc/include/"
	cp -f "${SRC}/tcclib.h" "${RUNTIME}/lib/tcc/include/" 2>/dev/null || true
fi

install -m 0644 "${MUSL_LIB}/crt1.o" "${RUNTIME}/usr/lib/crt1.o"
install -m 0644 "${MUSL_LIB}/crti.o" "${RUNTIME}/usr/lib/crti.o"
install -m 0644 "${MUSL_LIB}/crtn.o" "${RUNTIME}/usr/lib/crtn.o"
install -m 0644 "${MUSL_LIB}/libc.a" "${RUNTIME}/usr/lib/libc.a"
# Also under tccdir so -B/lib/tcc finds CRT/libc without -L.
install -m 0644 "${MUSL_LIB}/crt1.o" "${RUNTIME}/lib/tcc/crt1.o"
install -m 0644 "${MUSL_LIB}/crti.o" "${RUNTIME}/lib/tcc/crti.o"
install -m 0644 "${MUSL_LIB}/crtn.o" "${RUNTIME}/lib/tcc/crtn.o"
install -m 0644 "${MUSL_LIB}/libc.a" "${RUNTIME}/lib/tcc/libc.a"

# Minimal C library headers for in-guest compile.
mkdir -p "${RUNTIME}/usr/include/bits"
for h in stdio.h stdlib.h string.h strings.h stdarg.h stddef.h stdint.h \
	stdbool.h errno.h limits.h inttypes.h features.h unistd.h fcntl.h \
	sys/types.h sys/stat.h alloca.h; do
	d="$(dirname "${h}")"
	if [ "$d" != "." ]; then
		mkdir -p "${RUNTIME}/usr/include/${d}"
	fi
	if [ -f "${MUSL_INC}/${h}" ]; then
		install -m 0644 "${MUSL_INC}/${h}" "${RUNTIME}/usr/include/${h}"
	fi
done
if [ -d "${MUSL_INC}/bits" ]; then
	cp -a "${MUSL_INC}/bits/." "${RUNTIME}/usr/include/bits/"
fi

file "${OUT_DIR}/tcc" | grep -q ELF
echo "✓ tinycc OK → ${OUT_DIR}/tcc (+ ${RUNTIME}/)"
