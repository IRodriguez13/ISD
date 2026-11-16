# ISA registry

Everything ISA-specific that ISD needs to locate a toolchain or decide whether
a package can be built lives here, one directory per ISA. Recipes under
`packages/<name>/` stay shared and ISA-neutral; never fork a recipe into this
tree.

```text
packages/arch/<isa>/
  arch.conf   ISD_ARCH_TRIPLE (musl target triple), ISD_ARCH_ELF_MACHINE
              (readelf "Machine:" patterns accepted by elf-audit)
  aliases     other names accepted for <isa>: Make selectors and ARCH=
  support     "<package> <status>" rows; first match wins, `*` is the default
```

`<isa>` is the canonical name used for `out/<isa>/` and `sysroot/<isa>/`.
Statuses are `supported`, `buildable`, `blocked-by-package`,
`blocked-by-kernel-ABI` and `unsupported`; the package stamp refuses anything
but `supported` and `buildable`.

`scripts/arch-policy.sh` is the only reader of these files (Make reads the
`aliases` word list directly so `make help` stays probe-free). Scripts, Make
and recipes must not branch on `$ARCH`; the contract suite rejects such
branches.

## Adding an ISA

1. Create `packages/arch/<isa>/` with the three files above.
2. Add `rootfs/arch/<isa>/` if the root filesystem needs ISA-local files.
3. Run `make <isa> minimal plan` and `make isd-contracts`.

No Makefile, script or recipe edit is required.
