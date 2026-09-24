#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""ISD package extras + applet extras (.isdconfig) — stdlib only.

Commands: defconfig | show | set KEY=VAL | validate | plan | menu

make isdconfig → interactive menu (toggle y/n, save, validate).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CFG_DIR = ROOT / ".isdconfig.d"

# Always-on core package keys (profile selects init: runit | sysvinit | openrc).
CORE_BUSYBOX = "BUSYBOX"
SUPPORTED_INIT_SYSTEMS = frozenset({"runit", "sysvinit", "openrc"})
SUPPORTED_ROOT_FS = frozenset({"minix", "ext2"})
SUPPORTED_ADMIN = frozenset({"doas", "sudo"})
SUPPORTED_USERLAND = frozenset({"busybox"})
SUPPORTED_LIBC = frozenset({"musl"})
KNOWN_LIBCS = ("musl", "glibc")


class ConfigError(ValueError):
    """Invalid or unsupported profile/config — fail closed, no silent fallback."""

# Legacy alias — validate/menu use core_packages(profile) instead.
FORBIDDEN_DISABLE = ("BUSYBOX", "RUNIT")

def package_key(name: str) -> str:
    return name.upper().replace("-", "_")


def packaged_recipes() -> dict[str, str]:
    """Return CONFIG key -> package dir for every buildable recipe."""
    result: dict[str, str] = {}
    packages = ROOT / "packages"
    if not packages.is_dir():
        return result
    for build in sorted(packages.glob("*/build.sh")):
        name = build.parent.name
        result[package_key(name)] = name
    return result


PACKAGE_RECIPES = packaged_recipes()
# Init is selected separately and BusyBox is immutable core. Everything else
# is an exact, user-selectable package in the custom-distro menu.
EXTRAS = tuple(
    key for key, name in PACKAGE_RECIPES.items()
    if name not in {"busybox", *SUPPORTED_INIT_SYSTEMS}
)

# One admin elevation tool per profile (doas via opendoas, or gnu sudo).
ADMIN_EXTRAS = ("OPENDOAS", "SUDO")

# BusyBox applet extras — link /bin/<applet> when =y (binary must include applet).
# short → applet name
APPLETS: dict[str, str] = {
    "TOP": "top",
}

# Reserved for extras that need a non-lowercase package dir name.
# DOOM → packages/doom/ (packaged); keep map empty unless a rename is needed.
FUTURE_PACKAGES: dict[str, str] = dict(PACKAGE_RECIPES)

# If KEY=y, ensure each dep is y (or reject).
AUTO_DEPS = {
    "NANO": ("NCURSES",),
}

CORE_DEFAULTS = {k: "y" for k in FORBIDDEN_DISABLE}

# Profile-local extras default off. Product profiles declare mandatory software
# in profiles/<profile>/packages.txt, so creating a config never pollutes minimal.
EXTRA_DEFAULTS = {key: "n" for key in EXTRAS}
APPLET_DEFAULTS = {k: "y" for k in APPLETS}


def read_profile_conf(profile: str) -> dict[str, str]:
    path = ROOT / "profiles" / profile / "profile.conf"
    data: dict[str, str] = {}
    if not path.is_file():
        return data
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, val = line.split("=", 1)
        data[key.strip()] = val.strip()
    return data


def profile_exists(profile: str) -> bool:
    return (ROOT / "profiles" / profile / "profile.conf").is_file()


def profile_init_system(profile: str, path: Path | None = None) -> str:
    if not profile_exists(profile):
        raise ConfigError(f"unknown profile {profile}")
    init = read_profile_conf(profile).get("INIT_SYSTEM", "").strip()
    if profile == "custom" and path is not None:
        init = parse_cfg(path).get("INIT_SYSTEM", init).strip()
    if not init:
        raise ConfigError(f"profile {profile}: missing INIT_SYSTEM")
    if init not in SUPPORTED_INIT_SYSTEMS:
        raise ConfigError(f"profile {profile}: unsupported INIT_SYSTEM={init}")
    return init


def profile_root_fs(profile: str) -> str:
    if not profile_exists(profile):
        raise ConfigError(f"unknown profile {profile}")
    conf = read_profile_conf(profile)
    root_fs = (conf.get("ROOT_FS") or conf.get("ROOTFS_PACK") or "").strip()
    if not root_fs:
        raise ConfigError(f"profile {profile}: missing ROOT_FS")
    if root_fs not in SUPPORTED_ROOT_FS:
        raise ConfigError(f"profile {profile}: unsupported ROOT_FS={root_fs}")
    return root_fs


