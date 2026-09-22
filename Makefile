# SPDX-License-Identifier: GPL-3.0-only
#
# ISD — IR0 Software Distribution (stamp-based builder).
#
#   make isd-defconfig
#   make fetch
#   make headers                 # IR0_ROOT=../IR0  or IR0_UAPI_TARBALL=...
#   make build ARCH=x86_64 PROFILE=minimal
#   make rootfs-tree PROFILE=minimal
#   make image-minix PROFILE=minimal
#
# Kernel tree is only used for UAPI export and MINIX/ISO adapters.

SHELL := /bin/bash

IR0_ROOT ?= $(abspath $(CURDIR)/../IR0)
DISK_MB  ?= 200
HOME_DISK_MB ?= 64
PROFILE  ?= minimal
ARCH     ?= x86_64

# Ensure out/ exists before toolchain stamp generation.
# Do not mkdir at parse time — it breaks IR0 release-check-clean fresh guard.
ifeq ($(origin CC),default)
  CC :=
endif

include mk/paths.mk
include mk/toolchain.mk

# Resolved set: core ∪ profile packages.txt ∪ profile-local config.
# Empty or failed resolve is a hard error (no silent busybox+runit fallback).
RESOLVED_PACKAGES := $(shell PROFILE=$(PROFILE) bash $(CURDIR)/scripts/resolve-packages.sh)
ifeq ($(strip $(RESOLVED_PACKAGES)),)
  $(error resolve-packages.sh failed or returned empty for PROFILE=$(PROFILE))
endif

PKG_STAMPS := $(addprefix $(STAMP_PACKAGES)/,$(RESOLVED_PACKAGES))

# Overlay / rootfs inputs for the rootfs stamp graph.
ROOTFS_FIND_DIRS := rootfs/base rootfs/etc rootfs/root \
	profiles/$(PROFILE) rootfs/arch/$(ARCH) rootfs/local
ROOTFS_INPUTS := \
	scripts/stage-rootfs.sh \
	profiles/$(PROFILE)/profile.conf \
	profiles/$(PROFILE)/packages.txt \
	profiles/$(PROFILE)/services.txt \
	profiles/$(PROFILE)/applets.txt \
	$(wildcard .isdconfig.d/$(PROFILE)) \
	$(shell find $(ROOTFS_FIND_DIRS) -type f 2>/dev/null)

.PHONY: all fetch headers build build-packages build-services build-tests \
	disk rootfs rootfs-tree rootfs-manifest rootfs-tar image-minix image-ext2-root image \
	profiles-check toolchain-check elf-audit uapi-audit personal-data-check \
	rootfs-check release-check clean distclean help check-kernel check-ir0 \
	check-ir0-interface isd-contracts isd-verify-rootfs \
	compat-links isd-defconfig isdconfig validate-config resolve-packages \
	plan \
	print-artifacts print-artifacts-mk update-machine image-ext2-home \
	ai-dev-rules-install \
	$(addprefix build-,$(RESOLVED_PACKAGES))

all: build

help:
	@echo "ISD — IR0 Software Distribution (stamp-based)"
	@echo "  ARCH=$(ARCH)  PROFILE=$(PROFILE)  IR0_ROOT=$(IR0_ROOT)"
	@echo "  DISK=$(DISK)"
	@echo "  RESOLVED_PACKAGES=$(RESOLVED_PACKAGES)"
	@echo "  Targets: isd-defconfig isdconfig validate-config resolve-packages plan"
	@echo "           fetch headers build toolchain-check elf-audit"
	@echo "           rootfs-tree rootfs-tar image-minix image-ext2-root image rootfs"
	@echo "           profiles-check personal-data-check rootfs-check release-check"
	@echo "           ai-dev-rules-install clean distclean"
	@echo "  fetch:     download missing packages/*/dist + unpack packages/*/src"
	@echo "             (skips when already present — safe to re-run)"
	@echo "  clean:     remove out/ only (build artefacts); keeps packages/*/src+dist"
	@echo "  distclean: clean + delete packages/*/src (keeps downloaded dist/ tarballs)"

check-ir0-interface:
	@chmod +x scripts/check-ir0-interface.sh scripts/ir0-public-tool.sh
	@IR0_ROOT="$(IR0_ROOT)" scripts/check-ir0-interface.sh

check-kernel: check-ir0-interface

check-ir0: check-kernel

