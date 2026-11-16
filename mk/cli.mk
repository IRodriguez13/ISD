# SPDX-License-Identifier: GPL-3.0-only
# Human-oriented ISD command line.  Keep this file dependency-free: `make`
# and `make help` must not resolve packages, probe a compiler, or touch out/.

ISD_ARCH_ALIASES := x86 x86-64 x86_64 arm arm64 aarch64
ISD_PROFILE_ALIASES := appliance custom desktop desktop-console development \
	minimal minimal-openrc minimal-sysvinit
ISD_SELECTOR_GOALS := $(ISD_ARCH_ALIASES) $(ISD_PROFILE_ALIASES)
ISD_ACTION_GOALS := $(filter-out $(ISD_SELECTOR_GOALS),$(MAKECMDGOALS))

ISD_X86_GOALS := $(filter x86 x86-64 x86_64,$(MAKECMDGOALS))
ISD_ARM_GOALS := $(filter arm arm64 aarch64,$(MAKECMDGOALS))
ifneq ($(strip $(ISD_X86_GOALS)),)
ifneq ($(strip $(ISD_ARM_GOALS)),)
$(error select one architecture: x86-64 or arm)
endif
endif

ifneq ($(strip $(ISD_X86_GOALS)),)
ifneq ($(origin ARCH),command line)
ARCH := x86_64
endif
endif
ifneq ($(strip $(ISD_ARM_GOALS)),)
ifneq ($(origin ARCH),command line)
ARCH := aarch64
endif
endif

ISD_SELECTED_PROFILES := $(filter $(ISD_PROFILE_ALIASES),$(MAKECMDGOALS))
ifneq ($(words $(ISD_SELECTED_PROFILES)),0)
ifneq ($(words $(ISD_SELECTED_PROFILES)),1)
$(error select one profile, not $(ISD_SELECTED_PROFILES))
endif
ifneq ($(origin PROFILE),command line)
PROFILE := $(ISD_SELECTED_PROFILES)
endif
endif

# `make arm minimal` is intentionally a complete build request.  Explicit
# actions retain their normal semantics (`make arm minimal plan`, for example).
ISD_IMPLICIT_ISD := 0
ifneq ($(strip $(MAKECMDGOALS)),)
ifeq ($(strip $(ISD_ACTION_GOALS)),)
ISD_IMPLICIT_ISD := 1
endif
endif

# Keep introspection and completion independent from a cross compiler.  The
# paths layer only calculates ISA-local names; the toolchain layer is loaded
# exclusively by actions that actually compile or stage a root filesystem.
ISD_PATH_GOALS := isd all headers build build-packages build-services \
	build-tests compat-links toolchain-check elf-audit uapi-audit profiles-check \
	rootfs-tree rootfs-manifest rootfs-tar image-minix image-ext2-root image-root \
	image rootfs image-ext2-home rootfs-check release-check isd-verify-rootfs \
	update-machine clear clean distclean disk
ISD_TOOLCHAIN_GOALS := isd all headers build build-packages build-services \
	build-tests compat-links toolchain-check elf-audit uapi-audit profiles-check \
	rootfs-tree rootfs-manifest rootfs-tar image-minix image-ext2-root image-root \
	image rootfs image-ext2-home rootfs-check release-check isd-verify-rootfs
ISD_RESOLVE_GOALS := $(ISD_TOOLCHAIN_GOALS) fetch
ISD_NEEDS_PATHS := 0
ISD_NEEDS_TOOLCHAIN := 0
ISD_NEEDS_RESOLUTION := 0
ifneq ($(filter $(ISD_PATH_GOALS),$(MAKECMDGOALS)),)
ISD_NEEDS_PATHS := 1
endif
ifneq ($(filter $(ISD_TOOLCHAIN_GOALS),$(MAKECMDGOALS)),)
ISD_NEEDS_TOOLCHAIN := 1
endif
ifneq ($(filter $(ISD_RESOLVE_GOALS),$(MAKECMDGOALS)),)
ISD_NEEDS_RESOLUTION := 1
endif
ifeq ($(ISD_IMPLICIT_ISD),1)
ISD_NEEDS_PATHS := 1
ISD_NEEDS_TOOLCHAIN := 1
ISD_NEEDS_RESOLUTION := 1
endif
