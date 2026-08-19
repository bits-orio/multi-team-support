#!/usr/bin/env python3
"""Cross-check mts-* locale keys between Lua sources and locale/en/*.cfg.

Fails (exit 1) on:
  - a {"mts-<section>.<key>"} reference in Lua with no definition in locale/en
  - the same section.key defined twice across locale/en cfg files
    (the engine keeps only one — silent shadowing)
Warns (exit 0) on:
  - defined keys never referenced from Lua (they may be composed dynamically;
    mark deliberate ones with a trailing comment line "# checker:dynamic"
    directly above the key)

Only sections whose name starts with "mts-" are checked: prototype sections
([entity-name], [mod-setting-name], ...) are resolved by the engine from
prototype names, not from literal references in our Lua.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REF_RE = re.compile(r'\{\s*"(mts-[a-z0-9-]+\.[a-z0-9_-]+)"')
SECTION_RE = re.compile(r"^\[([^\]]+)\]\s*$")


def lua_files():
    for p in ROOT.rglob("*.lua"):
        if ".claude" not in p.parts:
            yield p


def collect_refs():
    refs = {}  # key -> first "file:line" seen
    for p in lua_files():
        for i, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
            if line.lstrip().startswith("--"):
                continue  # doc comments show example keys; not real references
            for m in REF_RE.finditer(line):
                refs.setdefault(m.group(1), f"{p.relative_to(ROOT)}:{i}")
    return refs


def collect_defs():
    defs = {}  # key -> [locations]
    dynamic = set()
    for p in sorted((ROOT / "locale" / "en").glob("*.cfg")):
        section = None
        pending_dynamic = False
        for i, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
            stripped = line.strip()
            m = SECTION_RE.match(stripped)
            if m:
                section = m.group(1)
                pending_dynamic = False
                continue
            if stripped.startswith("#") or stripped.startswith(";"):
                if "checker:dynamic" in stripped:
                    pending_dynamic = True
                continue
            if "=" in line and section and section.startswith("mts-"):
                key = f"{section}.{line.split('=', 1)[0].strip()}"
                defs.setdefault(key, []).append(f"{p.name}:{i}")
                if pending_dynamic:
                    dynamic.add(key)
            if stripped:
                pending_dynamic = False
    return defs, dynamic


def main():
    refs = collect_refs()
    defs, dynamic = collect_defs()
    errors, warnings = [], []

    for key, loc in sorted(refs.items()):
        if key not in defs:
            errors.append(f"missing definition: {key} (referenced at {loc})")
    for key, locs in sorted(defs.items()):
        if len(locs) > 1:
            errors.append(f"duplicate definition: {key} ({', '.join(locs)})")
        if key not in refs and key not in dynamic:
            warnings.append(f"unreferenced key: {key} ({locs[0]})")

    for w in warnings:
        print(f"warning: {w}")
    for e in errors:
        print(f"ERROR: {e}")
    print(
        f"check_locale: {len(refs)} referenced, {len(defs)} defined, "
        f"{len(errors)} errors, {len(warnings)} warnings"
    )
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