isd-contracts:
	@chmod +x tests/contracts/run.sh
	@./tests/contracts/run.sh

isd-verify-rootfs: rootfs-tree personal-data-check rootfs-check rootfs-manifest
	@chmod +x scripts/verify-profile-rootfs.sh
	@PROFILE=$(PROFILE) ARCH=$(ARCH) scripts/verify-profile-rootfs.sh "$(ROOTFS_DIR)"
isd-defconfig:
	@chmod +x scripts/isdconfig.py
	@PROFILE=$(PROFILE) python3 scripts/isdconfig.py defconfig

# Interactive: keep stdin/stdout as the caller's TTY (no /dev/null redirect).
isdconfig:
	@chmod +x scripts/isdconfig.py
	@PROFILE=$(PROFILE) python3 scripts/isdconfig.py menu

validate-config:
	@chmod +x scripts/isdconfig.py scripts/resolve-packages.sh
	@PROFILE=$(PROFILE) python3 scripts/isdconfig.py --profile $(PROFILE) defconfig
	@PROFILE=$(PROFILE) python3 scripts/isdconfig.py --profile $(PROFILE) validate
	@PROFILE=$(PROFILE) bash scripts/resolve-packages.sh >/dev/null

resolve-packages:
	@chmod +x scripts/resolve-packages.sh
	@PROFILE=$(PROFILE) scripts/resolve-packages.sh

# Immutable resolver output. Does not fetch, compile, or pack.
plan:
	@chmod +x scripts/isdconfig.py scripts/isdctl scripts/resolve-packages.sh
	@PROFILE=$(PROFILE) ARCH=$(ARCH) python3 scripts/isdconfig.py \
		--profile $(PROFILE) plan

print-artifacts:
	@chmod +x scripts/print-artifacts.sh
	@ARCH=$(ARCH) PROFILE=$(PROFILE) scripts/print-artifacts.sh

print-artifacts-mk:
	@ARCH=$(ARCH) PROFILE=$(PROFILE) scripts/print-artifacts.sh | sed \
		-e 's/^ROOT_DISK=/ROOT_DISK:=/' \
		-e 's/^ROOT_DISK_EXT2=/ROOT_DISK_EXT2:=/' \
		-e 's/^HOME_DISK=/HOME_DISK:=/' \
		-e 's/^ROOTFS=/ROOTFS:=/' \
		-e 's/^ROOTFS_STAMP=/ROOTFS_STAMP:=/' \
		-e 's/^REQUIRES_HOME_DISK=/REQUIRES_HOME_DISK:=/' \
		-e 's/^ROOTFS_PACK=/ROOTFS_PACK:=/' \
		-e 's/^ROOT_FS=/ROOT_FS:=/' \
		-e 's/^VARIANT_ID=/VARIANT_ID:=/' \
		-e 's/^ARCH=/ARCH:=/' \
		-e 's/^PROFILE=/PROFILE:=/'

update-machine:
	@chmod +x scripts/update-machine.sh scripts/ir0-public-tool.sh
	@IR0_ROOT="$(IR0_ROOT)" ARCH="$(ARCH)" PROFILE="$(PROFILE)" \
		MACHINE_DIR="$(MACHINE_DIR)" scripts/update-machine.sh

# --- stamps: toolchain / UAPI ------------------------------------------------

$(STAMP_TOOLCHAIN): scripts/toolchain.sh scripts/stamp-run.sh
	@chmod +x scripts/stamp-run.sh scripts/toolchain.sh
	@scripts/stamp-run.sh $@ -- bash -c 'ARCH=$(ARCH) source scripts/toolchain.sh && \
		echo "  TC      $$CC" && $$CC --version | head -1'

$(STAMP_UAPI): $(STAMP_TOOLCHAIN) scripts/install-uapi.sh scripts/stamp-run.sh
	@chmod +x scripts/install-uapi.sh scripts/stamp-run.sh
	@scripts/stamp-run.sh $@ -- env IR0_ROOT="$(IR0_ROOT)" \
		IR0_UAPI_TARBALL="$(IR0_UAPI_TARBALL)" \
		IR0_UAPI_SYSROOT="$(IR0_UAPI_SYSROOT)" \
		scripts/install-uapi.sh
	@echo "✓ headers (UAPI stamp $@)"

headers: $(STAMP_UAPI)

