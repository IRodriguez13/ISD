<!-- ISD AI dev rule: isd-workspace -->
<!-- alwaysApply: true -->
<!-- description: ISD rootfs builder workspace — IR0 companion, stamps, agent rules -->

# ISD workspace

**ISD** (IR0 Software Distribution): stamp-based rootfs and MINIX/ext2 images for
IR0 kernel profiles. Kernel ABI policy lives in the companion **`IR0_ROOT`** tree.

## Agent rules (canonical)

| What | Path |
|------|------|
| Tracked rules (commit these) | `Documentation/ai_driven_dev/rules/*.md` |
| Local Cursor install (gitignored) | `.cursor/rules/*.mdc` via `make ai-dev-rules-install` |
| IR0 kernel rules | `$(IR0_ROOT)/Documentation/ai_driven_dev/rules/` |

Install ISD rules on a new machine:

```bash
make ai-dev-rules-install
# or: python3 scripts/sync_ai_dev_rules.py install
```

Do **not** commit `.cursor/rules/` in this repository.

## Common targets

```bash
make fetch PROFILE=desktop
make build ARCH=x86_64 PROFILE=desktop
make rootfs-tree PROFILE=desktop
make image-minix PROFILE=desktop
```

IR0 integration (from `IR0_ROOT`): `make ensure-isd-disk PROFILE=desktop`,
`make smoke-desktop-twm-resize PROFILE=desktop`.

## Policy pointers

| Area | Doc |
|------|-----|
| Upstream patches only | `rules/isd-upstream-patches-only.md`, `Documentation/PATCHES.md` |
| Package recipes | `Documentation/PACKAGE_RECIPE.md` |
| Login / session contract | `Documentation/LOGIN_SESSION.md` |
| Profiles | `Documentation/PROFILES.md` |
