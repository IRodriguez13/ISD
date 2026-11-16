#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Check the logical ISD package catalog against buildable recipes."""
from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent
PACKAGES = ROOT / "packages"
CATALOG = PACKAGES / "catalog"


def entries(path: Path) -> list[str]:
    result: list[str] = []
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        item = raw.strip()
        if item and not item.startswith("#"):
            result.append(item)
    return result


def main() -> int:
    recipes = {path.parent.name for path in PACKAGES.glob("*/build.sh")}
    if not recipes:
        print("✗ package catalog: no buildable recipes found", file=sys.stderr)
        return 1
    if not CATALOG.is_dir():
        print(f"✗ package catalog: missing {CATALOG}", file=sys.stderr)
        return 1

    seen: dict[str, Path] = {}
    errors: list[str] = []
    for listing in sorted(CATALOG.glob("*.list")):
        for name in entries(listing):
            if name not in recipes:
                errors.append(f"{listing.relative_to(ROOT)}: unknown recipe {name}")
            elif name in seen:
                errors.append(
                    f"{listing.relative_to(ROOT)}: duplicate {name} "
                    f"(already in {seen[name].relative_to(ROOT)})"
                )
            else:
                seen[name] = listing

    for name in sorted(recipes - set(seen)):
        errors.append(f"uncatalogued recipe: packages/{name}/")

    if errors:
        for error in errors:
            print(f"✗ package catalog: {error}", file=sys.stderr)
        return 1
    print(f"✓ package catalog: {len(recipes)} recipes in {len(set(seen.values()))} categories")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
