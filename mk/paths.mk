# SPDX-License-Identifier: GPL-3.0-only
# ISD output and stamp layout (included by the top-level Makefile).
#
#   out/<arch>/
#     product/          package + service binaries
#     rootfs/<profile>/ finished tree
#     images/<profile>/ disk.img
#     stamps/{toolchain,uapi,packages,services,rootfs,images}/

ARCH     ?= x86_64
PROFILE  ?= minimal

# Per-profile variant tree (content hash invalidates stale product/ stamps).
VARIANT_ID := $(shell PROFILE=$(PROFILE) ARCH=$(ARCH) IR0_ROOT="$(IR0_ROOT)" \
	bash $(CURDIR)/scripts/compute-variant-id.sh 2>/dev/null)
ifeq ($(strip $(VARIANT_ID)),)
VARIANT_ID := $(PROFILE)
endif

OUT_ARCH    := $(CURDIR)/out/$(ARCH)
PRODUCT_OUT := $(OUT_ARCH)/variants/$(VARIANT_ID)/product
ROOTFS_OUT  := $(OUT_ARCH)/rootfs
ROOTFS_DIR  := $(ROOTFS_OUT)/$(PROFILE)
IMAGE_DIR   := $(OUT_ARCH)/images/$(PROFILE)
DISK        := $(IMAGE_DIR)/disk.img
DISK_EXT2   := $(IMAGE_DIR)/disk.ext2.img

TESTS_OUT ?= $(OUT_ARCH)/tests
SMOKE_OUT ?= $(OUT_ARCH)/smoke

STAMP_DIR       := $(OUT_ARCH)/stamps
STAMP_TOOLCHAIN := $(STAMP_DIR)/toolchain/ok
STAMP_UAPI      := $(STAMP_DIR)/uapi/headers
STAMP_PACKAGES  := $(STAMP_DIR)/variants/$(VARIANT_ID)/packages
STAMP_SERVICES  := $(STAMP_DIR)/variants/$(VARIANT_ID)/services
STAMP_ROOTFS    := $(STAMP_DIR)/rootfs/$(PROFILE)
STAMP_IMAGE     := $(STAMP_DIR)/images/$(PROFILE).minix
STAMP_IMAGE_EXT2 := $(STAMP_DIR)/images/$(PROFILE).ext2

export OUT_ARCH PRODUCT_OUT ROOTFS_OUT ROOTFS_DIR IMAGE_DIR DISK
export TESTS_OUT SMOKE_OUT
export STAMP_DIR STAMP_TOOLCHAIN STAMP_UAPI STAMP_PACKAGES STAMP_SERVICES
export STAMP_ROOTFS STAMP_IMAGE
export DISK_EXT2 STAMP_IMAGE_EXT2