def profile_userland(profile: str) -> str:
    userland = read_profile_conf(profile).get("USERLAND_BASE", "busybox").strip() or "busybox"
    if userland not in SUPPORTED_USERLAND:
        raise ConfigError(f"profile {profile}: unsupported USERLAND_BASE={userland}")
    return userland


def profile_libc(profile: str, path: Path | None = None) -> str:
    libc = read_profile_conf(profile).get("LIBC", "musl").strip() or "musl"
    if profile == "custom" and path is not None:
        configured = parse_cfg(path).get("LIBC")
        if configured is not None:
            libc = configured.strip()
            if not libc:
                raise ConfigError("profile custom: libc selection is required")
    if libc not in SUPPORTED_LIBC:
        if libc == "glibc":
            raise ConfigError(
                "profile custom: glibc is not packaged or guest-verified yet; "
                "select musl until packages/glibc passes the Docker+QEMU gate"
            )
        raise ConfigError(f"profile {profile}: unsupported LIBC={libc}")
    return libc


def core_packages(profile: str, path: Path | None = None) -> tuple[str, ...]:
    init = profile_init_system(profile, path).upper()
    return (CORE_BUSYBOX, init)


def core_menu_label(profile: str, path: Path | None = None) -> str:
    init = profile_init_system(profile, path)
    return f"Core busybox + {init} are always on."


def cfg_path(explicit: str | None = None, profile: str = "minimal") -> Path:
    if explicit:
        return Path(explicit)
    env = os.environ.get("ISD_CONFIG")
    if env:
        return Path(env)
    return DEFAULT_CFG_DIR / profile


