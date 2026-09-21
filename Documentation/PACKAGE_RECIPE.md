# Package recipes

> **Last verified:** 2026-07-26

Each `packages/<pkg>/` provides `version`, `url`, `sha256`, `build.sh`.
Build tools come only from `scripts/toolchain.sh`.

**Upstream patches:** canonical tree `patches/<pkg>/` (see `Documentation/PATCHES.md`,
`Documentation/ai_driven_dev/rules/isd-upstream-patches-only.md`). Applied by
`scripts/apply-isd-patches.sh` on fetch and before X autotools builds. Install
agent rules locally: `make ai-dev-rules-install`. Legacy `packages/<pkg>/patches/`
still supported.

Setuid allowlist: `packages/setuid.allowlist`.
Install path: `scripts/stage-rootfs.sh` → DESTDIR tree (not MINIX-aware).
