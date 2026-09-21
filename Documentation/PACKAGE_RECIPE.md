# Package recipes

> **Last verified:** 2026-07-26

Each `packages/<pkg>/` provides `version`, `url`, `sha256`, `build.sh`.
Build tools come only from `scripts/toolchain.sh`.

**Upstream patches:** canonical tree `patches/<pkg>/` (see `Documentation/PATCHES.md`,
`.cursor/rules/isd-upstream-patches-only.mdc`). Applied by `scripts/apply-isd-patches.sh`
on fetch and before X autotools builds. Legacy `packages/<pkg>/patches/` still supported.

Setuid allowlist: `packages/setuid.allowlist`.
Install path: `scripts/stage-rootfs.sh` → DESTDIR tree (not MINIX-aware).
