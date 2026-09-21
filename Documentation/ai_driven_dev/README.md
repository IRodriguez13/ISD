# AI-Assisted Development for ISD

This directory is the **tracked, versioned** copy of rules for AI coding agents
(Cursor, etc.) working on the ISD rootfs builder.

Local IDE configuration under `.cursor/` is **gitignored** and must be installed
from here when setting up a machine (`make ai-dev-rules-install`). Do **not**
commit rules under `.cursor/rules/` in the repository root.

## Layout

| Path | Purpose |
|------|---------|
| `AGENTS.md` | Short agent entrypoint |
| `rules/*.md` | Full rule set (workspace, upstream patches policy) |

## Install into Cursor (local only)

From the repository root:

```bash
make ai-dev-rules-install
# or
python3 scripts/sync_ai_dev_rules.py install
```

This copies rules into `.cursor/rules/*.mdc` and `AGENTS.md` to the repo root
(also gitignored).

## Export after editing local Cursor rules

If you maintain rules in `.cursor/` first:

```bash
python3 scripts/sync_ai_dev_rules.py export
```

Review the diff under `Documentation/ai_driven_dev/` before committing.

## IR0 companion

Kernel ABI, smokes, and tier policy live in **`IR0_ROOT/Documentation/ai_driven_dev/`**
(default `../IR0`). ISD agents must still follow IR0 kernel-first rules when the
bug is observable from userspace on IR0.

## Rule index

| Rule | Scope | Summary |
|------|-------|---------|
| `isd-workspace.md` | always | Stamps, targets, rule install path |
| `isd-upstream-patches-only.md` | always | `patches/` sole exception; IR0-first |