fetch:
	@chmod +x scripts/fetch-package.sh scripts/resolve-packages.sh
	@set -e; pkgs="$$(PROFILE=$(PROFILE) scripts/resolve-packages.sh)"; \
	for p in $$pkgs; do scripts/fetch-package.sh "$$p"; done

# --- packages: depend on toolchain ONLY (not UAPI) ---------------------------

build-packages: validate-config $(PKG_STAMPS)

$(STAMP_PACKAGES)/%: $(STAMP_TOOLCHAIN) packages/%/build.sh scripts/stamp-run.sh \
		scripts/toolchain.sh | $(STAMP_TOOLCHAIN)
	@chmod +x packages/$*/build.sh scripts/toolchain.sh scripts/stamp-run.sh
	@mkdir -p "$(STAMP_PACKAGES)" "$(PRODUCT_OUT)"
	@scripts/stamp-run.sh $@ -- bash -c ' \
		status=$$(ARCH=$(ARCH) bash -c "source scripts/toolchain.sh && toolchain_pkg_status $*"); \
		echo "  PKG     $* [$$status] ARCH=$(ARCH)"; \
		case "$$status" in \
			unsupported) echo "✗ $* unsupported on ARCH=$(ARCH)"; exit 1 ;; \
			blocked-by-package|blocked-by-kernel-ABI) \
				echo "✗ $* requested but $$status"; exit 1 ;; \
		esac; \
		ARCH=$(ARCH) CC="$(CC)" MUSL_CC="$(CC)" PRODUCT_OUT="$(PRODUCT_OUT)" \
			OUT="$(PRODUCT_OUT)" SYSROOT="$(SYSROOT)" \
			packages/$*/build.sh'

# nano requires ncurses prefix from the ncurses stamp.
ifneq ($(filter nano,$(RESOLVED_PACKAGES)),)
$(STAMP_PACKAGES)/nano: $(STAMP_PACKAGES)/ncurses
endif

# X11 bootstrap order.  Each recipe consumes only the staged prefixes of its
# declared dependencies; keeping these edges explicit also makes parallel
# profile builds deterministic.
$(STAMP_PACKAGES)/xtrans: $(STAMP_PACKAGES)/xorgproto
$(STAMP_PACKAGES)/libxau: $(STAMP_PACKAGES)/xorgproto
$(STAMP_PACKAGES)/libxdmcp: $(STAMP_PACKAGES)/xorgproto
$(STAMP_PACKAGES)/libxcb: $(STAMP_PACKAGES)/xorgproto \
	$(STAMP_PACKAGES)/xcb-proto \
	$(STAMP_PACKAGES)/libxau $(STAMP_PACKAGES)/libxdmcp
$(STAMP_PACKAGES)/libx11: $(STAMP_PACKAGES)/xorgproto \
	$(STAMP_PACKAGES)/xtrans $(STAMP_PACKAGES)/libxcb
$(STAMP_PACKAGES)/libxext: $(STAMP_PACKAGES)/xorgproto \
	$(STAMP_PACKAGES)/libxau $(STAMP_PACKAGES)/libx11
$(STAMP_PACKAGES)/libice: $(STAMP_PACKAGES)/xorgproto \
	$(STAMP_PACKAGES)/xtrans
$(STAMP_PACKAGES)/libsm: $(STAMP_PACKAGES)/xorgproto \
	$(STAMP_PACKAGES)/xtrans $(STAMP_PACKAGES)/libice
$(STAMP_PACKAGES)/libxt: $(STAMP_PACKAGES)/xorgproto \
	$(STAMP_PACKAGES)/libx11 $(STAMP_PACKAGES)/libsm \
	$(STAMP_PACKAGES)/libice
$(STAMP_PACKAGES)/libxmu: $(STAMP_PACKAGES)/xorgproto \
	$(STAMP_PACKAGES)/libx11 $(STAMP_PACKAGES)/libxext \
	$(STAMP_PACKAGES)/libxt
$(STAMP_PACKAGES)/libxpm: $(STAMP_PACKAGES)/xorgproto \
	$(STAMP_PACKAGES)/libx11 $(STAMP_PACKAGES)/libxext
$(STAMP_PACKAGES)/libxaw: $(STAMP_PACKAGES)/xorgproto \
	$(STAMP_PACKAGES)/libx11 $(STAMP_PACKAGES)/libxext \
	$(STAMP_PACKAGES)/libxt $(STAMP_PACKAGES)/libxmu \
	$(STAMP_PACKAGES)/libxpm
