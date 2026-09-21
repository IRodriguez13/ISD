# xterm-411 — MapSelections invalid Xt String parameter

> **Last verified:** 2026-09-20  
> **Upstream:** xterm 411 (`https://invisible-mirror.net/archives/xterm/xterm-411.tgz`)  
> **Maintainer:** Thomas E. Dickey — https://invisible-island.net/xterm/  
> **ISD patch:** `0001-button-MapSelections-guard-invalid-selection-param.patch`

## Summary

During IR0 desktop sessions (twm + xterm on TinyX), xterm could **SIGSEGV** in
`MapSelections()` when handling Xt action parameters for selection/paste
(`SELECT` token). Symbolization shows **musl `strcmp`** with a **non-NULL garbage
pointer** (CR2 ≈ `0x9`), not an IR0 kernel uaccess fault.

This is a defect in **xterm client source** (`button.c`), not the X server
(TinyX) and not IR0 MM hardening.

## Classification (IR0-first)

| Check | Result |
|-------|--------|
| IR0 kernel uaccess | **Ruled out** — no `KERNEL_UACCESS_FAULT`; `cs=user` |
| IR0 PTY/WINCH | **Unrelated** — crash in selection path, not `TIOCSWINSZ` |
| Component | **xterm** `button.c:MapSelections` → `isSELECT` → `strcmp` |
| Linux baseline | **Confirmed** — same logic SIGSEGV on host Linux (see below) |

## IR0 crash evidence

Serial log (manual desktop session, pre-patch):

```text
USER_FAULT_FRAME vector=... cr2=9 rip=54af84 cs=1b ...
USER_FAULT_FRAME rdi=0 rsi=7fffe820
USER_FAULT_FRAME pid=27 comm=xterm ...
USER_FAULT_FRAME opc=0 ret=4054f0
[PF] userspace segv pid=27 addr=9 ... rip=54af84 user=1
```

Symbolization (ISD desktop rootfs binary, load base `0x400000`):

| Symbol | Address | Meaning |
|--------|---------|---------|
| `strcmp` | `0x54af84` | Fault inside musl `strcmp` (`movzbl (%rdi)`) |
| `MapSelections` | `0x4054f0` | Return address after `isSELECT` → `strcmp` call |
| CR2 | `0x9` | Invalid `String` param (not NULL — passes `NonNull`) |

Upstream source path:

```c
/* button.c — xtermGetSelection → MapSelections */
for (j = 0; j < num_params; ++j) {
    if (isSELECT(params[j])) {   /* strcmp(NonNull(params[j]), "SELECT") */
        map = True;
        break;
    }
}
```

`NonNull(NULL)` is safe (`"<null>"`), but **small non-NULL garbage** (e.g.
`(String)9`) is not rejected and faults in `strcmp`.

## ISD fix

Patch adds `InvalidSelectionParam()` — skip/warn when `(unsigned long)param < 4096`.

See `0001-button-MapSelections-guard-invalid-selection-param.patch`.

## Verification matrix

| Gate | Command | Result (2026-09-20) |
|------|---------|---------------------|
| Patch applies | `scripts/apply-isd-patches.sh xterm` | OK |
| Package build | `make build-xterm ARCH=x86_64 PROFILE=desktop` | OK |
| Rootfs contains patch | `strings rootfs/.../xterm \| rg ignoring` | OK |
| IR0 smoke | `make smoke-desktop-twm-resize PROFILE=desktop` (IR0 tree) | **PASS** — no `USER_FAULT_FRAME comm=xterm` |
| Linux source audit | `scripts/verify-xterm-patch-linux-baseline.sh` | **PASS** — vanilla 411 lacks guard |
| Linux dynamic repro | same script (minimal C, vanilla logic) | **PASS** — SIGSEGV exit 139 on host Linux |

### IR0 smoke (post-patch)

```bash
cd IR0
make smoke-desktop-twm-resize PROFILE=desktop
# ✓ smoke-desktop-twm-resize passed
# Guards: no USER_FAULT_FRAME / [PF] userspace segv comm=xterm
```

Note: smoke still uses WINCH **kill fallback** for twm monitor gesture (P1);
the xterm segfault guard is independent and passed.

### Linux baseline (host, no QEMU)

```bash
cd ISD
scripts/verify-xterm-patch-linux-baseline.sh
```

Uses:

- Vanilla `xterm-411.tgz` source audit
- Patch apply to clean tree
- `patches/xterm/linux-baseline-repro.c` — reproduces **vanilla MapSelections/isSELECT
  logic** with `param=(char*)9`; crashes in `strcmp` on **production Linux** glibc.

This proves the bug class is **not IR0-specific**. Full twm+xterm+Xorg integration
repro on Linux is optional follow-up (requires X11 session + xterm 411 build).

## Upstream submission

**Status:** Sent 2026-09-20 to `tdickey@invisible-island.net` (git send-email).

| Item | Detail |
|------|--------|
| Cover Message-ID | `<20260921005946.2129785-1-ivanrwcm25@gmail.com>` |
| Patch Message-ID | `<20260921005946.2129785-2-ivanrwcm25@gmail.com>` |
| Resend bundle | `patches/xterm/submission/` |
| Cover text | `patches/xterm/COVER-LETTER.txt` |

Narrative sent: found on hobby kernel IR0 → reproduced bug class on stock Linux
(`linux-baseline-repro.c`) before submitting client-side guard (4096 threshold).

**Attachments sent:** patch + `linux-baseline-repro.c`

## Retire criteria

Remove from `patches/xterm/` when:

1. Upstream merges equivalent fix, or
2. ISD bumps xterm version containing the fix, or
3. Root cause reclassified to IR0/Xt stack (patch withdrawn with evidence).

## References

- xterm `button.c` — `MapSelections`, `xtermGetSelection`, `_OwnSelection`
- IR0 `Documentation/uaccess.md` — `USER_FAULT_FRAME` interpretation
- ISD `Documentation/PATCHES.md` — registry entry
- IR0 smoke: `scripts/smoke_desktop_twm_resize.py`
