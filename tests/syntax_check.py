#!/usr/bin/env python3
"""Parse every Lua file in the mod. Catches syntax errors Factorio would only
report at load time."""
import os, sys
# Factorio embeds Lua 5.2. lupa's default runtime is newer and accepts
# constructs 5.2 rejects (\u{} escapes, // division, integer subtypes), which
# let a load-time failure pass every headless check once. Pin to 5.2.
from lupa.lua52 import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIP = {".git", ".claude", ".run", "tests"}

def main():
    lua = LuaRuntime()
    version = lua.eval("_VERSION")
    if version != "Lua 5.2":
        print(f"REFUSING: harness is running {version}, Factorio runs Lua 5.2")
        return 2
    print(f"checking under {version}")
    check = lua.eval('function(p) local f, e = loadfile(p); if f then return "" end return tostring(e) end')
    bad, count = [], 0
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP]
        for name in sorted(filenames):
            if not name.endswith(".lua"):
                continue
            path = os.path.join(dirpath, name)
            count += 1
            err = check(path)
            if err:
                bad.append((os.path.relpath(path, ROOT), err))
    for path, err in bad:
        print(f"  SYNTAX: {path}\n          {err}")
    print(f"\n{count - len(bad)}/{count} Lua files parse")
    return 1 if bad else 0

if __name__ == "__main__":
    sys.exit(main())
