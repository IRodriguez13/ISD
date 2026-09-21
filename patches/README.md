# ISD root patches (`patches/`)

> **Last verified:** 2026-09-20  
> **Policy rule:** `Documentation/ai_driven_dev/rules/isd-upstream-patches-only.md`  
> **Full registry:** `Documentation/PATCHES.md`

## Purpose

This directory is the **only** sanctioned place for ISD changes to **upstream
third-party source trees** (xterm, future X clients, etc.).

It is **not** for:

- IR0 kernel ABI belts (fix the kernel first — see IR0
  `ir0-no-userspace-patches.mdc`)
- BusyBox/musl/login hacks to hide syscall bugs
- “Works on IR0” shortcuts without upstream justification

## Layout

```text
patches/
  README.md                 ← this file
  <package>/                ← matches packages/<package>/ name
    NNNN-subject.patch      ← unified diff, applies with patch -p1 in src/
```

Legacy per-package patches under `packages/<pkg>/patches/` still apply, but
**new upstream-candidate work** belongs here so it is visible and reviewable.

## Application

Patches apply automatically via `scripts/apply-isd-patches.sh`:

- on `make fetch` (fresh unpack)
- before every Xorg autotools build (`build-xorg-autotools.sh`)

Re-runs are idempotent (`patch -N`).

Manual:

```bash
scripts/apply-isd-patches.sh xterm
```

## Adding a patch (checklist)

1. **IR0 first** — prove the kernel is not at fault (`USER_FAULT_FRAME` with
   `cs=user`, no `KERNEL_UACCESS_FAULT`, Linux repro when possible).
2. **One logical fix per file** — subject line names package + symptom.
3. **Document** in `Documentation/PATCHES.md` (symptom, symbolized rip, IR0
   vs Linux status, upstream list target).
4. **Test** — rebuild package + profile smoke that triggered the bug.
5. **Upstream intent** — patch must be suitable to send to the maintainer
   (Thomas Dickey / xterm for xterm patches).

## Current patches

| Patch | Package | Status |
|-------|---------|--------|
| `xterm/0001-button-MapSelections-guard-invalid-selection-param.patch` | xterm 411 | IR0 repro ✓ · build ✓ · smoke ✓ · Linux baseline ✓ |

Details: `patches/xterm/REPORT.md` · verify: `scripts/verify-xterm-patch-linux-baseline.sh`

See `Documentation/PATCHES.md` for evidence and verification commands.