$(STAMP_PACKAGES)/libxfixes: $(STAMP_PACKAGES)/xorgproto \
	$(STAMP_PACKAGES)/libx11
$(STAMP_PACKAGES)/libxrender: $(STAMP_PACKAGES)/xorgproto \
	$(STAMP_PACKAGES)/libx11
$(STAMP_PACKAGES)/libxcursor: $(STAMP_PACKAGES)/xorgproto \
	$(STAMP_PACKAGES)/libx11 $(STAMP_PACKAGES)/libxfixes \
	$(STAMP_PACKAGES)/libxrender
$(STAMP_PACKAGES)/libxi: $(STAMP_PACKAGES)/xorgproto \
	$(STAMP_PACKAGES)/libx11 $(STAMP_PACKAGES)/libxext \
	$(STAMP_PACKAGES)/libxfixes
$(STAMP_PACKAGES)/libxtst: $(STAMP_PACKAGES)/xorgproto \
	$(STAMP_PACKAGES)/libx11 $(STAMP_PACKAGES)/libxext \
	$(STAMP_PACKAGES)/libxi
$(STAMP_PACKAGES)/libfontenc: $(STAMP_PACKAGES)/xorgproto \
	$(STAMP_PACKAGES)/zlib
$(STAMP_PACKAGES)/libxfont: $(STAMP_PACKAGES)/xorgproto \
	$(STAMP_PACKAGES)/xtrans $(STAMP_PACKAGES)/freetype \
	$(STAMP_PACKAGES)/libfontenc $(STAMP_PACKAGES)/zlib
$(STAMP_PACKAGES)/tinyx: $(STAMP_PACKAGES)/xorgproto \
	$(STAMP_PACKAGES)/xtrans $(STAMP_PACKAGES)/libxau \
	$(STAMP_PACKAGES)/libxdmcp $(STAMP_PACKAGES)/libx11 \
	$(STAMP_PACKAGES)/libxext \
	$(STAMP_PACKAGES)/libxi $(STAMP_PACKAGES)/libxtst \
	$(STAMP_PACKAGES)/freetype \
	$(STAMP_PACKAGES)/libfontenc $(STAMP_PACKAGES)/libxfont \
	$(STAMP_PACKAGES)/zlib
$(STAMP_PACKAGES)/tinyx: $(STAMP_PACKAGES)/font-cursor-misc \
	$(STAMP_PACKAGES)/font-misc-misc \
	$(STAMP_PACKAGES)/font-adobe-75dpi
$(STAMP_PACKAGES)/xinit: $(STAMP_PACKAGES)/xorgproto \
	$(STAMP_PACKAGES)/libx11 $(STAMP_PACKAGES)/xauth
$(STAMP_PACKAGES)/xauth: $(STAMP_PACKAGES)/xorgproto \
	$(STAMP_PACKAGES)/libxau $(STAMP_PACKAGES)/libx11 \
	$(STAMP_PACKAGES)/libxext $(STAMP_PACKAGES)/libice \
	$(STAMP_PACKAGES)/libsm $(STAMP_PACKAGES)/libxt \
	$(STAMP_PACKAGES)/libxmu
$(STAMP_PACKAGES)/twm: $(STAMP_PACKAGES)/xorgproto \
	$(STAMP_PACKAGES)/libx11 $(STAMP_PACKAGES)/libxext \
	$(STAMP_PACKAGES)/libice $(STAMP_PACKAGES)/libsm \
	$(STAMP_PACKAGES)/libxt $(STAMP_PACKAGES)/libxmu
$(STAMP_PACKAGES)/xterm: $(STAMP_PACKAGES)/xorgproto \
	$(STAMP_PACKAGES)/libx11 $(STAMP_PACKAGES)/libxext \
	$(STAMP_PACKAGES)/libice $(STAMP_PACKAGES)/libsm \
	$(STAMP_PACKAGES)/libxt $(STAMP_PACKAGES)/libxmu \
	$(STAMP_PACKAGES)/libxpm $(STAMP_PACKAGES)/libxaw \
	$(STAMP_PACKAGES)/ncurses
$(STAMP_PACKAGES)/xclock: $(STAMP_PACKAGES)/xorgproto \
	$(STAMP_PACKAGES)/libx11 $(STAMP_PACKAGES)/libxt \
	$(STAMP_PACKAGES)/libxmu $(STAMP_PACKAGES)/libxpm \
	$(STAMP_PACKAGES)/libxaw
