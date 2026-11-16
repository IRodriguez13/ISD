# Toolchain and targets

> **Last verified:** 2026-11-16  
> **Source of truth:** `packages/arch/<isa>/`, `scripts/arch-policy.sh`,
> `scripts/toolchain.sh`, `mk/toolchain.mk`

```bash
make x86-64 desktop toolchain-check
make x86-64 desktop build
make arm minimal plan             # plan + ISA blockers, no compiler probe;
                                  # exits 1 while a package is blocked
make arm minimal                  # needs an aarch64-musl toolchain and no
                                  # blocked package in the profile
make x86-64 desktop elf-audit
```

Variables: `ARCH`, `TARGET_TRIPLE`, `CROSS_COMPILE`, `CC`, `AR`, `RANLIB`,
`STRIP`, `READELF`, `OBJCOPY`, `SYSROOT`, `IR0_UAPI_SYSROOT`.

Outputs: `out/<arch>/{product,tests,smoke,rootfs/<profile>/}`.

ISA facts (accepted names, musl triple, ELF machine, per-package support
status) are data under `packages/arch/<isa>/`; see `packages/arch/README.md`.
`scripts/arch-policy.sh status <isa> <package>...` prints the status that the
package stamp enforces, e.g. on aarch64 busybox/runit are `buildable` and
sudo/ncurses/nano are `blocked-by-package`. x86_64 supports every recipe.
