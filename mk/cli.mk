# SPDX-License-Identifier: GPL-3.0-only
# Human-oriented ISD command line.  Keep this file dependency-free: `make`
# and `make help` must not resolve packages, probe a compiler, or touch out/.

# ISAs come from the registry: packages/arch/<isa>/ with its aliases file.
# Adding an ISA adds a directory; no selector list or branch is edited here.
ISD_ARCHES := $(patsubst packages/arch/%/arch.conf,%,\
	$(wildcard packages/arch/*/arch.conf))
isd_arch_names = $(1) $(file <packages/arch/$(1)/aliases)
ISD_ARCH_ALIASES := $(foreach a,$(ISD_ARCHES),$(call isd_arch_names,$(a)))
ISD_PROFILE_ALIASES := appliance custom desktop desktop-console development \
	minimal minimal-openrc minimal-sysvinit
ISD_SELECTOR_GOALS := $(ISD_ARCH_ALIASES) $(ISD_PROFILE_ALIASES)
ISD_ACTION_GOALS := $(filter-out $(ISD_SELECTOR_GOALS),$(MAKECMDGOALS))

ISD_SELECTED_ARCHES := $(foreach a,$(ISD_ARCHES),\
	$(if $(filter $(call isd_arch_names,$(a)),$(MAKECMDGOALS)),$(a)))
ifneq ($(words $(ISD_SELECTED_ARCHES)),0)
ifneq ($(words $(ISD_SELECTED_ARCHES)),1)
$(error select one architecture, not $(strip $(ISD_SELECTED_ARCHES)))
endif
ifneq ($(origin ARCH),command line)
ARCH := $(strip $(ISD_SELECTED_ARCHES))
endif
endif

# ARCH= may name an alias too (ARCH=arm64, ARCH=amd64): every output path and
# registry lookup uses the canonical ISA so one build never splits across
# out/<alias>/ and out/<isa>/.
ISD_ARCH_CANONICAL := $(strip $(foreach a,$(ISD_ARCHES),\
	$(if $(filter $(ARCH),$(call isd_arch_names,$(a))),$(a))))
ifneq ($(ISD_ARCH_CANONICAL),)
override ARCH := $(ISD_ARCH_CANONICAL)
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