$(STAMP_PACKAGES)/xeyes: $(STAMP_PACKAGES)/xorgproto \
	$(STAMP_PACKAGES)/libx11 $(STAMP_PACKAGES)/libxext \
	$(STAMP_PACKAGES)/libice $(STAMP_PACKAGES)/libsm \
	$(STAMP_PACKAGES)/libxt $(STAMP_PACKAGES)/libxmu \
	$(STAMP_PACKAGES)/libxrender
$(STAMP_PACKAGES)/xlogo: $(STAMP_PACKAGES)/xorgproto \
	$(STAMP_PACKAGES)/libx11 $(STAMP_PACKAGES)/libxext \
	$(STAMP_PACKAGES)/libice $(STAMP_PACKAGES)/libsm \
	$(STAMP_PACKAGES)/libxt $(STAMP_PACKAGES)/libxmu \
	$(STAMP_PACKAGES)/libxpm $(STAMP_PACKAGES)/libxaw \
	$(STAMP_PACKAGES)/libxrender
$(STAMP_PACKAGES)/xcalc: $(STAMP_PACKAGES)/xorgproto \
	$(STAMP_PACKAGES)/libx11 $(STAMP_PACKAGES)/libxext \
	$(STAMP_PACKAGES)/libice $(STAMP_PACKAGES)/libsm \
	$(STAMP_PACKAGES)/libxt $(STAMP_PACKAGES)/libxmu \
	$(STAMP_PACKAGES)/libxpm $(STAMP_PACKAGES)/libxaw
$(STAMP_PACKAGES)/xmessage: $(STAMP_PACKAGES)/xorgproto \
	$(STAMP_PACKAGES)/libx11 $(STAMP_PACKAGES)/libxext \
	$(STAMP_PACKAGES)/libice $(STAMP_PACKAGES)/libsm \
	$(STAMP_PACKAGES)/libxt $(STAMP_PACKAGES)/libxmu \
	$(STAMP_PACKAGES)/libxpm $(STAMP_PACKAGES)/libxaw
$(STAMP_PACKAGES)/xsetroot: $(STAMP_PACKAGES)/xorgproto \
	$(STAMP_PACKAGES)/libx11 $(STAMP_PACKAGES)/libxmu \
	$(STAMP_PACKAGES)/libxfixes $(STAMP_PACKAGES)/libxrender \
	$(STAMP_PACKAGES)/libxcursor $(STAMP_PACKAGES)/xbitmaps

$(addprefix build-,$(RESOLVED_PACKAGES)): build-%: $(STAMP_PACKAGES)/%
	@true

# --- services: toolchain + UAPI ----------------------------------------------

