#!/usr/bin/env bash
# Spike: what LuaPlanet.associate_surface does to a surface a script made.
# Question, results and the recorded lines are in FINDINGS.md beside this
# file. Headless. Needs Space Age and the game's test mode (Factorio 2.1.24
# and newer).
#
# Each case is one game run of scenarios/probe in test mode, with a private
# config, write-data and mod directory (only this probe mod and the DLC), as
# dev/run-tests.sh does it. Prints every case's "HP" lines, then compares
# them with recorded-2.1.25.txt when all cases ran.
#   usage: dev/spikes/heated-planet/run.sh [case ...]   (default: all five)
#     cases: aquilo vulcanus built-first planet-has-surface two-surfaces
#   FACTORIO=<path>    the binary (default: the one dev/run-tests.sh uses)
#   HARNESS_RUN=<dir>  where the run folder goes (default .run/spikes)
#
# Exit status: 0 every case finished and the lines match the recorded ones,
# 1 a case did not finish (failed run, engine or Lua error, no "HP DONE"),
# 2 every case finished but the lines differ: the engine behaves differently.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../harness-lib.sh
. "$HERE/../../harness-lib.sh"
RUN="${HARNESS_RUN:-$REPO/.run/spikes}/heated-planet"
RECORDED="$HERE/recorded-2.1.25.txt"
ALL=(aquilo vulcanus built-first planet-has-surface two-surfaces)
CASES=("$@"); [ ${#CASES[@]} -eq 0 ] && CASES=("${ALL[@]}")

harness_engine_at_least 2.1.24 || { echo "Factorio $ENGINE_FULL has no test mode (needs 2.1.24 or newer)"; exit 1; }
[ -d "$(dirname "$FACTORIO")/../../data/space-age" ] || { echo "this probe needs Space Age"; exit 1; }

rm -rf "$RUN"; mkdir -p "$RUN/mods"
harness_config "$RUN"
ln -s "$HERE" "$RUN/mods/hp-probe"
cat > "$RUN/mods/mod-list.json" <<'EOF'
{ "mods": [
  { "name": "base", "enabled": true },
  { "name": "elevated-rails", "enabled": true },
  { "name": "quality", "enabled": true },
  { "name": "space-age", "enabled": true },
  { "name": "hp-probe", "enabled": true }
] }
EOF

echo "Factorio $ENGINE_FULL: $FACTORIO"
status=0
: > "$RUN/result.txt"
for case in "${CASES[@]}"; do
  log="$RUN/$case.log"
  "$FACTORIO" --config "$RUN/config.ini" --mod-directory "$RUN/mods" \
    --test-scenario hp-probe/probe --test-ticks 600 --test-arg "$case" > "$log" 2>&1 \
    || { echo "[$case] run failed"; status=1; }
  { echo "== $case"; grep -h "HP " "$log" | sed -E 's/^.*: HP /HP /'; } | tee -a "$RUN/result.txt"
  grep -q "HP DONE" "$log" || { echo "[$case] missing HP DONE"; status=1; }
  errors=$(harness_errors "$log")
  [ -n "$errors" ] && { echo "$errors" | head -20 | sed "s/^/[$case] ERROR: /"; status=1; }
done

if [ $status -ne 0 ]; then echo "FAILED (logs: $RUN)"; exit 1; fi
if [ "${CASES[*]}" != "${ALL[*]}" ]; then echo "DONE (not every case ran: no comparison)"; exit 0; fi
if diff "$RECORDED" "$RUN/result.txt" > "$RUN/diff.txt"; then
  echo "DONE: same lines as recorded-2.1.25.txt"
else
  echo "---- differs from recorded-2.1.25.txt (< recorded, > this run)"
  cat "$RUN/diff.txt"
  echo "DONE: the result differs from recorded-2.1.25.txt"; exit 2
fi
