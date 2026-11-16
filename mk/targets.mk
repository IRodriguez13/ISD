# SPDX-License-Identifier: GPL-3.0-only
# The ISD Make interface.  `make help` is generated from these tables and
# scripts/check-make-help.sh (contract suite) fails when the Makefile defines a
# target that is not classified here, so help cannot drift from the graph.
#
#   public      supported entry points, one-line description each
#   internal    graph nodes and conventions; may change without notice
#   deprecated  old names kept as aliases that print their replacement

ISD_HELP_GROUPS := build config check integration maintenance

ISD_HELP_TITLE.build := Build
ISD_TARGETS.build := isd fetch headers build build-<pkg> plan rootfs-tree \
	image-root
ISD_HELP.isd := build the selected profile image (default action)
ISD_HELP.fetch := download and unpack the sources of the resolved packages
ISD_HELP.headers := export the IR0 UAPI headers to sysroot/<arch> only
ISD_HELP.build := build every resolved package and the IR0 services
ISD_HELP.build-<pkg> := build one resolved package, e.g. build-busybox
ISD_HELP.plan := show the resolved packages and ISA blockers (no build)
ISD_HELP.rootfs-tree := stage the root filesystem tree out/<arch>/rootfs/<profile>
ISD_HELP.image-root := pack the tree into the profile ROOT_FS image (minix|ext2)

ISD_HELP_TITLE.config := Configure
ISD_TARGETS.config := menuconfig isdconfig validate-config resolve-packages
ISD_HELP.menuconfig := choose an exact custom distribution (profile custom)
ISD_HELP.isdconfig := same full-screen selector as menuconfig
ISD_HELP.validate-config := validate the selected distribution configuration
ISD_HELP.resolve-packages := print the resolved package list of the profile

ISD_HELP_TITLE.check := Check
ISD_TARGETS.check := toolchain-check uapi-audit elf-audit profiles-check \
	rootfs-check personal-data-check package-catalog-check isd-contracts \
	isd-verify-rootfs check-ir0-interface release-check
ISD_HELP.toolchain-check := show the resolved cross toolchain for the ISA
ISD_HELP.uapi-audit := audit the exported IR0 UAPI headers
ISD_HELP.elf-audit := check product ELFs match the ISA and are static
ISD_HELP.profiles-check := check profile outputs against the product tree
ISD_HELP.rootfs-check := check the staged tree (setuid, ELF, layout)
ISD_HELP.personal-data-check := refuse host personal data in the staged tree
ISD_HELP.package-catalog-check := check the package catalog against recipes
ISD_HELP.isd-contracts := run the host-side ISD contract suite
ISD_HELP.isd-verify-rootfs := stage, check and verify one profile tree
ISD_HELP.check-ir0-interface := check IR0_ROOT against IR0_ISD_INTERFACE
ISD_HELP.release-check := run the complete host-side release gate

ISD_HELP_TITLE.integration := IR0 integration
ISD_TARGETS.integration := isd-defconfig print-artifacts print-artifacts-mk \
	image-minix image-ext2-root rootfs-manifest rootfs-tar image-ext2-home \
	update-machine
ISD_HELP.isd-defconfig := write .isdconfig.d/<profile> defaults if missing
ISD_HELP.print-artifacts := print the artifact manifest IR0 consumes
ISD_HELP.print-artifacts-mk := same manifest as Make assignments
ISD_HELP.image-minix := pack the tree into a MINIX root image
ISD_HELP.image-ext2-root := pack the tree into an ext2 root image
ISD_HELP.rootfs-manifest := write a manifest of the staged tree
ISD_HELP.rootfs-tar := write a reproducible tarball of the staged tree
ISD_HELP.image-ext2-home := create the ext2 home disk and the IR0 boot ISO
ISD_HELP.update-machine := refresh an IR0 machine with this profile tree

ISD_HELP_TITLE.maintenance := Maintenance
ISD_TARGETS.maintenance := clear distclean ai-dev-rules-install help
ISD_HELP.clear := remove out/<arch> and sysroot/<arch> for one ISA
ISD_HELP.distclean := clear, then drop unpacked sources (downloads kept)
ISD_HELP.ai-dev-rules-install := install the agent rules into .cursor/
ISD_HELP.help := show this help (no probes)

ISD_PUBLIC_TARGETS := $(foreach g,$(ISD_HELP_GROUPS),$(ISD_TARGETS.$(g)))

# all: GNU convention for isd.  targets: machine-readable classification.
ISD_INTERNAL_TARGETS := all build-packages build-services build-tests \
	compat-links disk targets

# old:new pairs.  Each old name stays an alias that names its replacement.
ISD_DEPRECATED_TARGETS := rootfs:image-minix image:image-root clean:clear \
	check-kernel:check-ir0-interface check-ir0:check-ir0-interface
ISD_DEPRECATED_NAMES := $(foreach d,$(ISD_DEPRECATED_TARGETS),$(firstword $(subst :, ,$(d))))

define isd_deprecated_alias
$(1): $(2)
	@echo "note: 'make $(1)' is deprecated; use 'make $(2)'" >&2
endef
$(foreach d,$(ISD_DEPRECATED_TARGETS),$(eval $(call isd_deprecated_alias,$(firstword $(subst :, ,$(d))),$(lastword $(subst :, ,$(d))))))

targets:
	@printf 'public %s\n' $(foreach t,$(ISD_PUBLIC_TARGETS),'$(t)')
	@printf 'internal %s\n' $(ISD_INTERNAL_TARGETS)
	@printf 'deprecated %s %s\n' $(subst :, ,$(ISD_DEPRECATED_TARGETS))
	@printf 'selector %s\n' $(ISD_SELECTOR_GOALS)
