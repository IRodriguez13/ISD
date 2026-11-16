# Toolchain and targets

> **Last verified:** 2026-07-26  
> **Source of truth:** `scripts/toolchain.sh`, `mk/toolchain.mk`

```bash
make x86-64 desktop toolchain-check
make x86-64 desktop build
make arm minimal plan             # package plan without probing a compiler
make arm minimal                  # builds once an aarch64-musl toolchain exists
make x86-64 desktop elf-audit
```

Variables: `ARCH`, `TARGET_TRIPLE`, `CROSS_COMPILE`, `CC`, `AR`, `RANLIB`,
`STRIP`, `READELF`, `OBJCOPY`, `SYSROOT`, `IR0_UAPI_SYSROOT`.

Outputs: `out/<arch>/{product,tests,smoke,rootfs/<profile>/}`.

| ARCH | busybox/runit | sudo/ncurses/nano |
|------|---------------|------------------------|
| x86_64 | supported | supported |
| aarch64 | buildable | blocked-by-package |