def parse_cfg(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    if not path.is_file():
        return data
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, val = line.split("=", 1)
        data[key.strip()] = val.strip()
    return data


def write_cfg(path: Path, data: dict[str, str], profile: str = "minimal") -> None:
    init = data.get("INIT_SYSTEM", "").strip() if profile == "custom" else ""
    if not init:
        init = profile_init_system(profile, path)
    if init not in SUPPORTED_INIT_SYSTEMS:
        raise ConfigError(f"profile {profile}: unsupported INIT_SYSTEM={init}")
    core = (CORE_BUSYBOX, init.upper())
    keys = (
        [f"CONFIG_PKG_{k}" for k in core]
        + [f"CONFIG_PKG_{k}" for k in EXTRAS]
        + [f"CONFIG_APPLET_{k}" for k in APPLETS]
    )
    lines = [
        "# ISD package extras (.isdconfig) — generated by scripts/isdconfig.py",
        f"# Core busybox + {init} always on. Profile packages.txt = mandatory set.",
        "# CONFIG_PKG_* = optional packages; CONFIG_APPLET_* = BusyBox links.",
        "",
    ]
    if profile == "custom":
        libc = data.get("LIBC", "").strip() or profile_libc(profile, path)
        lines.extend([f"INIT_SYSTEM={init}", f"LIBC={libc}", ""])
    for key in keys:
        if key.startswith("CONFIG_PKG_"):
            short = key[len("CONFIG_PKG_") :]
            val = data.get(
                key,
                "y" if short in core else EXTRA_DEFAULTS.get(short, "n"),
            )
        else:
            short = key[len("CONFIG_APPLET_") :]
            val = data.get(key, APPLET_DEFAULTS.get(short, "n"))
        lines.append(f"{key}={val}")
    admin = data.get("ADMIN_ELEVATION", "").strip().lower()
    if admin in ("doas", "sudo"):
        lines.extend(["", f"ADMIN_ELEVATION={admin}"])
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def ensure_defaults(data: dict[str, str], profile: str = "minimal", path: Path | None = None) -> dict[str, str]:
    out = dict(data)
    for k in core_packages(profile, path):
        out.setdefault(f"CONFIG_PKG_{k}", "y")
    for k, v in EXTRA_DEFAULTS.items():
        out.setdefault(f"CONFIG_PKG_{k}", v)
    for k, v in APPLET_DEFAULTS.items():
        out.setdefault(f"CONFIG_APPLET_{k}", v)
    return out


def pkg_enabled(data: dict[str, str], short: str) -> bool:
    return data.get(f"CONFIG_PKG_{short}", "n").lower() in ("y", "yes", "1")


def admin_elevation_from_data(data: dict[str, str], profile: str) -> str:
    """Effective admin tool: profile.conf default overridden by .isdconfig."""
    tool = read_profile_conf(profile).get("ADMIN_ELEVATION", "doas")
    override = data.get("ADMIN_ELEVATION", "").strip().lower()
    if override in ("doas", "sudo"):
        tool = override
    if pkg_enabled(data, "SUDO"):
        tool = "sudo"
    elif pkg_enabled(data, "OPENDOAS") and override != "sudo":
        tool = "doas"
    if tool not in SUPPORTED_ADMIN:
        raise ConfigError(
            f"profile {profile}: unsupported ADMIN_ELEVATION={tool}"
        )
    return tool


def apply_admin_exclusion(data: dict[str, str], enabled: str) -> None:
    """Keep at most one CONFIG_PKG_{OPENDOAS,SUDO}=y."""
    if enabled not in ADMIN_EXTRAS:
        return
    for short in ADMIN_EXTRAS:
        key = f"CONFIG_PKG_{short}"
        data[key] = "y" if short == enabled else "n"
    data["ADMIN_ELEVATION"] = "sudo" if enabled == "SUDO" else "doas"


def applet_enabled(data: dict[str, str], short: str) -> bool:
    return data.get(f"CONFIG_APPLET_{short}", "n").lower() in ("y", "yes", "1")


def pkg_dirname(short: str) -> str:
    """CONFIG_PKG_FOO → packages/<dir> name."""
    if short in FUTURE_PACKAGES:
        return FUTURE_PACKAGES[short]
    return short.lower()


def recipe_ready(short: str) -> bool:
    d = pkg_dirname(short)
    return (ROOT / "packages" / d / "build.sh").is_file()


def find_doom_iwad() -> Path | None:
    """Locate an IWAD (same rules as scripts/find-doom-iwad.sh)."""
    script = ROOT / "scripts" / "find-doom-iwad.sh"
    if not script.is_file():
        iwad = os.environ.get("ISD_DOOM_IWAD", "").strip()
        if iwad and Path(iwad).is_file():
            return Path(iwad)
        return None
    try:
        proc = subprocess.run(
            ["bash", str(script)],
            capture_output=True,
            text=True,
            check=False,
            env=os.environ.copy(),
        )
    except OSError:
        return None
    path = (proc.stdout or "").strip()
    if proc.returncode == 0 and path and Path(path).is_file():
        return Path(path)
    return None


def refuse_enable_pkg(short: str, profile: str = "minimal") -> str | None:
    """If short cannot be enabled (=y), return an error message; else None."""
    if short in core_packages(profile):
        return None
    if short not in EXTRAS:
        return f"unknown package CONFIG_PKG_{short}"
    d = pkg_dirname(short)
    if not recipe_ready(short):
        return (
            f"CONFIG_PKG_{short}=y is not buildable: packages/{d}/ not packaged yet "
            f"(interim: IR0_LEGACY_USERSPACE=1 make load-userspace-devtools)"
        )
    if short == "DOOM":
        if find_doom_iwad() is None:
            return (
                "CONFIG_PKG_DOOM=y is not buildable: no IWAD found "
                "(set ISD_DOOM_IWAD or place DOOM1.WAD in ../universal-doom/)"
            )
    return None


def validate_enabled_pkgs(data: dict[str, str], profile: str = "minimal") -> list[str]:
    """Return errors for enabled extras that cannot be built."""
    errors: list[str] = []
    enabled_admin = [s for s in ADMIN_EXTRAS if pkg_enabled(data, s)]
    if len(enabled_admin) > 1:
        errors.append(
            f"✗ admin tools are mutually exclusive: {', '.join(enabled_admin)} "
            f"(pick doas or sudo via ADMIN_ELEVATION / usmang)"
        )
    for short in EXTRAS:
        if not pkg_enabled(data, short):
            continue
        msg = refuse_enable_pkg(short, profile)
        if msg:
            errors.append(f"✗ {msg}")
    return errors


def _normalize_assignment(item: str) -> tuple[str, str, str] | None:
    """Return (kind, short, val) where kind is 'PKG' or 'APPLET'."""
    if "=" not in item:
        return None
    key, val = item.split("=", 1)
    key = key.strip()
    val = val.strip().lower()
    if val not in ("y", "n"):
        return None
    upper = key.upper()
    if upper.startswith("CONFIG_PKG_"):
        short = upper[len("CONFIG_PKG_") :]
        return ("PKG", short, val)
    if upper.startswith("CONFIG_APPLET_"):
        short = upper[len("CONFIG_APPLET_") :]
        return ("APPLET", short, val)
    if upper.startswith("PKG_"):
        return ("PKG", upper[len("PKG_") :], val)
    if upper.startswith("APPLET_"):
        return ("APPLET", upper[len("APPLET_") :], val)
    # Bare short name: prefer PKG if known, else APPLET.
    short = upper
    if short in FORBIDDEN_DISABLE or short in EXTRAS:
        return ("PKG", short, val)
    if short in APPLETS:
        return ("APPLET", short, val)
    return ("PKG", short, val)


def cmd_defconfig(path: Path, profile: str, force: bool) -> int:
    if path.is_file() and not force:
        print(f"  CONFIG    {path} already present (use --force to reset)")
        return 0
    data: dict[str, str] = {}
    defaults_path = path
    if profile == "custom" and force:
        # A forced reset must not inherit init/libc from the file being reset.
        conf = read_profile_conf(profile)
        data["INIT_SYSTEM"] = conf.get("INIT_SYSTEM", "runit")
        data["LIBC"] = conf.get("LIBC", "musl")
        defaults_path = None
    data = ensure_defaults(data, profile, defaults_path)
    write_cfg(path, data, profile)
    print(f"  CONFIG    wrote {path}")
    return 0


def cmd_show(path: Path, profile: str) -> int:
    data = ensure_defaults(parse_cfg(path), profile, path)
    print(f"# {path}")
    print("# packages")
    for k in core_packages(profile, path) + EXTRAS:
        key = f"CONFIG_PKG_{k}"
        print(f"{key}={data.get(key, 'n')}")
    print("# applets (BusyBox hardlinks)")
    for k in APPLETS:
        key = f"CONFIG_APPLET_{k}"
        print(f"{key}={data.get(key, 'n')}  → /bin/{APPLETS[k]}")
    return 0


def cmd_set(path: Path, profile: str, assignments: list[str]) -> int:
    data = ensure_defaults(parse_cfg(path), profile, path)
    core = core_packages(profile, path)
    pending: list[tuple[str, str, str]] = []
    for item in assignments:
        parsed = _normalize_assignment(item)
        if parsed is None:
            print(f"✗ expected KEY=y|n, got {item!r}", file=sys.stderr)
            return 1
        kind, short, val = parsed
        if kind == "PKG":
            if short in core and val == "n":
                print(
                    f"✗ cannot disable CONFIG_PKG_{short} (core package)",
                    file=sys.stderr,
                )
                return 1
            if short not in core and short not in EXTRAS:
                print(f"✗ unknown package key CONFIG_PKG_{short}", file=sys.stderr)
                return 1
            if val == "y":
                msg = refuse_enable_pkg(short, profile)
                if msg:
                    print(f"✗ {msg}", file=sys.stderr)
                    print("  configuration unchanged", file=sys.stderr)
                    return 1
        else:
            if short not in APPLETS:
                print(f"✗ unknown applet key CONFIG_APPLET_{short}", file=sys.stderr)
                return 1
        pending.append((kind, short, val))

    for kind, short, val in pending:
        if kind == "PKG":
            key = f"CONFIG_PKG_{short}"
            data[key] = val
            if val == "y" and short in ADMIN_EXTRAS:
                apply_admin_exclusion(data, short)
            if val == "y" and short in AUTO_DEPS:
                for dep in AUTO_DEPS[short]:
                    data[f"CONFIG_PKG_{dep}"] = "y"
        else:
            data[f"CONFIG_APPLET_{short}"] = val

    write_cfg(path, data, profile)
    print(f"  CONFIG    updated {path}")
    return 0


def cmd_validate(path: Path, profile: str) -> int:
    if not profile_exists(profile):
        print(f"✗ unknown profile {profile}", file=sys.stderr)
        return 2
    data = ensure_defaults(parse_cfg(path), profile, path)
    errors: list[str] = []

    for short in core_packages(profile, path):
        if not pkg_enabled(data, short):
            errors.append(
                f"✗ CONFIG_PKG_{short}=n is forbidden (core package; "
                f"leave CONFIG_PKG_{short}=y)."
            )

    for short, deps in AUTO_DEPS.items():
        if pkg_enabled(data, short):
            for dep in deps:
                if not pkg_enabled(data, dep):
                    errors.append(
                        f"✗ CONFIG_PKG_{short}=y requires CONFIG_PKG_{dep}=y "
                        f"(auto-dep)."
                    )

    errors.extend(validate_enabled_pkgs(data, profile))

    for short, applet in APPLETS.items():
        if not applet_enabled(data, short):
            continue
        if short == "TOP":
            frag = ROOT / "packages" / "busybox" / "ir0_full.config"
            if frag.is_file() and "CONFIG_TOP=y" not in frag.read_text(encoding="utf-8"):
                errors.append(
                    f"✗ CONFIG_APPLET_TOP=y but packages/busybox/ir0_full.config "
                    f"lacks CONFIG_TOP=y (rebuild busybox after enabling TOP)."
                )

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1

    print(f"✓ isdconfig validate OK PROFILE={profile}")
    return 0


def resolved_packages(profile: str, path: Path) -> list[str]:
    env = os.environ.copy()
    env["PROFILE"] = profile
    env["ISD_CONFIG"] = str(path)
    script = ROOT / "scripts" / "resolve-packages.sh"
    proc = subprocess.run(
        ["bash", str(script)],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
        env=env,
    )
    if proc.returncode != 0:
        err = (proc.stderr or proc.stdout or "resolve-packages failed").strip()
        raise ConfigError(err)
    return [p for p in proc.stdout.split() if p]


def build_plan(profile: str, path: Path, arch: str | None = None) -> dict:
    if not profile_exists(profile):
        raise ConfigError(f"unknown profile {profile}")
    data = ensure_defaults(parse_cfg(path), profile, path)
    errors = validate_enabled_pkgs(data, profile)
    init = profile_init_system(profile, path)
    root_fs = profile_root_fs(profile)
    userland = profile_userland(profile)
    libc = profile_libc(profile, path)
    admin = admin_elevation_from_data(data, profile)
    packages = resolved_packages(profile, path)
    missing = []
    for pkg in packages:
        if not (ROOT / "packages" / pkg / "build.sh").is_file():
            missing.append(pkg)
    arch = arch or os.environ.get("ARCH", "x86_64")
    payload = {
        "preset": profile,
        "arch": arch,
        "root_fs": root_fs,
        "init": init,
        "userland": userland,
        "libc": libc,
        "admin": admin,
        "packages": packages,
        "unavailable": missing,
        "errors": errors,
        "status": "buildable" if not errors and not missing else "invalid",
    }
    digest = hashlib.sha256(
        json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()[:16]
    payload["config_hash"] = digest
    return payload


def format_plan(plan: dict) -> str:
    pkgs = "\n".join(f"  {p}" for p in plan.get("packages") or []) or "  (none)"
    missing = plan.get("unavailable") or []
    errors = plan.get("errors") or []
    lines = [
        "ISD build plan",
        "─────────────────────────────────────────",
        f"Preset:       {plan.get('preset')}",
        f"Arch:         {plan.get('arch')}",
        f"Root FS:      {plan.get('root_fs')}",
        f"Init:         {plan.get('init')}",
        f"Userland:     {plan.get('userland')}",
        f"libc:         {plan.get('libc')}",
        f"Admin:        {plan.get('admin')}",
        "",
        "Packages resolved:",
        pkgs,
        "",
        f"Unavailable:  {', '.join(missing) if missing else 'none'}",
        f"Config hash:  {plan.get('config_hash')}",
        f"Status:       {plan.get('status')}",
    ]
    if errors:
        lines.append("Errors:")
        lines.extend(f"  {e}" for e in errors)
    return "\n".join(lines) + "\n"


def cmd_plan(path: Path, profile: str, as_json: bool) -> int:
    try:
        plan = build_plan(profile, path)
    except ConfigError as exc:
        print(f"✗ plan: {exc}", file=sys.stderr)
        return 2
    if as_json:
        print(json.dumps(plan, indent=2, sort_keys=True))
    else:
        print(format_plan(plan), end="")
    return 0 if plan.get("status") == "buildable" else 1


def _prompt_yn(inp, out, prompt: str, current: str) -> str:
    cur = current.lower() if current.lower() in ("y", "n") else "n"
    while True:
        out.write(f"{prompt} [{cur}] ")
        out.flush()
        line = inp.readline()
        if not line:
            return cur
        ans = line.strip().lower()
        if ans == "":
            return cur
        if ans in ("y", "n"):
            return ans
        if ans in ("yes", "true", "1"):
            return "y"
        if ans in ("no", "false", "0"):
            return "n"
        out.write("  enter y or n (empty keeps current)\n")
        out.flush()


class _Closer:
    def __init__(self, *files) -> None:
        self._files = files

    def close(self) -> None:
        for f in self._files:
            try:
                f.close()
            except OSError:
                pass


def _open_menu_streams():
    """Return (inp, out, closer) for the interactive menu.

    Prefer stdin/stdout when they are TTYs (works when /dev/tty is ENXIO,
    e.g. some IDE/WSL sessions). Else try /dev/tty. closer may be None.
    """
    if sys.stdin.isatty() and sys.stdout.isatty():
        return sys.stdin, sys.stdout, None
    try:
        tty = open("/dev/tty", "r+", encoding="utf-8", errors="replace")
        return tty, tty, tty
    except OSError:
        pass
    try:
        tin = open("/dev/tty", "r", encoding="utf-8", errors="replace")
        tout = open("/dev/tty", "w", encoding="utf-8", errors="replace")
        return tin, tout, _Closer(tin, tout)
    except OSError:
        pass
    return None, None, None


def _package_section(short: str) -> str:
    if short in {"OPENDOAS", "SUDO"}:
        return "Security and administration"
    if short in {"TINYCC", "GNUMAKE", "PACK_EXTRACT", "NANO", "NCURSES"}:
        return "Development tools"
    if short.startswith(("X", "LIBX", "FONT_")) or short in {
        "TINYX", "TWM", "FREETYPE", "LIBFONTENC", "ZLIB"
    }:
        return "Graphical desktop and X11"
    if short in {"DOOM", "IV"}:
        return "Applications"
    return "Libraries and system software"


def _package_label(short: str) -> str:
    if short == "PACK_EXTRACT":
        return "pack + unpack (extract alias)"
    return pkg_dirname(short)


def _menuconfig(path: Path, profile: str, data: dict[str, str]) -> int:
    """Full-screen stdlib curses selector, modelled after kernel menuconfig."""
    import curses

    rows: list[tuple[str, str, str]] = []
    if profile == "custom":
        rows.extend([
            ("choice", "INIT_SYSTEM", "Init system"),
            ("choice", "LIBC", "C library"),
        ])
    sections = (
        "Security and administration",
        "Development tools",
        "Graphical desktop and X11",
        "Applications",
        "Libraries and system software",
    )
    for section in sections:
        members = [short for short in EXTRAS if _package_section(short) == section]
        if not members:
            continue
        rows.append(("header", section, section))
        rows.extend(("pkg", short, _package_label(short)) for short in members)
    rows.append(("header", "BusyBox applets", "BusyBox applets"))
    rows.extend(("applet", short, applet) for short, applet in APPLETS.items())
    selectable = [i for i, row in enumerate(rows) if row[0] != "header"]

    def draw(stdscr) -> int:
        curses.curs_set(0)
        stdscr.keypad(True)
        pos = 0
        top = 0
        message = "Space/Enter: select   S: save   Q: discard   arrows: navigate"
        while True:
            height, width = stdscr.getmaxyx()
            visible = max(3, height - 6)
            current = selectable[pos]
            if current < top:
                top = current
            if current >= top + visible:
                top = current - visible + 1
            stdscr.erase()
            stdscr.addnstr(0, 2, "ISD Distribution Configuration", width - 4, curses.A_BOLD)
            stdscr.addnstr(1, 2, f"Profile: {profile}   Config: {path}", width - 4)
            for screen_y, row_i in enumerate(range(top, min(len(rows), top + visible)), 3):
                kind, key, label = rows[row_i]
                attr = curses.A_REVERSE if row_i == current else curses.A_NORMAL
                if kind == "header":
                    text = f"--- {label} ---"
                    attr |= curses.A_BOLD
                elif kind == "choice":
                    value = data.get(key, profile_init_system(profile, path) if key == "INIT_SYSTEM" else "musl")
                    text = f"    ({value}) {label}"
                else:
                    cfgkey = f"CONFIG_{'PKG' if kind == 'pkg' else 'APPLET'}_{key}"
                    value = data.get(cfgkey, "n")
                    marker = "*" if value == "y" else " "
                    unavailable = kind == "pkg" and not recipe_ready(key)
                    suffix = " [unavailable]" if unavailable else ""
                    text = f"    [{marker}] {label}{suffix}"
                try:
                    stdscr.addnstr(screen_y, 2, text, width - 4, attr)
                except curses.error:
                    pass
            stdscr.addnstr(height - 2, 1, message, width - 2)
            stdscr.refresh()
            ch = stdscr.getch()
            if ch in (curses.KEY_UP, ord("k")):
                pos = (pos - 1) % len(selectable)
            elif ch in (curses.KEY_DOWN, ord("j")):
                pos = (pos + 1) % len(selectable)
            elif ch in (ord("q"), ord("Q"), 27):
                return 1
            elif ch in (ord("s"), ord("S")):
                return 0
            elif ch in (ord(" "), 10, 13):
                kind, key, label = rows[current]
                if kind == "choice" and key == "INIT_SYSTEM":
                    choices = ("runit", "sysvinit", "openrc")
                    old = data.get(key, "runit")
                    data[key] = choices[(choices.index(old) + 1) % len(choices)]
                elif kind == "choice" and key == "LIBC":
                    message = "glibc is blocked until Docker+QEMU verification; musl remains selected"
                    data[key] = "musl"
                elif kind in {"pkg", "applet"}:
                    if kind == "pkg" and not recipe_ready(key):
                        message = f"{label}: package recipe unavailable"
                        continue
                    cfgkey = f"CONFIG_{'PKG' if kind == 'pkg' else 'APPLET'}_{key}"
                    data[cfgkey] = "n" if data.get(cfgkey, "n") == "y" else "y"
                    if kind == "pkg" and data[cfgkey] == "y":
                        if key in ADMIN_EXTRAS:
                            apply_admin_exclusion(data, key)
                        for dep in AUTO_DEPS.get(key, ()):
                            data[f"CONFIG_PKG_{dep}"] = "y"

    if curses.wrapper(draw) != 0:
        print("  CONFIG    discarded")
        return 0
    write_cfg(path, data, profile)
    print(f"  CONFIG    wrote {path}")
    return cmd_validate(path, profile)


def cmd_menu(path: Path, profile: str) -> int:
    """Interactive toggle for extras; saves and validates."""
    data = ensure_defaults(parse_cfg(path), profile, path)

    # A real terminal gets the sectioned full-screen selector. Keep the line
    # menu below as a portability fallback for restricted consoles/CI shells.
    if sys.stdin.isatty() and sys.stdout.isatty() and os.environ.get("TERM", "") not in {"", "dumb"}:
        try:
            return _menuconfig(path, profile, data)
        except (ImportError, OSError):
            pass

    inp, out, closer = _open_menu_streams()
    if inp is None or out is None:
        print(
            "✗ isdconfig menu needs an interactive terminal "
            "(stdin/stdout TTY or /dev/tty).\n"
            "  From a real shell:\n"
            "    make isdconfig PROFILE=minimal\n"
            "  Non-interactive:\n"
            "    python3 scripts/isdconfig.py set CONFIG_PKG_NANO=y\n"
            "    python3 scripts/isdconfig.py set CONFIG_APPLET_TOP=y\n"
            "    python3 scripts/isdconfig.py show",
            file=sys.stderr,
        )
        return 1

    try:
        out.write("ISD test-distro software (toggle y/n)\n")
        out.write(f"Config: {path}\n")
        out.write(f"Profile: {profile}\n")
        if profile == "custom":
            current_init = profile_init_system(profile, path)
            out.write("Available init systems: runit, sysvinit, openrc\n")
            while True:
                out.write(f"Init system [{current_init}] ")
                out.flush()
                answer = inp.readline().strip().lower()
                if not answer:
                    answer = current_init
                if answer in SUPPORTED_INIT_SYSTEMS:
                    data["INIT_SYSTEM"] = answer
                    break
                out.write("  enter runit, sysvinit, or openrc\n")
            current_libc = parse_cfg(path).get("LIBC", "musl").strip() or "musl"
            out.write("Available libc: musl [ready], glibc [not packaged]\n")
            while True:
                out.write(f"C library [{current_libc}] ")
                out.flush()
                answer = inp.readline().strip().lower() or current_libc
                if answer == "musl":
                    data["LIBC"] = answer
                    break
                if answer == "glibc":
                    out.write("  glibc is blocked until its recipe passes Docker+QEMU\n")
                else:
                    out.write("  enter musl or glibc\n")
            out.write("Userland: BusyBox [ready], GNU coreutils [not packaged]\n")
        out.write(core_menu_label(profile, path) + "\n")
        out.write("Empty answer keeps the current value.\n\n")
        out.flush()

        out.write("--- packages ---\n")
        for short in EXTRAS:
            key = f"CONFIG_PKG_{short}"
            cur = data.get(key, EXTRA_DEFAULTS.get(short, "n"))
            note = ""
            if not recipe_ready(short):
                note = f"  (not packaged: packages/{pkg_dirname(short)}/ — cannot enable)"
                cur = "n"
            elif short in FUTURE_PACKAGES:
                note = f"  (packages/{FUTURE_PACKAGES[short]}/)"
            if short in AUTO_DEPS:
                note += f"  [deps: {', '.join(AUTO_DEPS[short])}]"
            out.write(f"  {key}{note}\n")
            out.flush()
            if not recipe_ready(short):
                out.write(f"  {short} [n] (skipped — not packaged)\n")
                out.flush()
                data[key] = "n"
                continue
            data[key] = _prompt_yn(inp, out, f"  {short}", cur)
            if data[key] == "y":
                msg = refuse_enable_pkg(short, profile)
                if msg:
                    out.write(f"    ✗ {msg}\n")
                    out.flush()
                    out.write("    configuration unchanged for this option\n")
                    out.flush()
                    data[key] = cur
            if data[key] == "y" and short in ADMIN_EXTRAS:
                apply_admin_exclusion(data, short)
            if data[key] == "y" and short in AUTO_DEPS:
                for dep in AUTO_DEPS[short]:
                    data[f"CONFIG_PKG_{dep}"] = "y"
                    out.write(f"    → auto-enabled CONFIG_PKG_{dep}=y\n")
                    out.flush()

        out.write("\n--- BusyBox applets ---\n")
        for short, applet in APPLETS.items():
            key = f"CONFIG_APPLET_{short}"
            cur = data.get(key, APPLET_DEFAULTS.get(short, "n"))
            out.write(f"  {key} → /bin/{applet}\n")
            out.flush()
            data[key] = _prompt_yn(inp, out, f"  {short}", cur)

        out.write("\n")
        out.flush()
        save = _prompt_yn(inp, out, "Save .isdconfig", "y")
        if save != "y":
            out.write("  (discarded)\n")
            out.flush()
            return 0
    finally:
        if closer is not None:
            closer.close()

    write_cfg(path, data, profile)
    print(f"  CONFIG    wrote {path}")
    rc = cmd_validate(path, profile)
    if rc == 0:
        print("")
        print("Next: rebuild the image so packages/applets apply:")
        print(f"  make isd-image PROFILE={profile}")
        print(f"  # or from IR0: make first-boot PROFILE={profile}")
        cmd_show(path, profile)
    return rc


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="ISD .isdconfig helper")
    ap.add_argument(
        "--config",
        default=None,
        help="config path (default: $ISD_CONFIG or .isdconfig.d/<profile>)",
    )
    ap.add_argument(
        "--profile",
        default=os.environ.get("PROFILE", "minimal"),
        help="profile name for validate messages",
    )
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_def = sub.add_parser("defconfig", help="write defaults if missing")
    p_def.add_argument(
        "--force", action="store_true", help="overwrite existing config"
    )

    sub.add_parser("show", help="print effective config")
    p_set = sub.add_parser("set", help="set CONFIG_PKG_* / CONFIG_APPLET_*=y|n")
    p_set.add_argument("assignments", nargs="+", help="KEY=VAL …")
    sub.add_parser("validate", help="validate config against recipes")
    p_plan = sub.add_parser("plan", help="print immutable build plan (does not build)")
    p_plan.add_argument(
        "--json", action="store_true", help="emit machine-readable plan"
    )
    sub.add_parser("menu", help="interactive extras menu (TTY)")

    args = ap.parse_args(argv)
    path = cfg_path(args.config, args.profile)

    try:
        if args.cmd == "defconfig":
            return cmd_defconfig(path, args.profile, args.force)
        if args.cmd == "show":
            return cmd_show(path, args.profile)
        if args.cmd == "set":
            return cmd_set(path, args.profile, args.assignments)
        if args.cmd == "validate":
            return cmd_validate(path, args.profile)
        if args.cmd == "plan":
            return cmd_plan(path, args.profile, args.json)
        if args.cmd == "menu":
            return cmd_menu(path, args.profile)
    except ConfigError as exc:
        print(f"✗ {exc}", file=sys.stderr)
        return 2
    ap.error(f"unknown command {args.cmd}")
    return 2


if __name__ == "__main__":
    sys.exit(main())
