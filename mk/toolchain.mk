# SPDX-License-Identifier: GPL-3.0-only
# Included by the top-level Makefile. Resolves ARCH and toolchain once.

ARCH ?= x86_64
export ARCH

ifeq ($(origin _IR0_TC_INCLUDED), undefined)
_IR0_TC_INCLUDED := 1
ISD_TOOLCHAIN_CACHE ?= /tmp/isd-toolchain-$(shell id -u)-$(shell printf '%s' '$(CURDIR)' | cksum | cut -d' ' -f1)-$(ARCH).mk
include $(shell ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) \
	bash $(CURDIR)/scripts/toolchain-print.sh > $(ISD_TOOLCHAIN_CACHE) && \
	echo $(ISD_TOOLCHAIN_CACHE))
endif

IR0_UAPI_SYSROOT ?= $(CURDIR)/sysroot
SYSROOT ?= $(IR0_UAPI_SYSROOT)
export IR0_UAPI_SYSROOT SYSROOT
export CC TARGET_TRIPLE AR RANLIB STRIP READELF OBJCOPY
export PRODUCT_OUT TESTS_OUT SMOKE_OUT ROOTFS_OUT OUT_ARCH MUSL_CC
