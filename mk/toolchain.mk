# SPDX-License-Identifier: GPL-3.0-only
# Included by the top-level Makefile. Resolves ARCH and toolchain once.

ARCH ?= x86_64
export ARCH

ifeq ($(origin _IR0_TC_INCLUDED), undefined)
_IR0_TC_INCLUDED := 1
ISD_TOOLCHAIN_CACHE ?= /tmp/isd-toolchain-$(shell id -u)-$(shell printf '%s' '$(CURDIR)' | cksum | cut -d' ' -f1)-$(ARCH).mk
include $(shell ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) IR0_TOOLCHAIN_OPTIONAL=1 \
	bash $(CURDIR)/scripts/toolchain-print.sh > $(ISD_TOOLCHAIN_CACHE) && \
	echo $(ISD_TOOLCHAIN_CACHE))
endif

# Headers are ABI inputs too.  Keep their staging tree per architecture so an
# aarch64 build can never overwrite an x86-64 compile environment.
IR0_UAPI_SYSROOT ?= $(CURDIR)/sysroot/$(ARCH)
SYSROOT ?= $(IR0_UAPI_SYSROOT)
export IR0_UAPI_SYSROOT SYSROOT
export CC TARGET_TRIPLE AR RANLIB STRIP READELF OBJCOPY
export MUSL_CC
