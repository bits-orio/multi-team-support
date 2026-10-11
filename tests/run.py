#!/usr/bin/env python3
"""Headless test runner for MTS.

Factorio's require() uses dotted module names that map to paths, which is
exactly stock Lua package.path behaviour, so the real modules load unchanged.
The Factorio runtime itself is mocked in tests/mock_factorio.lua.

Each test file runs in its own fresh Lua state, so the globals and module
stubs one file installs can never leak into the next. Exit status: 0 when
every check passes, 1 when any fails, 2 when a file cannot run at all.
"""
import sys, os
# Factorio embeds Lua 5.2. lupa's default runtime is newer and accepts
# constructs 5.2 rejects (\u{} escapes, // division, integer subtypes), which
# let a load-time failure pass every headless check once. Pin to 5.2.
from lupa.lua52 import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

TESTS = ("tests.test_reaper", "tests.test_agent_records", "tests.test_agent_manifest",
         "tests.test_agent_bytes", "tests.test_player_teams", "tests.test_chat_scope",
         "tests.test_team_release")

def run_one(module):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(f'package.path = "{ROOT}/?.lua;{ROOT}/?/init.lua;" .. package.path')
    report = lua.execute(f'return (require("{module}"))')
    failures = report["failures"]
    lines = [failures[i] for i in range(1, len(failures) + 1)]
    return int(report["passed"]), int(report["failed"]), lines

def main():
    passed = failed = 0
    broken = False
    for module in TESTS:
        try:
            p, f, lines = run_one(module)
        except Exception as exc:
            print(f"HARNESS ERROR in {module}:", exc)
            broken = True
            continue
        for line in lines:
            print(f"  FAIL [{module}]:", line)
        print(f"{module}: {p} passed, {f} failed")
        passed, failed = passed + p, failed + f
    print(f"\n{passed} passed, {failed} failed")
    if broken:
        return 2
    return 0 if failed == 0 else 1

if __name__ == "__main__":
    sys.exit(main())
