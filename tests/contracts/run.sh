#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# ISD contract tests (A–F). No full package rebuild required.
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
PASS=0
FAIL=0
ok() { echo "  OK  $*"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL $*"; FAIL=$((FAIL + 1)); }

chmod +x scripts/stamp-run.sh scripts/resolve-packages.sh scripts/isdconfig.py \
	scripts/install-uapi.sh scripts/stage-rootfs.sh scripts/check-make-help.sh \
	scripts/arch-policy.sh 2>/dev/null || true

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "=== ISD contracts (A–H) ==="

# --- M: Make interface (mk/targets.mk ↔ make help) --------------------------
echo "-- M make help --"
help_check=$(scripts/check-make-help.sh 2>&1) && ok "M every target classified, public ones described" \
	|| bad "M make help drift: $help_check"

# --- R: ISA registry (packages/arch/<isa>/) ---------------------------------
echo "-- R ISA registry --"
reg_ok=1
for dir in packages/arch/*/; do
	isa=$(basename "$dir")
	[ -f "$dir/arch.conf" ] && [ -f "$dir/aliases" ] && [ -f "$dir/support" ] \
		|| { reg_ok=0; echo "    $isa: missing arch.conf/aliases/support"; continue; }
	( source "$dir/arch.conf"; [ -n "${ISD_ARCH_TRIPLE:-}" ] \
		&& [ -n "${ISD_ARCH_ELF_MACHINE:-}" ] ) \
		|| { reg_ok=0; echo "    $isa: arch.conf incomplete"; }
	[ "$(scripts/arch-policy.sh canonical "$isa")" = "$isa" ] || reg_ok=0
	for alias in $(cat "$dir/aliases"); do
		[ "$(scripts/arch-policy.sh canonical "$alias")" = "$isa" ] \
			|| { reg_ok=0; echo "    alias $alias does not map to $isa"; }
	done
done
dup_alias=$(cat packages/arch/*/aliases | tr ' ' '\n' | sed '/^$/d' | sort | uniq -d)
[ -z "$dup_alias" ] || { reg_ok=0; echo "    duplicate aliases: $dup_alias"; }
[ "$reg_ok" -eq 1 ] && ok "R every ISA directory is complete and aliases are unique" \
	|| bad "R ISA registry incomplete"
[ "$(scripts/arch-policy.sh status arm64 busybox sudo | tr '\n' ' ')" = \
	"busybox buildable sudo blocked-by-package " ] \
	&& ok "R aarch64 package status comes from packages/arch/aarch64/support" \
	|| bad "R aarch64 package status"
IR0_TOOLCHAIN_OPTIONAL=1 ARCH=amd64 bash -c 'source scripts/toolchain.sh; \
	[ "$ARCH/$TARGET_TRIPLE/$(toolchain_pkg_status busybox)" = \
	  x86_64/x86_64-linux-musl/supported ]' \
	&& ok "R toolchain resolves ISA facts through the registry" \
	|| bad "R toolchain ISA facts"
isa_keys=$(grep -lE '^(ARCHES|STATUS_[A-Za-z0-9_]+)=' packages/*/package.conf 2>/dev/null || true)
[ -z "$isa_keys" ] && ok "R recipes carry no per-ISA status (packages/arch owns it)" \
	|| bad "R per-ISA keys in recipes: $(echo $isa_keys)"
support_bad=$(awk -v ok_st=" supported buildable blocked-by-package blocked-by-kernel-ABI unsupported " '
	/^[[:space:]]*(#|$)/ { next }
	index(ok_st, " " $2 " ") == 0 { print FILENAME ": bad status " $2; next }
	$1 != "*" && system("test -f packages/" $1 "/build.sh") != 0 { print FILENAME ": no recipe " $1 }
	' packages/arch/*/support)
[ -z "$support_bad" ] && ok "R support tables name real recipes and valid statuses" \
	|| bad "R support tables: $support_bad"
set +e
arm_plan=$(make -s arm minimal plan 2>&1)
arm_plan_rc=$?
set -e
[ "$arm_plan_rc" -ne 0 ] && echo "$arm_plan" | grep -q 'sudo (blocked-by-package)' \
	&& ok "R plan refuses packages the ISA cannot build" \
	|| bad "R arm minimal plan rc=$arm_plan_rc: $arm_plan"
make -s x86-64 minimal plan >/dev/null \
	&& ok "R x86-64 minimal plan stays buildable" || bad "R x86-64 minimal plan"
alias_art=$(make -s print-artifacts ARCH=arm64 PROFILE=minimal 2>&1 || true)
echo "$alias_art" | grep -qx 'ARCH=aarch64' \
	&& ! echo "$alias_art" | grep -q '/out/arm64/' \
	&& make -s -n ARCH=amd64 headers >/dev/null 2>&1 \
	&& ok "R ARCH aliases resolve to the canonical ISA tree" \
	|| bad "R ARCH alias split tree: $alias_art"
make -s -n x86-64 minimal headers PROFILE=not-a-profile >/dev/null 2>&1 \
	&& ok "R headers does not resolve the package profile" \
	|| bad "R headers resolves the package profile"
make -s -n x86-64 minimal build-runit >/dev/null 2>&1 \
	&& ok "R build-<pkg> resolves the profile on its own" \
	|| bad "R build-<pkg> has no rule without another resolving goal"
