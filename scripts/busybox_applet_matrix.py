#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""
Build and check the IR0 BusyBox applet status matrix.

Status comes from real runs inside IR0 (smoke/busybox_matrix_smoke.c, tag
BBMATRIX) plus a small table of applets validated by other gates
(packages/busybox/applet_evidence.tsv). An applet present in the binary but never
exercised is reported as "unverified" — it is never promoted to "supported"
just because it compiled.

Usage:
  busybox_applet_matrix.py --log LOG --binary BB [--write TSV]
                           [--write-development FILE]
  busybox_applet_matrix.py --check --matrix TSV --profiles DIR
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "packages" / "busybox" / "applet_evidence.tsv"

LINE_RE = re.compile(
    r"BBMATRIX applet=(?P<applet>\S+) status=(?P<status>\S+) "
    r"ec=(?P<ec>-?\d+) reason=(?P<reason>\S+)"
)
STATUSES = ("supported", "partial", "unavailable", "unverified")


def applet_list(binary: Path) -> list[str]:
    out = subprocess.run(
        [str(binary), "--list"], check=True, capture_output=True, text=True
    )
    return sorted({line.strip() for line in out.stdout.splitlines() if line.strip()})


def read_evidence() -> dict[str, tuple[str, str]]:
    """applet -> (status, evidence) for applets validated by other gates."""
    table: dict[str, tuple[str, str]] = {}
    if not EVIDENCE.is_file():
        return table
    for raw in EVIDENCE.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        parts = [p for p in parts if p]
        if len(parts) < 3:
            continue
        applet, status, evidence = parts[0], parts[1], parts[2]
        if status not in STATUSES:
            raise SystemExit(f"{EVIDENCE}: unknown status {status!r} for {applet}")
        table[applet] = (status, evidence)
    return table


def parse_log(log: Path) -> dict[str, tuple[str, str]]:
    """applet -> (status, evidence) from the guest matrix run."""
    if not log.is_file():
        raise SystemExit(f"missing matrix log: {log}")
    text = log.read_text(errors="replace")
    if "BBMATRIX_OK" not in text:
        raise SystemExit(f"{log}: matrix run did not finish (no BBMATRIX_OK)")

    result: dict[str, tuple[str, str]] = {}
    for m in LINE_RE.finditer(text):
        applet = m.group("applet")
        status = m.group("status")
        reason = m.group("reason")
        detail = f"busybox-matrix(ec={m.group('ec')}"
        detail += ")" if reason == "-" else f",{reason})"
        result[applet] = (status, detail)
    if not result:
        raise SystemExit(f"{log}: no BBMATRIX lines found")
    return result


def probe_host_help(binary: Path, applet: str) -> tuple[str, str]:
    """Presence probe only: does the host binary carry this applet?

    Runs on the build host, so it says nothing about IR0 behavior. It can
    only tell "not in the binary" (unavailable) from "in the binary but
    never exercised under IR0" (unverified). Promoting these to "supported"
    is what made the matrix claim 381 working applets while the guest run
    covered 37.
    """
    try:
        proc = subprocess.run(
            [str(binary), applet, "--help"],
            check=False,
            capture_output=True,
            text=True,
            timeout=3,
        )
    except subprocess.TimeoutExpired:
        return "unverified", "host-help(timeout)"
    out = (proc.stdout or "") + (proc.stderr or "")
    if "applet not found" in out:
        return "unavailable", "host-help(missing)"
    return "unverified", "host-help(present)"


def build_matrix_host_help(binary: Path) -> list[tuple[str, str, str]]:
    """Host --help probe + evidence overrides (no QEMU)."""
    from_evidence = read_evidence()
    rows: list[tuple[str, str, str]] = []
    for applet in applet_list(binary):
        if applet in from_evidence:
            status, evidence = from_evidence[applet]
        else:
            status, evidence = probe_host_help(binary, applet)
        rows.append((applet, status, evidence))
    return rows


def build_matrix(log: Path, binary: Path) -> list[tuple[str, str, str]]:
    from_log = parse_log(log)
    from_evidence = read_evidence()
    rows: list[tuple[str, str, str]] = []
    for applet in applet_list(binary):
        if applet in from_log:
            status, evidence = from_log[applet]
        elif applet in from_evidence:
            status, evidence = from_evidence[applet]
        else:
            # Guest matrix covers hot paths; the rest stay unverified.
            status, evidence = probe_host_help(binary, applet)
        rows.append((applet, status, evidence))
    return rows


