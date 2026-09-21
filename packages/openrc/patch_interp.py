#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Patch ELF PT_INTERP to a shorter path (MINIX v1 dentry limit workaround)."""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

PT_INTERP = 3
EI_CLASS = 4
ELFCLASS64 = 2
EM_386 = 3
EM_X86_64 = 62


def patch(path: Path, new_interp: str) -> None:
    data = bytearray(path.read_bytes())
    if data[EI_CLASS] != ELFCLASS64:
        raise SystemExit(f"{path}: not ELF64")
    e_phoff = struct.unpack_from("<Q", data, 0x20)[0]
    e_phentsize = struct.unpack_from("<H", data, 0x36)[0]
    e_phnum = struct.unpack_from("<H", data, 0x38)[0]
    new_b = new_interp.encode("ascii") + b"\x00"
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        p_type, p_flags, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_align = struct.unpack_from(
            "<IIQQQQQQ", data, off
        )
        if p_type != PT_INTERP:
            continue
        old = bytes(data[p_offset : p_offset + p_filesz]).split(b"\x00", 1)[0]
        if len(new_b) > p_filesz:
            raise SystemExit(
                f"{path}: new interpreter too long ({len(new_b)} > {p_filesz})"
            )
        data[p_offset : p_offset + len(new_b)] = new_b
        for j in range(len(new_b), p_filesz):
            data[p_offset + j] = 0
        print(f"  PT_INTERP {path.name}: {old.decode()} -> {new_interp}")
        path.write_bytes(data)
        return
    raise SystemExit(f"{path}: no PT_INTERP")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("interpreter")
    parser.add_argument("binaries", nargs="+", type=Path)
    args = parser.parse_args()
    for binary in args.binaries:
        if binary.is_file():
            patch(binary, args.interpreter)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