$(STAMP_SERVICES): $(STAMP_TOOLCHAIN) $(STAMP_UAPI) scripts/build-services.sh \
		$(wildcard services/*.c) $(wildcard lib/*.c) \
		scripts/stamp-run.sh
	@chmod +x scripts/build-services.sh scripts/stamp-run.sh
	@mkdir -p "$(dir $@)" "$(PRODUCT_OUT)" "$(SMOKE_OUT)"
	@scripts/stamp-run.sh $@ -- env ARCH=$(ARCH) CC="$(CC)" MUSL_CC="$(CC)" \
		PRODUCT_OUT="$(PRODUCT_OUT)" SMOKE_OUT="$(SMOKE_OUT)" \
		SYSROOT="$(SYSROOT)" \
		scripts/build-services.sh product

build-services: $(STAMP_SERVICES)

build: build-packages build-services compat-links

build-tests: $(STAMP_TOOLCHAIN) $(STAMP_UAPI)
	@chmod +x scripts/build-services.sh
	@ARCH=$(ARCH) CC="$(CC)" MUSL_CC="$(CC)" PRODUCT_OUT="$(PRODUCT_OUT)" \
		SMOKE_OUT="$(SMOKE_OUT)" TESTS_OUT="$(TESTS_OUT)" SYSROOT="$(SYSROOT)" \
		scripts/build-services.sh smoke
	@$(MAKE) -s -C tests/host run

# Legacy paths expected by the kernel tree (symlinks into out/<arch>/product).
compat-links: build-packages build-services
	@mkdir -p out "$(SMOKE_OUT)" "$(TESTS_OUT)"
	@ln -sfn "$(PRODUCT_OUT)/busybox-full" out/busybox-full
	@ln -sfn "$(PRODUCT_OUT)/busybox-auth" out/busybox-auth
	@ln -sfn "$(PRODUCT_OUT)/bin" out/bin
	@ln -sfn "$(PRODUCT_OUT)/stage-bin" out/stage-bin
	@ln -sfn "$(SMOKE_OUT)" out/smoke
	@ln -sfn "$(PRODUCT_OUT)" out/product

toolchain-check: $(STAMP_TOOLCHAIN)
	@chmod +x scripts/toolchain.sh
	@ARCH=$(ARCH) bash -c 'source scripts/toolchain.sh && \
		echo "ARCH=$$ARCH TARGET_TRIPLE=$$TARGET_TRIPLE"; \
		echo "CC=$$CC"; $$CC --version | head -1; \
		echo "READELF=$$READELF"; \
		echo "✓ toolchain-check OK"'

elf-audit: compat-links
	@chmod +x scripts/elf-audit.sh
	@ARCH=$(ARCH) READELF="$(READELF)" PRODUCT_OUT="$(PRODUCT_OUT)" \
		scripts/elf-audit.sh

uapi-audit: $(STAMP_UAPI)
	@chmod +x scripts/uapi-audit.sh
	@IR0_UAPI_SYSROOT="$(IR0_UAPI_SYSROOT)" scripts/uapi-audit.sh

personal-data-check:
	@chmod +x scripts/personal-data-check.sh
	@PROFILE=$(PROFILE) ARCH=$(ARCH) ROOTFS_OUT="$(ROOTFS_OUT)" \
		scripts/personal-data-check.sh

profiles-check: compat-links
	@chmod +x scripts/profiles-check.sh
	@PRODUCT_OUT="$(PRODUCT_OUT)" scripts/profiles-check.sh

# --- rootfs / image ----------------------------------------------------------

# stage-rootfs.sh is a prerequisite: editing the installer must restage the
# image, otherwise a newly installed binary silently never reaches the disk.
$(STAMP_ROOTFS): $(PKG_STAMPS) $(STAMP_SERVICES) $(STAMP_UAPI) \
		$(ROOTFS_INPUTS) scripts/stage-rootfs.sh scripts/stamp-run.sh
	@chmod +x scripts/stage-rootfs.sh scripts/stamp-run.sh
	@mkdir -p "$(ROOTFS_DIR)" "$(dir $@)"
	@scripts/stamp-run.sh $@ -- env IR0_ROOT="$(IR0_ROOT)" \
		IR0_PRODUCT_PROFILE="$(PROFILE)" ARCH="$(ARCH)" \
		PRODUCT_OUT="$(PRODUCT_OUT)" ROOTFS_OUT="$(ROOTFS_OUT)" \
		IR0_GUEST_MANDOC_DIR="$(IR0_GUEST_MANDOC_DIR)" \
		ISD_PACKAGES_MANIFEST="$(RESOLVED_PACKAGES)" \
		scripts/stage-rootfs.sh "$(ROOTFS_DIR)"

rootfs-tree: $(STAMP_ROOTFS)

rootfs-manifest: rootfs-tree
	@chmod +x scripts/rootfs-manifest.sh
	@scripts/rootfs-manifest.sh "$(ROOTFS_DIR)" \
		"$(ROOTFS_DIR).manifest"

rootfs-tar: rootfs-manifest
	@tar --sort=name --owner=0 --group=0 --numeric-owner \
		--mtime="@$${SOURCE_DATE_EPOCH:-0}" \
		-C "$(ROOTFS_DIR)" -cf "$(ROOTFS_DIR).tar" .
	@echo "✓ rootfs-tar $(ROOTFS_DIR).tar"

$(DISK): | check-ir0
	@mkdir -p $(dir $(DISK))
	@echo "  DISK    $(DISK) ($(DISK_MB)M MINIX)"
	@dd if=/dev/zero of=$(DISK) bs=1M count=$(DISK_MB) status=none
	@INJECT=$$(bash scripts/ir0-public-tool.sh "$(IR0_ROOT)" ir0-minix-inject-path); \
		python3 "$$INJECT" --format-large $(DISK)

disk: $(DISK)

$(STAMP_IMAGE): $(STAMP_ROOTFS) $(DISK) scripts/pack-minix.sh scripts/stamp-run.sh \
		| check-ir0
	@chmod +x scripts/pack-minix.sh scripts/stamp-run.sh
	@mkdir -p "$(dir $@)" "$(IMAGE_DIR)"
	@scripts/stamp-run.sh $@ -- env IR0_ROOT="$(IR0_ROOT)" ARCH="$(ARCH)" \
		PROFILE="$(PROFILE)" \
		scripts/pack-minix.sh "$(ROOTFS_DIR)" "$(DISK)"

# Primary image path: finished tree → MINIX adapter.
image-minix: $(STAMP_IMAGE)

# STO-1: host-built EXT2 root (parallel path; product default remains MINIX until STO-4).
image-ext2-root: $(STAMP_IMAGE_EXT2)

$(STAMP_IMAGE_EXT2): $(STAMP_ROOTFS) scripts/pack-ext2-root.sh \
		scripts/estimate-rootfs-ext2.sh scripts/stamp-run.sh
	@chmod +x scripts/pack-ext2-root.sh scripts/estimate-rootfs-ext2.sh
	@mkdir -p "$(dir $(STAMP_IMAGE_EXT2))" "$(IMAGE_DIR)"
	@scripts/stamp-run.sh $(STAMP_IMAGE_EXT2) -- \
		scripts/fs-image.sh populate ext2 "$(ROOTFS_DIR)" "$(DISK_EXT2)"

# Profile-selected root image (ROOT_FS=minix|ext2 in profile.conf or make ROOT_FS=…).
image-root: $(STAMP_ROOTFS) scripts/fs-image.sh scripts/stamp-run.sh \
		scripts/root_fs_contract.json
	@chmod +x scripts/fs-image.sh scripts/fs-backends/*/*.sh 2>/dev/null || true
	@ROOT_FS="$${ROOT_FS:-$$(grep -E '^ROOT_FS=' profiles/$(PROFILE)/profile.conf 2>/dev/null | tail -1 | cut -d= -f2 || echo minix)}"; \
	ROOT_FS="$${ROOT_FS:-minix}"; \
	case "$$ROOT_FS" in minix) STAMP="$(STAMP_IMAGE)"; DISK="$(DISK)" ;; \
	ext2) STAMP="$(STAMP_IMAGE_EXT2)"; DISK="$(DISK_EXT2)" ;; \
	*) echo "✗ unknown ROOT_FS=$$ROOT_FS"; exit 2 ;; esac; \
	mkdir -p "$$(dirname "$$STAMP")" "$(IMAGE_DIR)"; \
	scripts/stamp-run.sh "$$STAMP" -- \
		scripts/fs-image.sh populate "$$ROOT_FS" "$(ROOTFS_DIR)" "$$DISK"

