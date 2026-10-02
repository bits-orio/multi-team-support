#!/usr/bin/env python3
"""Headless test runner for MTS behaviour tests.

Factorio's require() uses dotted module names that map to paths, which is
exactly stock Lua package.path behaviour, so the real modules load unchanged.
The Factorio runtime itself is mocked in tests/mock_factorio.lua.
"""
import sys, os
# Factorio embeds Lua 5.2. lupa's default runtime is newer and accepts
# constructs 5.2 rejects (\u{} escapes, // division, integer subtypes), which
# let a load-time failure pass every headless check once. Pin to 5.2.
from lupa.lua52 import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def main():
    passed, failed = 0, 0
    for suite in ("tests.test_reaper", "tests.test_teams_sort"):
        # Each suite gets an isolated engine mock and require cache.
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(f'package.path = "{ROOT}/?.lua;{ROOT}/?/init.lua;" .. package.path')
        try:
            report = lua.execute(f'return (require("{suite}"))')
        except Exception as exc:
            print("HARNESS ERROR:", suite, exc)
            return 2
        passed += int(report["passed"])
        failed += int(report["failed"])
        failures = report["failures"]
        for i in range(1, len(failures) + 1):
            print("  FAIL:", failures[i])
    print(f"\n{passed} passed, {failed} failed")
    return 0 if failed == 0 else 1

if __name__ == "__main__":
    sys.exit(main())
