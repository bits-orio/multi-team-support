#!/usr/bin/env python3
"""Detect require() cycles. This codebase breaks several deliberately with
parse-time injection, so the useful signal is whether any NEW module sits on a
cycle."""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIP = {".git", ".claude", "tests", "tools", "docs"}
REQ = re.compile(r'require\(\s*"([\w.]+)"\s*\)')

def module_name(path):
    rel = os.path.relpath(path, ROOT)[:-4]
    return rel.replace(os.sep, ".")

def build():
    graph = {}
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP]
        for name in filenames:
            if name.endswith(".lua"):
                path = os.path.join(dirpath, name)
                graph[module_name(path)] = set(REQ.findall(open(path).read()))
    return graph

def cycles(graph):
    found, state, stack = [], {}, []
    def walk(node):
        state[node] = 1
        stack.append(node)
        for dep in sorted(graph.get(node, ())):
            if dep not in graph:
                continue
            if state.get(dep) == 1:
                found.append(stack[stack.index(dep):] + [dep])
            elif state.get(dep) is None:
                walk(dep)
        stack.pop()
        state[node] = 2
    for node in sorted(graph):
        if state.get(node) is None:
            walk(node)
    return found

NEW = ("scripts.reaper", "gui.cleanup", "scripts.team_teardown",
       "scripts.agent_tools", "scripts.player_team_history",
       "scripts.team_incarnation", "milestones.external_keys")

def main():
    sys.setrecursionlimit(10000)
    graph = build()
    found = cycles(graph)
    mine = [c for c in found if any(n.startswith(NEW) for n in c)]
    for c in found:
        tag = "NEW" if c in mine else "pre-existing"
        print(f"  [{tag}] " + " -> ".join(c))
    print(f"\n{len(graph)} modules, {len(found)} cycle(s), {len(mine)} involving new code")
    return 1 if mine else 0

if __name__ == "__main__":
    sys.exit(main())
