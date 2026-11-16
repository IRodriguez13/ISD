# AI agents working on ISD

**ISD** builds rootfs images and ports for the IR0 kernel. Read this file plus the
relevant rules under `Documentation/ai_driven_dev/rules/`.

## Install Cursor rules (local)

```bash
make ai-dev-rules-install
```

Canonical copies live in `Documentation/ai_driven_dev/` — not in `.cursor/` (gitignored).

## Default workflow

1. **Kernel ABI bugs** → fix in `IR0_ROOT` first; do not patch BusyBox/musl/xterm to hide them.
2. **Upstream vendor bugs** → `patches/<pkg>/` only, documented in `Documentation/PATCHES.md`.
3. **Profile/rootfs policy** → `profiles/`, `rootfs/`, `scripts/stage-rootfs.sh`.

## Verification (typical)

```bash
make help                                      # public targets (generated)
make isd-contracts IR0_ROOT=../IR0             # host contract suite
make x86-64 desktop build
scripts/verify-xterm-patch-linux-baseline.sh   # when patches/xterm touched
# From IR0_ROOT (boots the disk named by `make print-artifacts`):
make run x86-64 PROFILE=desktop
```

## Rule index

| Rule | Summary |
|------|---------|
| `isd-workspace.md` | Layout, install, IR0 companion |
| `isd-upstream-patches-only.md` | Sole exception for `patches/` tree |