# Backward-compatible alias used by the kernel tree (MINIX product default).
rootfs: image-minix

image: image-root

image-ext2-home:
	@mkdir -p "$(IMAGE_DIR)"
	@chmod +x scripts/create-ext2-home.sh
	@HOME_DISK_MB="$(HOME_DISK_MB)" scripts/create-ext2-home.sh \
		"$(IMAGE_DIR)/home.ext2.img"
	@$(MAKE) -s -C $(IR0_ROOT) kernel-x64-userspace.iso
	@echo "✓ image ready: $(IR0_ROOT)/kernel-x64-userspace.iso + $(DISK)"

rootfs-check: rootfs-tree personal-data-check
	@chmod +x scripts/rootfs-check.sh
	@PROFILE=$(PROFILE) ARCH=$(ARCH) READELF="$(READELF)" \
		scripts/rootfs-check.sh "$(ROOTFS_DIR)"

release-check: check-ir0-interface toolchain-check elf-audit uapi-audit profiles-check \
	isd-contracts isd-verify-rootfs
	@$(MAKE) -s -C tests/host run
	@echo "✓ release-check OK PROFILE=$(PROFILE) ARCH=$(ARCH)"

# Build artefacts only. Never delete packages/*/src or packages/*/dist.
clean:
	@rm -rf out
	@echo "✓ clean (out/ removed; packages/*/src and dist/ kept)"

# Drop unpacked sources too (re-fetch or re-unpack from dist/ next time).
# Downloaded tarballs under packages/*/dist are preserved.
distclean: clean
	@rm -rf $(SYSROOT) packages/*/src
	@echo "✓ distclean (src/ removed; dist/ tarballs kept)"

ai-dev-rules-install:
	@python3 scripts/sync_ai_dev_rules.py install
