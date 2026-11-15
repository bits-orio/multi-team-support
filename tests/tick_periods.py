#!/usr/bin/env python3
"""Every script.on_nth_tick period in the mod must be unique.

Factorio keeps exactly ONE handler per period per mod, so two modules
registering the same period means whichever registers last silently replaces
the other. This shipped once: the reaper's disband drain took period 15, which
gui/platform_hub.lua already held, and the drain would never have run in-game.
No headless behaviour test can catch that, because neither handler is wrong on
its own.
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIP = {".git", ".claude", ".run", "tests", "tools", "docs"}
CALL = re.compile(r'script\.on_nth_tick\(\s*([A-Za-z_][\w.]*|\d+)')
REQUIRE = re.compile(r'local\s+(\w+)\s*=\s*require\("([\w.]+)"\)')
ARITH = re.compile(r'^[\d\s*+/()-]+$')

SYMBOL = re.compile(r'(?:local\s+(\w+)|^\s*\w+\.(\w+))\s*=\s*([^\n]+)', re.M)

def symbols(text):
    """Every `local X = expr` and `M.X = expr` in the file, by bare name."""
    table = {}
    for local_name, field_name, expr in SYMBOL.findall(text):
        name = local_name or field_name
        table.setdefault(name, expr.split('--')[0].strip())
    return table

def const_in(text, name, depth=4):
    """Resolve a constant, substituting other same-file constants it references
    (HEARTBEAT_TICKS = TICKS_PER_HOUR = 60 * 60 * 60)."""
    table = symbols(text)
    expr = table.get(name)
    if expr is None:
        return None
    for _ in range(depth):
        if ARITH.match(expr):
            return int(eval(expr))
        # Strip module qualifiers (M.FOO -> FOO), then substitute known names.
        expr = re.sub(r'\b\w+\.(\w+)\b', r'\1', expr)
        substituted = re.sub(r'\b([A-Za-z_]\w*)\b',
                             lambda m: table.get(m.group(1), m.group(1)), expr)
        if substituted == expr:
            break
        expr = re.sub(r'\b\w+\.(\w+)\b', r'\1', substituted)
    return int(eval(expr)) if ARITH.match(expr) else None

def resolve(arg, text, path):
    if arg.isdigit():
        return int(arg)
    if '.' in arg:                                  # alias.CONST from another module
        alias, const = arg.split('.', 1)
        for a, mod in REQUIRE.findall(text):
            if a == alias:
                target = os.path.join(ROOT, mod.replace('.', os.sep) + '.lua')
                if os.path.exists(target):
                    return const_in(open(target).read(), const)
        return None
    return const_in(text, arg)

def main():
    periods, unresolved = {}, []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP]
        for name in sorted(filenames):
            if not name.endswith('.lua'):
                continue
            path = os.path.join(dirpath, name)
            text = open(path).read()
            for arg in CALL.findall(text):
                rel = os.path.relpath(path, ROOT)
                value = resolve(arg, text, path)
                if value is None:
                    unresolved.append((rel, arg))
                    continue
                periods.setdefault(value, []).append(f"{rel} ({arg})")

    clashes = {p: w for p, w in periods.items() if len(w) > 1}
    for period, where in sorted(clashes.items()):
        print(f"  COLLISION on_nth_tick({period}):")
        for w in where:
            print(f"      {w}")
    for rel, arg in unresolved:
        print(f"  UNRESOLVED period {arg!r} in {rel} - extend this checker")

    print(f"\n{len(periods)} distinct periods, {len(clashes)} collision(s), "
          f"{len(unresolved)} unresolved")
    if periods and not clashes and not unresolved:
        print("periods: " + ", ".join(str(p) for p in sorted(periods)))
    return 1 if (clashes or unresolved) else 0

if __name__ == '__main__':
    sys.exit(main())
