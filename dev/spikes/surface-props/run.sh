#!/usr/bin/env bash
# Spike: a planet's surface properties and pollutant copied onto a surface
# that is not tied to the planet. What follows the copy, what does not, and
# what a later associate_surface does to written values. Question, results
# and the recorded lines are in FINDINGS.md beside this file. Headless.
# Needs Space Age.
#
# Each case is its own save: --create (the case's setup runs in on_init),
# then the save is run in the game's test mode (Factorio 2.1.24 and newer; a
# connected player exists, which the fx cases need). Older engines run
# --benchmark instead, without a player. Every case has a private config,
# write-data and mod directory (a copy of the probe mod with its case.lua,
# and the DLC), as dev/run-tests.sh does it.
#   usage: dev/spikes/surface-props/run.sh [case ...]   (default: all nine)
#     cases: props tie misc day robots fx-vulcanus fx-gleba fx-fulgora fx-aquilo
#   FACTORIO=<path>    the binary (default: the one dev/run-tests.sh uses)
#   HARNESS_RUN=<dir>  where the run folder goes (default .run/spikes)
#
# Prints every case's "SP" lines and, when all cases ran, compares them with
# recorded-2.1.25.txt. Left out of the comparison: what lightning does on
# Fulgora's own surface, which is chance.
# Exit status: 0 every case finished and the lines match the recorded ones,
# 1 a case did not finish (failed run, engine or Lua error, no "SP DONE"),
# 2 every case finished but the lines differ: the engine behaves differently.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../harness-lib.sh
. "$HERE/../../harness-lib.sh"
RUN="${HARNESS_RUN:-$REPO/.run/spikes}/surface-props"
RECORDED="$HERE/recorded-2.1.25.txt"
TICKS=1600   # the longest case (robots) ends at tick 1500
ALL=(props tie misc day robots fx-vulcanus fx-gleba fx-fulgora fx-aquilo)
CASES=("$@"); [ ${#CASES[@]} -eq 0 ] && CASES=("${ALL[@]}")

[ -d "$(dirname "$FACTORIO")/../../data/space-age" ] || { echo "this probe needs Space Age"; exit 1; }

# A surface's day shape and flags never differed from a new surface's in the
# recorded runs. While they read exactly so they are shortened, to keep the
# lines readable; any other value prints in full and shows up in the diff.
DEFAULTS="dusk=0.25 dawn=0.75 evening=0.45 morning=0.55 min_brightness=0.15 show_clouds=true always_day=false freeze_daytime=false ignore_surface_conditions=false has_global_electric_network=false peaceful_mode=false no_enemies_mode=false"
lines() { # <log files...>: the SP lines, without timestamps and source positions
  grep -h "SP " "$@" | sed -E 's/^.*: SP /SP /' | sed "s/$DEFAULTS/(day shape and flags as on a new surface)/"
}
# What is left out of the comparison (see the header).
steady() { grep -v "^SP real lightning entity-ticks\|^SP real execute_lightning ok=true" "$1"; }

run_case() { # <case>
  local case="$1" dir="$RUN/$1" mode errors
  rm -rf "$dir"; mkdir -p "$dir/mods/sp-probe"
  harness_config "$dir"
  cp "$HERE/info.json" "$HERE/control.lua" "$dir/mods/sp-probe/"
  printf 'return "%s"\n' "$case" > "$dir/mods/sp-probe/case.lua"
  cat > "$dir/mods/mod-list.json" <<'EOF'
{ "mods": [
  { "name": "base", "enabled": true },
  { "name": "elevated-rails", "enabled": true },
  { "name": "quality", "enabled": true },
  { "name": "space-age", "enabled": true },
  { "name": "sp-probe", "enabled": true }
] }
EOF
  touch "$dir/run.log"
  if "$FACTORIO" --config "$dir/config.ini" --mod-directory "$dir/mods" --create "$dir/save.zip" \
      --map-gen-seed 1 > "$dir/create.log" 2>&1; then
    if harness_engine_at_least 2.1.24; then mode=(--test-save "$dir/save.zip" --test-ticks "$TICKS")
    else mode=(--benchmark "$dir/save.zip" --benchmark-ticks "$TICKS" --benchmark-runs 1); fi
    "$FACTORIO" --config "$dir/config.ini" --mod-directory "$dir/mods" "${mode[@]}" > "$dir/run.log" 2>&1 \
      || { echo "[$case] ${mode[0]} failed"; status=1; }
  else
    echo "[$case] --create failed"; status=1
  fi
  { echo "== $case"; lines "$dir/create.log" "$dir/run.log"; } | tee -a "$RUN/result.txt"
  grep -q "SP DONE$" "$dir/run.log" || { echo "[$case] missing SP DONE"; status=1; }
  grep -q "SP INIT ERROR\|SP TICK ERROR\|SP set_property(.*) FAILED" "$dir/create.log" "$dir/run.log" \
    && { echo "[$case] the probe logged an error"; status=1; }
  errors=$(grep -h -v "SP " "$dir/create.log" "$dir/run.log" | grep -E "Error|error while|stack traceback|Failed to load mods" || true)
  [ -n "$errors" ] && { echo "$errors" | head -20 | sed "s/^/[$case] ERROR: /"; status=1; }
}

mkdir -p "$RUN"
: > "$RUN/result.txt"
echo "Factorio $ENGINE_FULL: $FACTORIO"
status=0
for case in "${CASES[@]}"; do run_case "$case"; done

if [ $status -ne 0 ]; then echo "FAILED (logs: $RUN)"; exit 1; fi
if [ "${CASES[*]}" != "${ALL[*]}" ]; then echo "DONE (not every case ran: no comparison)"; exit 0; fi
if diff <(steady "$RECORDED") <(steady "$RUN/result.txt") > "$RUN/diff.txt"; then
  echo "DONE: same lines as recorded-2.1.25.txt"
else
  echo "---- differs from recorded-2.1.25.txt (< recorded, > this run)"
  cat "$RUN/diff.txt"
  echo "DONE: the result differs from recorded-2.1.25.txt"; exit 2
fi