def write_matrix(rows: list[tuple[str, str, str]], dest: Path) -> None:
    width = max(len(r[0]) for r in rows) + 1
    lines = [
        "# IR0 BusyBox applet status — generated by make busybox-matrix.",
        "# Do not edit by hand: status must come from a run, not from a build.",
        "# applet\tstatus\tevidence",
    ]
    for applet, status, evidence in rows:
        lines.append(f"{applet.ljust(width)}\t{status}\t{evidence}")
    dest.write_text("\n".join(lines) + "\n")


def read_matrix(path: Path) -> dict[str, tuple[str, str]]:
    if not path.is_file():
        raise SystemExit(f"missing matrix: {path} (run make busybox-matrix)")
    table: dict[str, tuple[str, str]] = {}
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = [p for p in line.split("\t") if p.strip()]
        if len(parts) < 2:
            continue
        table[parts[0].strip()] = (parts[1].strip(),
                                   parts[2].strip() if len(parts) > 2 else "-")
    return table


def read_profile(path: Path) -> list[str]:
    applets = []
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        applets.append(line)
    return applets


def check_profiles(matrix_path: Path, profiles_dir: Path) -> int:
    matrix = read_matrix(matrix_path)
    failures: list[str] = []

    for profile in sorted(profiles_dir.glob("*.txt")):
        name = profile.stem
        applets = read_profile(profile)
        if not applets:
            failures.append(f"{name}: empty profile")
            continue
        missing = [a for a in applets if a not in matrix]
        if missing:
            failures.append(f"{name}: not in the applet matrix: {', '.join(missing)}")
        if name in ("desktop", "appliance"):
            weak = [a for a in applets
                    if a in matrix and matrix[a][0] != "supported"]
            if weak:
                detail = ", ".join(f"{a}={matrix[a][0]}" for a in weak)
                failures.append(f"{name}: not validated as supported: {detail}")
        print(f"  {name}: {len(applets)} applets")

    if failures:
        print("✗ busybox-profiles-check FAILED")
        for f in failures:
            print(f"  - {f}")
        return 1
    print("✓ busybox-profiles-check OK")
    return 0


def write_development_lists(rows: list[tuple[str, str, str]], dest: Path) -> None:
    listed = [a for a, s, _ in rows if s != "unavailable"]
    header = (
        "# Development profile — every applet the general BusyBox exposes\n"
        "# except the ones the matrix proved unavailable. Generated by\n"
        "# make busybox-matrix / --host-help; gaps are expected here on purpose.\n"
    )
    body = "\n".join(listed) + "\n"
    dest.write_text(header + body)
    # Keep nested profile in sync when writing the legacy flat list.
    nested = ROOT / "profiles" / "development" / "applets.txt"
    if dest.name == "development.txt" or dest == nested:
        nested.parent.mkdir(parents=True, exist_ok=True)
        nested.write_text(header + body)


def main() -> int:
    ap = argparse.ArgumentParser(description="BusyBox applet status matrix")
    ap.add_argument("--log")
    ap.add_argument("--binary")
    ap.add_argument("--write")
    ap.add_argument("--write-development")
    ap.add_argument("--host-help", action="store_true",
                    help="Classify via host busybox applet --help (no QEMU)")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--matrix")
    ap.add_argument("--profiles")
    args = ap.parse_args()

    if args.check:
        if not args.matrix or not args.profiles:
            ap.error("--check needs --matrix and --profiles")
        return check_profiles(Path(args.matrix), Path(args.profiles))

    if not args.binary:
        ap.error("--binary is required")

    if args.host_help:
        rows = build_matrix_host_help(Path(args.binary))
    else:
        if not args.log:
            ap.error("--log and --binary are required (or use --host-help)")
        rows = build_matrix(Path(args.log), Path(args.binary))
    counts = {s: 0 for s in STATUSES}
    for _, status, _ in rows:
        counts[status] = counts.get(status, 0) + 1

    if args.write:
        write_matrix(rows, Path(args.write))
    if args.write_development:
        write_development_lists(rows, Path(args.write_development))

    print(
        "  applets: {total} → supported={supported} partial={partial} "
        "unavailable={unavailable} unverified={unverified}".format(
            total=len(rows), **counts
        )
    )
    for applet, status, evidence in rows:
        if status in ("partial", "unavailable"):
            print(f"    {status:<12} {applet} ({evidence})")
    # Coverage gate: ≥80% of enabled applets smokeable (supported|partial).
    total = len(rows)
    ok = counts.get("supported", 0) + counts.get("partial", 0)
    pct = (100.0 * ok / total) if total else 0.0
    print(f"  smokeable: {ok}/{total} ({pct:.1f}%)")
    if pct < 80.0:
        print("✗ busybox coverage below 80% smokeable")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