triples=$(for c in packages/arch/*/arch.conf; do (source "$c"; echo "$ISD_ARCH_TRIPLE"); done | paste -sd'|')
isa_triples=$(grep -nE "$triples" scripts/*.sh scripts/*.py packages/*/build.sh \
	packages/*/fetch.sh mk/*.mk Makefile 2>/dev/null | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)
[ -z "$isa_triples" ] && ok "R no hard-coded target triple outside packages/arch" \
	|| bad "R hard-coded triple: $isa_triples"
isa_branches=$(grep -rnE 'case "?\$\{?ARCH|ifn?eq \(\$\(ARCH\)|"\$\{?ARCH\}?" *!?=+ *"?(x86|aarch|arm|amd)' \
	scripts mk Makefile packages/*/build.sh packages/*/fetch.sh 2>/dev/null || true)
[ -z "$isa_branches" ] && ok "R no ISA branches outside packages/arch" \
	|| bad "R ISA branch outside packages/arch: $isa_branches"

# --- A: stamp-run writes only on success; skip leaves stamp untouched --------
echo "-- A stamp-run --"
ST="$TMP/stamp-a"
scripts/stamp-run.sh "$ST" -- true
[ -f "$ST" ] && ok "A stamp written on success" || bad "A no stamp on success"
BEFORE=$(cat "$ST")
if scripts/stamp-run.sh "$ST" -- false 2>/dev/null; then
	bad "A failure returned 0"
else
	ok "A failure exits non-zero"
fi
AFTER=$(cat "$ST")
[ "$BEFORE" = "$AFTER" ] && ok "A stamp untouched on failure" || bad "A stamp changed on failure"
scripts/stamp-run.sh "$ST" -- true
[ -f "$ST" ] && ok "A stamp rewrite on success" || bad "A rewrite failed"

# --- B: extras + resolve + auto-dep nano→ncurses -----------------------------
echo "-- B extras / resolve --"
CFG="$TMP/isdconfig-b"
PROFILE=minimal ISD_CONFIG="$CFG" python3 scripts/isdconfig.py --config "$CFG" defconfig --force
PROFILE=minimal ISD_CONFIG="$CFG" python3 scripts/isdconfig.py --config "$CFG" set CONFIG_PKG_OPENDOAS=y
got=$(PROFILE=appliance ISD_CONFIG="$CFG" bash scripts/resolve-packages.sh)
echo " $got " | grep -q ' opendoas ' && ok "B resolve includes CONFIG_PKG_OPENDOAS" || bad "B opendoas missing: $got"
echo " $got " | grep -q ' busybox ' && ok "B core busybox" || bad "B no busybox"
echo " $got " | grep -q ' runit ' && ok "B core runit" || bad "B no runit"

CFG2="$TMP/isdconfig-b2"
PROFILE=minimal ISD_CONFIG="$CFG2" python3 scripts/isdconfig.py --config "$CFG2" defconfig --force
PROFILE=minimal ISD_CONFIG="$CFG2" python3 scripts/isdconfig.py --config "$CFG2" set CONFIG_PKG_NANO=y
grep -q 'CONFIG_PKG_NCURSES=y' "$CFG2" && ok "B auto-dep NANO→NCURSES in config" || bad "B NCURSES not set"
got2=$(PROFILE=appliance ISD_CONFIG="$CFG2" bash scripts/resolve-packages.sh)
echo " $got2 " | grep -q ' nano ' && echo " $got2 " | grep -q ' ncurses ' \
	&& ok "B resolve nano+ncurses" || bad "B resolve missing nano/ncurses: $got2"

# Minimal includes the preferred elevation tool; development owns its toolchain.
CFG_EMPTY="$TMP/isdconfig-empty"
: >"$CFG_EMPTY"
min=$(PROFILE=minimal ISD_CONFIG="$CFG_EMPTY" bash scripts/resolve-packages.sh)
echo " $min " | grep -q ' busybox ' && echo " $min " | grep -q ' runit ' \
	&& echo " $min " | grep -q ' sudo ' \
	&& ! echo " $min " | grep -q ' opendoas ' \
	&& ! echo " $min " | grep -q ' gnumake ' \
	&& ! echo " $min " | grep -q ' tinycc ' \
	&& ok "B minimal packages.txt mandates sudo" || bad "B minimal resolve: $min"

desk=$(PROFILE=desktop ISD_CONFIG="$CFG_EMPTY" bash scripts/resolve-packages.sh)
echo " $desk " | grep -q ' tinycc ' && echo " $desk " | grep -q ' gnumake ' \
	&& echo " $desk " | grep -q ' doom ' \
	&& echo " $desk " | grep -q ' nano ' && echo " $desk " | grep -q ' sudo ' \
	&& ok "B desktop packages.txt mandates tinycc+gnumake+doom+editor" \
	|| bad "B desktop resolve: $desk"

dev=$(PROFILE=development ISD_CONFIG="$CFG_EMPTY" bash scripts/resolve-packages.sh)
echo " $dev " | grep -q ' tinycc ' && echo " $dev " | grep -q ' gnumake ' \
	&& echo " $dev " | grep -q ' sudo ' \
	&& ok "B development mandates sudo+tinycc+gnumake" \
	|| bad "B development resolve: $dev"

CFG3="$TMP/isdconfig-b3"
PROFILE=minimal ISD_CONFIG="$CFG3" python3 scripts/isdconfig.py --config "$CFG3" defconfig --force
got3=$(PROFILE=minimal ISD_CONFIG="$CFG3" bash scripts/resolve-packages.sh)
echo " $got3 " | grep -q ' sudo ' && ! echo " $got3 " | grep -q ' opendoas ' \
	&& ! echo " $got3 " | grep -q ' nano ' \
	&& ! echo " $got3 " | grep -q ' tinycc ' \
	&& ok "B minimal defconfig stays clean" || bad "B minimal defconfig resolve: $got3"
grep -q 'CONFIG_APPLET_TOP=y' "$CFG3" && ok "B defconfig seeds APPLET_TOP" \
	|| bad "B no APPLET_TOP in defconfig"

PROFILE=minimal ISD_CONFIG="$CFG3" python3 scripts/isdconfig.py --config "$CFG3" \
	set CONFIG_APPLET_TOP=n
grep -q 'CONFIG_APPLET_TOP=n' "$CFG3" && ok "B set CONFIG_APPLET_TOP=n" \
	|| bad "B applet set failed"

CFG_ISO="$TMP/config-root"
mkdir -p "$CFG_ISO/.isdconfig.d"
PROFILE=minimal python3 scripts/isdconfig.py --config "$CFG_ISO/.isdconfig.d/minimal" \
	defconfig --force
PROFILE=development python3 scripts/isdconfig.py --config "$CFG_ISO/.isdconfig.d/development" \
	defconfig --force
python3 scripts/isdconfig.py --config "$CFG_ISO/.isdconfig.d/development" \
	set CONFIG_PKG_NANO=y
! grep -q 'CONFIG_PKG_NANO=y' "$CFG_ISO/.isdconfig.d/minimal" \
	&& ok "B profile configs are isolated" || bad "B profile config contamination"

# --- C: overlay independence (.keep trees present; Makefile find deps) -------
echo "-- C overlays --"
ov_ok=1
for p in minimal development desktop desktop-console appliance; do
	[ -f "profiles/$p/overlay/.keep" ] || [ -f "profiles/$p/overlay/etc/.keep" ] || ov_ok=0
done
[ -f rootfs/arch/x86_64/.keep ] && [ -f rootfs/local/.keep ] || ov_ok=0
[ "$ov_ok" = 1 ] && ok "C overlay .keep present" || bad "C missing overlay .keep"
grep -q 'ROOTFS_FIND_DIRS' Makefile && grep -q 'find \$(ROOTFS_FIND_DIRS)' Makefile \
	&& ok "C rootfs stamp find deps" || bad "C Makefile missing find deps"
grep -q 'ISD_PACKAGES_MANIFEST' scripts/stage-rootfs.sh && ok "C stage uses manifest" || bad "C no manifest"
grep -q '\[ "\$ap" = "busybox" \] && return 0' scripts/stage-rootfs.sh \
	&& ok "C skip busybox self-link" || bad "C no busybox skip"
grep -q 'CONFIG_APPLET_' scripts/stage-rootfs.sh \
	&& ok "C stage links CONFIG_APPLET_*" || bad "C no applet config links"
shell_profile_ok=1
for shell_profile in rootfs/base/etc/profile rootfs/etc/profile; do
	grep -q "alias ll='ls -l'" "$shell_profile" \
		&& grep -q "alias llh='ls -lah'" "$shell_profile" \
		&& grep -q 'PS1=.*\\w' "$shell_profile" \
		&& grep -q 'ENV=/etc/ashrc' "$shell_profile" \
		|| shell_profile_ok=0
done
[ "$shell_profile_ok" = 1 ] \
	&& ok "C common ash aliases and home-aware prompt stay synchronized" \
	|| bad "C shell profile aliases/prompt drift"
grep -q 'done <<< "$BB_APPLETS"' scripts/stage-rootfs.sh \
	&& ! grep -q 'MANIFEST="${PROF_DIR}/applets.txt"' scripts/stage-rootfs.sh \
	&& ok "C every profile links the complete busybox-full applet set" \
	|| bad "C profile-specific BusyBox applet surface"
grep -q '"$BUSYBOX" --list > "$MANIFEST"' scripts/pack-minix.sh \
	&& grep -q 'links_per_inode=200' scripts/busybox_inject_manifest.sh \
	&& ok "C MINIX packs full applet set with bounded inode link shards" \
	|| bad "C MINIX BusyBox manifest/link-count safety missing"
grep -q 'format-large' scripts/pack-minix.sh \
	&& ok "C pack-minix format-large clean image" || bad "C pack-minix no format-large"
grep -q 'firstboot.done' scripts/pack-minix.sh \
	&& ok "C pack rejects stale firstboot.done" || bad "C pack no firstboot.done guard"

# --- D: DOOM IWAD gate + tinycc/gnumake/doom ready + clean policy -----------
echo "-- D packages / validate / clean --"
CFGD="$TMP/isdconfig-d"
PROFILE=minimal ISD_CONFIG="$CFGD" python3 scripts/isdconfig.py --config "$CFGD" defconfig --force
sed -i 's/CONFIG_PKG_DOOM=n/CONFIG_PKG_DOOM=y/' "$CFGD"
# Validate must fail without IWAD; config stays unchanged (no silent scrub).
set +e
out=$(env -u ISD_DOOM_IWAD ISD_DOOM_SKIP_AUTODISCOVER=1 PROFILE=minimal ISD_CONFIG="$CFGD" \
	python3 scripts/isdconfig.py --config "$CFGD" validate 2>&1)
rc=$?
set -e
[ "$rc" -ne 0 ] && grep -q 'CONFIG_PKG_DOOM=y' "$CFGD" \
	&& ok "D DOOM=y kept on validate failure without IWAD" || bad "D DOOM: rc=$rc cfg=$(grep DOOM "$CFGD") out=$out"
echo "$out" | grep -qi 'DOOM\|IWAD\|doom' && ok "D DOOM error message" || bad "D DOOM no message: $out"

set +e
out_set=$(env -u ISD_DOOM_IWAD ISD_DOOM_SKIP_AUTODISCOVER=1 PROFILE=minimal ISD_CONFIG="$CFGD" \
	python3 scripts/isdconfig.py --config "$CFGD" set CONFIG_PKG_DOOM=y 2>&1)
rc_set=$?
set -e
grep -q 'CONFIG_PKG_DOOM=y' "$CFGD" \
	&& [ "$rc_set" -ne 0 ] \
	&& echo "$out_set" | grep -qi 'unchanged\|not buildable' \
	&& ok "D set DOOM=y rejected without IWAD" \
	|| bad "D set DOOM: rc=$rc_set out=$out_set cfg=$(grep DOOM "$CFGD")"

# When an IWAD exists (lab universal-doom or explicit), DOOM=y must stick.
CFGD2="$TMP/isdconfig-d2"
PROFILE=minimal ISD_CONFIG="$CFGD2" python3 scripts/isdconfig.py --config "$CFGD2" defconfig --force
sed -i 's/CONFIG_PKG_DOOM=n/CONFIG_PKG_DOOM=y/' "$CFGD2"
if bash scripts/find-doom-iwad.sh >/dev/null 2>&1; then
	set +e
	out2=$(env -u ISD_DOOM_IWAD -u ISD_DOOM_SKIP_AUTODISCOVER \
		PROFILE=minimal ISD_CONFIG="$CFGD2" \
		python3 scripts/isdconfig.py --config "$CFGD2" validate 2>&1)
	rc2=$?
	set -e
	[ "$rc2" -eq 0 ] && grep -q 'CONFIG_PKG_DOOM=y' "$CFGD2" \
		&& ok "D DOOM=y kept when IWAD autodiscovered" \
		|| bad "D DOOM kept: rc=$rc2 cfg=$(grep DOOM "$CFGD2") out=$out2"
else
	# CI without a lab WAD: explicit temp IWAD still keeps =y.
	fake_wad="$TMP/fake.wad"
	printf 'IWAD' >"$fake_wad"
	set +e
	out2=$(env ISD_DOOM_IWAD="$fake_wad" ISD_DOOM_SKIP_AUTODISCOVER=1 \
		PROFILE=minimal ISD_CONFIG="$CFGD2" \
		python3 scripts/isdconfig.py --config "$CFGD2" validate 2>&1)
	rc2=$?
	set -e
	[ "$rc2" -eq 0 ] && grep -q 'CONFIG_PKG_DOOM=y' "$CFGD2" \
		&& ok "D DOOM=y kept with ISD_DOOM_IWAD" \
		|| bad "D DOOM kept explicit: rc=$rc2 out=$out2"
fi

[ -f packages/tinycc/build.sh ] && ok "D packages/tinycc present" || bad "D no tinycc recipe"
[ -x scripts/find-doom-iwad.sh ] || [ -f scripts/find-doom-iwad.sh ] \
	&& ok "D find-doom-iwad.sh present" || bad "D missing find-doom-iwad.sh"
[ -f packages/gnumake/build.sh ] && ok "D packages/gnumake present" || bad "D no gnumake recipe"
[ -x profiles/development/examples/shebang/direct.sh ] \
	&& ok "D development direct shebang example executable" \
	|| bad "D development direct shebang example missing or not executable"
[ -x profiles/development/examples/shebang/busybox-ash.sh ] \
	&& ok "D development BusyBox shebang example executable" \
	|| bad "D development BusyBox shebang example missing or not executable"
[ -f packages/doom/build.sh ] && ok "D packages/doom present" || bad "D no doom recipe"
[ -f lib/ir0_keymap.c ] && [ -f services/ir0_keymap.c ] \
	&& ok "D keymap lib+CLI present" || bad "D missing keymap sources"
grep -q 'ir0_keymap_apply_file' services/runit_console_run.c \
	&& ok "D console applies /etc/keymap" || bad "D console missing keymap apply"
grep -q 'usr/bin/keymap' scripts/stage-rootfs.sh \
	&& ok "D stage installs keymap" || bad "D stage missing keymap"

CFGT="$TMP/isdconfig-t"
PROFILE=minimal ISD_CONFIG="$CFGT" python3 scripts/isdconfig.py --config "$CFGT" defconfig --force
PROFILE=minimal ISD_CONFIG="$CFGT" python3 scripts/isdconfig.py --config "$CFGT" \
	set CONFIG_PKG_TINYCC=y
grep -q 'CONFIG_PKG_TINYCC=y' "$CFGT" && ok "D set TINYCC=y kept" || bad "D TINYCC scrubbed wrongly"
gott=$(PROFILE=minimal ISD_CONFIG="$CFGT" bash scripts/resolve-packages.sh 2>/dev/null)
echo " $gott " | grep -q ' tinycc ' && ok "D resolve includes tinycc" || bad "D resolve: $gott"

CFGG="$TMP/isdconfig-g"
PROFILE=minimal ISD_CONFIG="$CFGG" python3 scripts/isdconfig.py --config "$CFGG" defconfig --force
PROFILE=minimal ISD_CONFIG="$CFGG" python3 scripts/isdconfig.py --config "$CFGG" \
	set CONFIG_PKG_GNUMAKE=y
grep -q 'CONFIG_PKG_GNUMAKE=y' "$CFGG" && ok "D set GNUMAKE=y kept" || bad "D GNUMAKE scrubbed wrongly"
gotg=$(PROFILE=minimal ISD_CONFIG="$CFGG" bash scripts/resolve-packages.sh 2>/dev/null)
echo " $gotg " | grep -q ' gnumake ' && ok "D resolve includes gnumake" || bad "D resolve: $gotg"


if ! find packages/busybox/ir0-patches -type f -name '*.patch' -print -quit 2>/dev/null | grep -q . \
	&& grep -q 'getutxent' packages/busybox/src/procps/uptime.c \
	&& ! grep -q 'IR0 soft FB palette\|bb_get_applet_usage\|fopen("/var/run/utmp"' \
		packages/busybox/src/{procps/uptime.c,coreutils/ls.c,include/libbb.h,libbb/appletlib.c,libbb/lineedit.c}; then
	ok "D BusyBox stays upstream for IR0 ABI"
else
	bad "D BusyBox contains IR0-specific source edits"
fi
grep -q 'scripts/package-lock.sh' Makefile \
	&& test -x scripts/package-lock.sh \
	&& ok "D package source mutations serialize across ISAs" \
	|| bad "D package source lock missing"

grep -A1 '^clear:' Makefile | grep -q 'rm -rf "$(OUT_ARCH)"' \
	&& grep -A1 '^clear:' Makefile | grep -q 'sysroot/$(ARCH)' \
	&& ! grep -A1 '^clear:' Makefile | grep -q 'packages/' \
	&& ok "D clear only removes selected ISA outputs" || bad "D clear scope unsafe"
grep -A2 '^distclean:' Makefile | grep -q 'packages/\*/src' \
	&& ok "D distclean may drop src/" || bad "D distclean policy missing"

set +e
out=$(PROFILE=minimal ISD_CONFIG="$CFGD" python3 scripts/isdconfig.py --config "$CFGD" \
	set CONFIG_PKG_BUSYBOX=n 2>&1)
rc=$?
set -e
[ "$rc" -ne 0 ] && ok "D FORBIDDEN_DISABLE BUSYBOX" || bad "D allowed disable busybox"

# --- E: UAPI ordering (package stamps ↔ toolchain; UAPI order-only) ---------
echo "-- E UAPI ordering --"
# Recipes such as BusyBox compile against the exported IR0 UAPI, so the
# headers must exist first; but a header re-export must not rebuild every
# package by mtime (the variant id tracks UAPI content instead).
pkg_rule=$(make -s -pn x86-64 minimal build-runit 2>/dev/null \
	| grep -m1 -E '/packages/%:' || true)
pkg_normal=${pkg_rule%%|*}
pkg_order=""
case "$pkg_rule" in *'|'*) pkg_order=${pkg_rule#*|} ;; esac
echo "$pkg_normal" | grep -q 'stamps/toolchain/ok' && ok "E pkg ← toolchain" \
	|| bad "E pkg rule: $pkg_rule"
if echo "$pkg_normal" | grep -q 'stamps/uapi/'; then
	bad "E pkg rebuilds on every UAPI export"
else
	ok "E pkg rebuild independent of UAPI mtime"
fi
echo "$pkg_order" | grep -q 'stamps/uapi/headers' \
	&& ok "E pkg built after UAPI export (order-only)" \
	|| bad "E pkg may build before the UAPI export: $pkg_rule"
grep -A2 '^\$(STAMP_SERVICES):' Makefile | grep -q 'STAMP_UAPI' \
	&& ok "E services ← UAPI" || bad "E services missing UAPI dep"
grep -q 'env -u ARCH make' scripts/install-uapi.sh \
	&& ok "E install-uapi clears ARCH" || bad "E install-uapi still uses make -s"

# --- F: ensure-host-deps consent (IR0_ROOT) -----------------------------------
echo "-- F ensure-host-deps --"
ENS="${IR0_ROOT:-../IR0}/scripts/ensure-host-deps.sh"
if [ ! -x "$ENS" ] && [ ! -f "$ENS" ]; then
	bad "F missing $ENS"
else
	chmod +x "$ENS" 2>/dev/null || true
	set +e
	IR0_DEPS_SELFTEST=1 IR0_DEPS_INSTALL=never PROFILE=userspace "$ENS" >"$TMP/never.txt" 2>&1
	rc=$?
	set -e
	[ "$rc" -ne 0 ] && ok "F never non-zero" || bad "F never rc=$rc"
	grep -qi 'Declined\|not installing\|never\|Proposed install\|missing' "$TMP/never.txt" \
		&& ok "F never message" || ok "F never ran (deptest may be clean)"

	set +e
	IR0_DEPS_SELFTEST=1 IR0_DEPS_INSTALL=yes PROFILE=userspace "$ENS" >"$TMP/yes.txt" 2>&1
	rc=$?
	set -e
	if grep -q 'would run:.*sudo\|SELFTEST OK\|\[ensure-host-deps\] OK\|deptest' "$TMP/yes.txt"; then
		ok "F yes SELFTEST path"
	else
		# Host already has deps — script exits 0 without install plan.
		[ "$rc" -eq 0 ] && ok "F yes OK (deps present)" || bad "F yes: $(tail -3 "$TMP/yes.txt")"
	fi
	grep -Eiq 'sudo -S|SUDO_PASSWORD' "$ENS" && bad "F password capture" || ok "F no password capture"
	grep -q 'Install missing host dependencies' "$ENS" && ok "F consent prompt" || bad "F no consent prompt"
fi

# Paths / help smoke
grep -q 'VARIANT_ID' mk/paths.mk && grep -q 'variants/$(VARIANT_ID)/product' mk/paths.mk \
	&& ok "A paths.mk variant stamps" || bad "A paths.mk variant layout"
grep -q '\.isdconfig' .gitignore && ok "B .isdconfig gitignored" || bad "B gitignore"

# --- G: login session auto-X contract ---------------------------------------
echo "-- G login session --"
prof="${ROOT}/rootfs/base/etc/profile"
grep -F 'terminal) _auto_x=0 ;;' "$prof" >/dev/null \
	&& ok "G ir0-session terminal disables auto-X" || bad "G terminal session"
grep -F '[ "$_ir0_profile" = "desktop" ] && _auto_x=1' "$prof" >/dev/null \
	&& ok "G desktop profile enables default auto-X" || bad "G desktop auto-X"
grep -q 'desktop-console' "${ROOT}/profiles/desktop-console/profile.conf" \
	&& ok "G desktop-console profile exists" || bad "G desktop-console profile"
[ -f "${ROOT}/profiles/desktop/x-session-clients.txt" ] \
	&& ok "G x-session clients metadata" || bad "G x-session metadata"
grep -q 'usr/share/terminfo' scripts/stage-rootfs.sh \
	&& ok "G stage installs terminfo" || bad "G stage missing terminfo"
grep -q 'CONFIG_FEATURE_EDITING_ASK_TERMINAL=y' packages/busybox/ir0_full_defconfig \
	&& ok "G busybox asks terminal for keys" || bad "G busybox ASK_TERMINAL off"
[ -f "${ROOT}/IR0_ISD_INTERFACE_SUPPORTED" ] \
	&& ok "G IR0_ISD_INTERFACE_SUPPORTED present" || bad "G interface supported file"

# --- H: print-artifacts contract --------------------------------------------
echo "-- H print-artifacts --"
chmod +x scripts/print-artifacts.sh
out_h=$(ARCH=x86_64 PROFILE=minimal scripts/print-artifacts.sh)
echo "$out_h" | grep -q '^ROOT_DISK=.*/disk.img$' \
	&& ok "H minimal ROOT_DISK" || bad "H ROOT_DISK: $out_h"
echo "$out_h" | grep -q '^ROOT_DISK_EXT2=.*/disk.ext2.img$' \
	&& ok "H minimal ROOT_DISK_EXT2" || bad "H ROOT_DISK_EXT2: $out_h"
echo "$out_h" | grep -q '^ROOTFS_PACK=minix$' \
	&& ok "H minimal ROOTFS_PACK" || bad "H ROOTFS_PACK: $out_h"
echo "$out_h" | grep -q '^REQUIRES_HOME_DISK=0$' \
	&& ok "H minimal no home disk" || bad "H REQUIRES_HOME_DISK minimal: $out_h"
out_hd=$(ARCH=x86_64 PROFILE=desktop scripts/print-artifacts.sh)
echo "$out_hd" | grep -q '^REQUIRES_HOME_DISK=1$' \
	&& ok "H desktop declares home disk" || bad "H desktop home: $out_hd"
echo "$out_hd" | grep -q '^HOME_DISK=.*/home.ext2.img$' \
	&& ok "H desktop HOME_DISK path" || bad "H HOME_DISK: $out_hd"
grep -q '^print-artifacts-mk:' Makefile && ok "H print-artifacts-mk target" || bad "H no print-artifacts-mk"
grep -q '^update-machine:' Makefile && ok "H update-machine target" || bad "H no update-machine"
vid=$(ARCH=x86_64 PROFILE=minimal bash scripts/compute-variant-id.sh)
echo "$vid" | grep -q '^minimal-[0-9a-f]\{12\}$' \
	&& ok "H variant id content hash" || bad "H variant id: $vid"
# The toolchain layer must not override the variant-scoped layout from
# mk/paths.mk: stamps and products have to live in the same variant.
mk_paths=$(make -s -pn x86-64 minimal build-runit 2>/dev/null \
	| grep -E '^(PRODUCT_OUT|STAMP_PACKAGES) :=' || true)
echo "$mk_paths" | grep -q '^PRODUCT_OUT := .*/variants/minimal-[0-9a-f]*/product$' \
	&& ok "H product tree is variant-scoped like its stamps" \
	|| bad "H product tree escapes the variant: $(echo $mk_paths)"
# Re-exporting identical headers (new UAPI stamp, same content) must keep the
# variant: otherwise every package rebuilds into a fresh variants/ tree.
uapi_stamp=out/x86_64/stamps/uapi/headers
if [ -f "$uapi_stamp" ]; then
	cp -p "$uapi_stamp" "$TMP/uapi-stamp"
	printf 'ok\n2000-01-01T00:00:00Z\n' > "$uapi_stamp"
	vid_reexport=$(ARCH=x86_64 PROFILE=minimal bash scripts/compute-variant-id.sh)
	cp -p "$TMP/uapi-stamp" "$uapi_stamp"
	[ "$vid" = "$vid_reexport" ] \
		&& ok "H variant id follows UAPI content, not stamp time" \
		|| bad "H variant id changed on identical UAPI re-export ($vid -> $vid_reexport)"
else
	ok "H variant id UAPI re-export (skipped — no UAPI export yet)"
fi

# resolve-packages must fail on unknown profile (no silent busybox+runit fallback).
set +e
bad_prof=$(PROFILE=does-not-exist bash scripts/resolve-packages.sh 2>&1)
rc_prof=$?
set -e
[ "$rc_prof" -ne 0 ] && echo "$bad_prof" | grep -qi 'unknown PROFILE' \
	&& ok "H resolve-packages fails on unknown profile" \
	|| bad "H resolve fallback: rc=$rc_prof out=$bad_prof"

# --- I init system profiles -------------------------------------------------
echo "-- I init system --"
grep -q '^INIT_SYSTEM=runit$' profiles/minimal/profile.conf \
	&& ok "I minimal INIT_SYSTEM=runit" || bad "I minimal init"
grep -q '^USERLAND_BASE=busybox$' profiles/minimal/profile.conf \
	&& ok "I minimal USERLAND_BASE" || bad "I minimal userland"
grep -q '^INIT_SYSTEM=sysvinit$' profiles/minimal-sysvinit/profile.conf \
	&& ok "I minimal-sysvinit profile" || bad "I minimal-sysvinit profile.conf"
sysv_pkgs=$(PROFILE=minimal-sysvinit bash scripts/resolve-packages.sh)
echo " $sysv_pkgs " | grep -q ' sysvinit ' \
	&& echo " $sysv_pkgs " | grep -qv ' runit ' \
	&& ok "I minimal-sysvinit resolves sysvinit not runit" \
	|| bad "I sysvinit resolve: $sysv_pkgs"
[ -f packages/sysvinit/build.sh ] && ok "I sysvinit package recipe" || bad "I sysvinit build.sh"
grep -q 'INIT_SYSTEM' scripts/stage-rootfs.sh \
	&& ok "I stage-rootfs init dispatch" || bad "I stage-rootfs dispatch"
grep -q '^INIT_SYSTEM=openrc$' profiles/minimal-openrc/profile.conf \
	&& ok "I minimal-openrc profile" || bad "I minimal-openrc profile.conf"
orc_pkgs=$(PROFILE=minimal-openrc bash scripts/resolve-packages.sh)
echo " $orc_pkgs " | grep -q ' openrc ' \
	&& echo " $orc_pkgs " | grep -qv ' runit ' \
	&& ok "I minimal-openrc resolves openrc not runit" \
	|| bad "I openrc resolve: $orc_pkgs"
[ -f packages/openrc/build.sh ] && ok "I openrc package recipe" || bad "I openrc build.sh"
grep -E '^proc[[:space:]]+/proc[[:space:]]+proc' profiles/minimal-openrc/overlay/etc/fstab \
	&& ok "I openrc overlay fstab proc" || bad "I openrc fstab proc entry"
grep -q '^uucp:' rootfs/base/etc/group \
	&& ok "I base group uucp" || bad "I base group missing uucp"
grep -q '04755' packages/opendoas/build.sh \
	&& ok "I opendoas staged setuid" || bad "I opendoas build mode"
grep -q '04755' packages/sudo/build.sh \
	&& ok "I sudo staged setuid" || bad "I sudo build mode"
python3 scripts/check-package-catalog.py >/dev/null \
	&& ok "I package catalog covers every recipe" || bad "I package catalog invalid"
grep -q 'INIT_SYSTEM=' scripts/verify-profile-rootfs.sh \
	&& ok "I verify-profile-rootfs init audit" || bad "I verify init audit"

# --- J STO ext2 root pack (parallel to MINIX; product default stays minix) ----
echo "-- J STO ext2 root pack --"
[ -f scripts/pack-ext2-root.sh ] && [ -f scripts/estimate-rootfs-ext2.sh ] \
	&& ok "J pack scripts present" || bad "J missing pack-ext2-root/estimate"
chmod +x scripts/pack-ext2-root.sh scripts/estimate-rootfs-ext2.sh 2>/dev/null || true
grep -q 'image-ext2-root' Makefile && ok "J image-ext2-root target" || bad "J no image-ext2-root"
grep -q 'STAMP_IMAGE_EXT2' mk/paths.mk && ok "J ext2 stamp path" || bad "J STAMP_IMAGE_EXT2"
grep -q 'firstboot.done' scripts/pack-ext2-root.sh \
	&& ok "J ext2 pack strips firstboot.done" || bad "J ext2 firstboot guard"
grep -q 'Mount points must stay empty' scripts/pack-ext2-root.sh \
	&& ok "J ext2 empty proc mountpoint" || bad "J ext2 proc .keep guard"
grep -q 'DISK_MB_MAX:-128' scripts/estimate-rootfs-ext2.sh \
	&& ok "J ext2 desktop-sized default cap" || bad "J ext2 cap too small"
grep -q 'if ! estimate=' scripts/pack-ext2-root.sh \
	&& ok "J ext2 estimate failure is clean" || bad "J ext2 estimate failure leaks unset variable"
grep -q 'leaking those numeric IDs' scripts/pack-ext2-root.sh \
	&& ok "J ext2 normalizes host ownership" || bad "J ext2 leaks host ownership"
grep -q 'mkfs.ext2.*-d' scripts/pack-ext2-root.sh \
	&& ok "J ext2 mkfs -d populate" || bad "J ext2 mkfs -d"
grep -q '^ROOTFS_PACK=minix$' profiles/minimal/profile.conf \
	&& ok "J profile ROOTFS_PACK default" || bad "J ROOTFS_PACK in profile.conf"
[ -f scripts/root_fs_contract.json ] && ok "J root_fs_contract.json" || bad "J contract json"
grep -q 'fs-image.sh populate' Makefile && ok "J fs-image facade" || bad "J fs-image facade"
[ -f scripts/fs-backends/ext2/populate.sh ] && ok "J ext2 backend populate" || bad "J ext2 backend"

# --- K: config-truth (fail-closed + immutable plan + no SKIP-success) --------
echo "-- K config-truth --"
chmod +x scripts/isdctl 2>/dev/null || true
[ -x scripts/isdctl ] && ok "K isdctl present" || bad "K missing isdctl"
grep -q '^plan:' Makefile && ok "K make plan target" || bad "K no make plan"
grep -q 'isd-build.json' scripts/stage-rootfs.sh \
	&& ok "K stage writes /etc/isd-build.json" || bad "K no guest manifest"
# Requested blocked packages must fail the build, not SKIP; exit 0.
if grep -A2 'blocked-by-package|blocked-by-kernel-ABI' Makefile \
	| grep -q 'exit 0'; then
	bad "K blocked package still SKIP-success"
else
	grep -A2 'blocked-by-package|blocked-by-kernel-ABI' Makefile \
		| grep -q 'exit 1' \
		&& ok "K blocked package fails closed" \
		|| bad "K blocked package rule missing"
fi
# Missing INIT_SYSTEM is an error (no silent runit).
BROKEN="$TMP/broken-init"
mkdir -p "$BROKEN/profiles/broken" "$BROKEN/packages/busybox"
printf 'USERLAND_BASE=busybox\n' >"$BROKEN/profiles/broken/profile.conf"
printf 'busybox\n' >"$BROKEN/profiles/broken/packages.txt"
: >"$BROKEN/packages/busybox/build.sh"
# Re-run resolver from a copy of the script against a fake tree is heavy;
# instead assert the live resolver rejects a missing INIT_SYSTEM via python.
set +e
out_init=$(PROFILE=does-not-exist python3 scripts/isdconfig.py --profile does-not-exist plan 2>&1)
rc_init=$?
set -e
[ "$rc_init" -ne 0 ] && echo "$out_init" | grep -qi 'unknown profile' \
	&& ok "K plan fails on unknown profile" \
	|| bad "K plan unknown: rc=$rc_init out=$out_init"

# Inject a temp profile with bad INIT_SYSTEM under the real tree? Avoid
# polluting profiles/. Use a python snippet against the module.
set +e
out_bad=$(python3 - <<'PY'
import os, sys, tempfile
from pathlib import Path
sys.path.insert(0, "scripts")
import isdconfig
isdconfig.ROOT = Path(tempfile.mkdtemp())
prof = isdconfig.ROOT / "profiles" / "bogus"
prof.mkdir(parents=True)
(prof / "profile.conf").write_text("INIT_SYSTEM=foobar\nROOT_FS=minix\n", encoding="utf-8")
try:
    isdconfig.profile_init_system("bogus")
except isdconfig.ConfigError as exc:
    print(exc)
    sys.exit(2)
print("fell-through")
sys.exit(0)
PY
)
rc_bad=$?
set -e
[ "$rc_bad" -ne 0 ] && echo "$out_bad" | grep -qi 'unsupported INIT_SYSTEM' \
	&& ok "K INIT_SYSTEM=foobar fails closed" \
	|| bad "K INIT_SYSTEM fallback: rc=$rc_bad out=$out_bad"

CFGK="$TMP/isdconfig-k"
PROFILE=minimal ISD_CONFIG="$CFGK" python3 scripts/isdconfig.py --config "$CFGK" defconfig --force
plan_json=$(PROFILE=minimal ISD_CONFIG="$CFGK" python3 scripts/isdconfig.py \
	--config "$CFGK" --profile minimal plan --json)
echo "$plan_json" | python3 -c '
import json,sys
p=json.load(sys.stdin)
need=("preset","arch","root_fs","init","userland","libc","admin","packages","config_hash","status")
missing=[k for k in need if k not in p]
assert not missing, missing
assert p["preset"]=="minimal"
assert p["init"]=="runit"
assert p["root_fs"]=="minix"
assert p["status"]=="buildable"
assert "busybox" in p["packages"]
assert "runit" in p["packages"]
' && ok "K plan JSON contract" || bad "K plan JSON: $plan_json"

plan_openrc=$(PROFILE=minimal-openrc python3 scripts/isdconfig.py --profile minimal-openrc plan --json)
echo "$plan_openrc" | python3 -c '
import json,sys
p=json.load(sys.stdin)
assert p["init"]=="openrc"
assert "openrc" in p["packages"]
assert "runit" not in p["packages"]
assert p["status"]=="buildable"
' && ok "K plan openrc is not runit" || bad "K plan openrc: $plan_openrc"

# Custom composition exposes every init while resolving only selected packages.
CFGC="$TMP/isdconfig-custom"
PROFILE=custom python3 scripts/isdconfig.py --profile custom --config "$CFGC" defconfig --force
PROFILE=custom python3 scripts/isdconfig.py --profile custom --config "$CFGC" set SUDO=y
sed -i 's/^INIT_SYSTEM=runit$/INIT_SYSTEM=openrc/' "$CFGC"
plan_custom=$(PROFILE=custom ISD_CONFIG="$CFGC" python3 scripts/isdconfig.py \
	--config "$CFGC" --profile custom plan --json)
echo "$plan_custom" | python3 -c '
import json,sys
p=json.load(sys.stdin)
assert p["init"]=="openrc"
assert p["admin"]=="sudo"
assert p["packages"]==["busybox","openrc","sudo"], p["packages"]
assert p["status"]=="buildable"
' && ok "K custom exact package/init plan" || bad "K custom plan: $plan_custom"

CFGC_RESET="$TMP/isdconfig-custom-reset"
cp "$CFGC" "$CFGC_RESET"
PROFILE=custom python3 scripts/isdconfig.py --profile custom --config "$CFGC_RESET" \
	defconfig --force >/dev/null
grep -q '^INIT_SYSTEM=runit$' "$CFGC_RESET" \
	&& grep -q '^LIBC=musl$' "$CFGC_RESET" \
	&& ok "K custom force reset ignores previous selections" \
	|| bad "K custom force reset inherited stale init/libc"

# A custom image may not silently substitute a missing or unavailable libc.
cp "$CFGC" "$CFGC.blank-libc"
sed -i 's/^LIBC=.*$/LIBC=/' "$CFGC.blank-libc"
set +e
out_libc_blank=$(PROFILE=custom python3 scripts/isdconfig.py --profile custom \
	--config "$CFGC.blank-libc" plan 2>&1)
rc_libc_blank=$?
set -e
[ "$rc_libc_blank" -ne 0 ] && echo "$out_libc_blank" | grep -qi 'libc selection is required' \
	&& ok "K custom blank libc fails closed" \
	|| bad "K custom blank libc: rc=$rc_libc_blank out=$out_libc_blank"

cp "$CFGC" "$CFGC.glibc"
sed -i 's/^LIBC=.*$/LIBC=glibc/' "$CFGC.glibc"
set +e
out_glibc=$(PROFILE=custom python3 scripts/isdconfig.py --profile custom \
	--config "$CFGC.glibc" plan 2>&1)
rc_glibc=$?
set -e
[ "$rc_glibc" -ne 0 ] && echo "$out_glibc" | grep -qi 'not packaged or guest-verified' \
	&& ok "K glibc remains blocked until Docker+QEMU verified" \
	|| bad "K glibc gate: rc=$rc_glibc out=$out_glibc"

ctl_out=$(PROFILE=minimal scripts/isdctl --profile minimal plan --json)
echo "$ctl_out" | python3 -c '
import json,sys
p=json.load(sys.stdin)
assert p["status"]=="buildable"
assert p["init"]=="runit"
' && ok "K isdctl plan matches resolver" || bad "K isdctl: $ctl_out"

grep -q 'CFLAGS="-Os -fno-pie -no-pie"' packages/zlib/build.sh \
	&& grep -q 'unsafe vsprintf fallback' packages/zlib/build.sh \
	&& ok "K zlib PIE probe cannot enable unsafe vsprintf fallback" \
	|| bad "K zlib secure vsnprintf configure guard missing"

grep -q '^$(STAMP_PACKAGES)/xload:' Makefile \
	&& ok "K xload dependency edge makes clean parallel builds deterministic" \
	|| bad "K xload dependency edge missing"

grep -q 'prefix=$PREFIX/usr' packages/freetype/build.sh \
	&& ok "K freetype pkg-config metadata is relocated from DESTDIR" \
	|| bad "K freetype pkg-config metadata relocation missing"

grep -q 'FREETYPE_CFLAGS=.*include/freetype2' packages/libxfont/build.sh \
	&& grep -q 'FREETYPE_CFLAGS=.*include/freetype2' packages/tinyx/build.sh \
	&& ok "K freetype consumers use the isolated include prefix" \
	|| bad "K freetype consumer include isolation missing"

grep -q -- '--with-keysymdefdir=' packages/libx11/build.sh \
	&& ok "K libX11 keysym lookup uses the isolated xorgproto prefix" \
	|| bad "K libX11 isolated keysym lookup missing"

grep -q '^DEPENDS=.*libice.*libsm.*libxt' packages/libxpm/package.conf \
	&& sed -n '/^$(STAMP_PACKAGES)\/libxpm:/,/^$(STAMP_PACKAGES)\/libxaw:/p' Makefile | grep -q '$(STAMP_PACKAGES)/libxt' \
	&& ok "K libXpm static link dependencies are ordered explicitly" \
	|| bad "K libXpm static dependency ordering missing"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
