# ISD upstream patch registry

> **Last verified:** 2026-09-20  
> **Source of truth:** `patches/`, `scripts/apply-isd-patches.sh`, package
> `packages/*/version` + `url`.

## Policy summary

| Question | Answer |
|----------|--------|
| Where do patches live? | **`patches/<package>/`** at ISD repo root (canonical). Legacy: `packages/<pkg>/patches/`. |
| When is a patch allowed? | **Only** when IR0 kernel/userspace ABI is ruled out and the defect is in **upstream source** (xterm client, not IR0 kernel). |
| IR0-first? | **Always.** Observe on IR0 → classify → fix kernel if ABI → only then patch ISD ports. |
| Linux ground truth? | **Baseline:** `scripts/verify-xterm-patch-linux-baseline.sh` (source audit + SIGSEGV on host Linux). Full X11 session repro optional. |
| Upstream goal? | Every patch here is an **upstream submission candidate** (xterm: Thomas Dickey, `xterm@invisible-island.net`). Retire when upstream merges or version bump includes the fix. |

Agent rule: `.cursor/rules/isd-upstream-patches-only.mdc`  
IR0 cross-rule: `IR0/.cursor/rules/ir0-no-userspace-patches.mdc` (ISD exception pointer).

---

## xterm 411 — MapSelections invalid selection parameter

### Classification

| Item | Detail |
|------|--------|
| **Component** | **xterm** (X client), `button.c` — **not** TinyX / X server |
| **Function** | `MapSelections` → `isSELECT` → musl `strcmp` |
| **Symptom** | `[PF] userspace segv comm=xterm`, CR2 ≈ `0x9`, `rip=0x54af84` (strcmp), `ret=0x4054f0` (MapSelections) |
| **IR0 kernel** | `cs=user`, `USER_PROT_READ`, no `KERNEL_UACCESS_FAULT` — **not** an IR0 MM/uaccess regression |
| **Trigger (observed)** | Desktop session (twm + xterm): selection/paste action path (`xtermGetSelection`), often during mouse/window interaction — not PTY WINCH kernel path |
| **Patch** | `patches/xterm/0001-…patch` · full report: `patches/xterm/REPORT.md` |

### Root cause (technical)

Xt action callbacks pass `String *params` into `MapSelections`. The loop calls
`isSELECT(params[j])`, which expands to `strcmp(NonNull(value), "SELECT")`.
`NonNull(NULL)` is safe (`"<null>"`), but a **non-null garbage pointer** (e.g.
`(String)9`) passes no validation and faults inside `strcmp`.

This is **client-side xterm** defensive gap, not evidence that IR0 memory
hardening failed open.

### Patch behavior

- Adds `InvalidSelectionParam()` — rejects `String` values with address `< 4096`
  (cannot be valid user C strings on x86).
- Skips invalid entries with `xtermWarning` instead of SIGSEGV.
- Minimal diff suitable for upstream review.

### Verification

#### IR0 (done)

```bash
# Symbolize crash (desktop rootfs binary)
XTERM=../ISD/out/x86_64/rootfs/desktop/usr/bin/xterm
addr2line -e "$XTERM" -f -C 0x54af84 0x4054f0
# → strcmp @ … ; MapSelections @ button.c

# Patch applies cleanly
scripts/apply-isd-patches.sh xterm
patch -p1 -N --dry-run -d packages/xterm/src \
  -i patches/xterm/0001-button-MapSelections-guard-invalid-selection-param.patch
```

#### Linux production baseline (done)

```bash
cd ISD
scripts/verify-xterm-patch-linux-baseline.sh
# 1) vanilla xterm-411 button.c lacks InvalidSelectionParam
# 2) ISD patch applies cleanly to vanilla tree
# 3) linux-baseline-repro.c SIGSEGV on host Linux (exit 139) — not IR0-specific
```

Full twm + xterm 411 + Xorg repro on Linux remains optional; the minimal repro
uses the same `isSELECT`/strcmp logic as vanilla `MapSelections`.

#### IR0 smoke (done)

```bash
cd IR0
make smoke-desktop-twm-resize PROFILE=desktop   # PASS 2026-09-20 (patched xterm rootfs)
```

#### IR0 build (done)

```bash
cd ISD
scripts/apply-isd-patches.sh xterm
rm -f out/x86_64/stamps/packages/xterm
make build-xterm ARCH=x86_64 PROFILE=desktop   # PASS 2026-09-20
```

#### Linux production (integration — optional)

On a Linux host with **xterm 411** built from the same tarball:

1. Build vanilla xterm-411 (no patch).
2. Reproduce twm + xterm selection/resize session; confirm same strcmp fault
   in `MapSelections` (gdb backtrace or core `addr2line`).
3. Rebuild with ISD patch; confirm warning + no crash.

**Baseline already confirmed** via `verify-xterm-patch-linux-baseline.sh` without
a full X session.

### Upstream submission notes

- **Maintainer:** Thomas E. Dickey (xterm)
- **List / contact:** https://invisible-island.net/xterm/
- **Suggested subject:** `xterm: guard MapSelections against invalid Xt String parameters`
- **Include:** CR2, rip/ret symbolization, IR0 log excerpt, `patches/xterm/REPORT.md`, `linux-baseline-repro.c`

### Retire criteria

Remove patch when:

- Upstream xterm release includes equivalent fix, **or**
- ISD bumps xterm version with fix in vendor `button.c`, **or**
- Linux repro fails and root cause is traced to IR0 (patch withdrawn).

---

## opendoas (legacy location)

Existing patches remain under `packages/opendoas/patches/` (pre-policy). Do not
move without a dedicated review; new work uses `patches/opendoas/` if needed.
