#!/usr/bin/env bash
# Headless test suite; settings in dev/harness.conf. The PRE_TESTS commands
# run first. Then, for each mod set, this mod, its DEPS and the test mod (if
# the repo has one) are staged in a private mod folder, a fresh save is
# created (on_init runs), and --benchmark advances it (on_load, then TICKS
# ticks).
#
# Exit status is non-zero on a failed PRE_TESTS command, a failed Factorio
# run, any engine or Lua error in the logs, any <ABBR>_TEST FAIL line, or a
# test mod that never printed <ABBR>_TEST DONE.
#   usage: dev/run-tests.sh [base|space-age ...]   (default: SETS in harness.conf)
#   HARNESS_TICKS=<n>  benchmark length (default: TICKS in harness.conf)
#   HARNESS_RUN=<dir>  where runs live (default .run/tests), so parallel runs do not collide
#   FACTORIO=<path>    the binary (default: the install matching info.json's factorio_version)
set -uo pipefail
# shellcheck source=harness-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/harness-lib.sh"
RUN_DIR="${HARNESS_RUN:-$REPO/.run/tests}"
TICKS="${HARNESS_TICKS:-$TICKS}"
WANT=("$@"); [ ${#WANT[@]} -eq 0 ] && WANT=("${SETS[@]}")
TAG="${ABBR}_TEST"

run_pre_tests() {
  local cmd status=0
  for cmd in "${PRE_TESTS[@]}"; do
    if (cd "$REPO" && bash -c "$cmd") > "$RUN_DIR/pre.log" 2>&1; then
      echo "[pre] ok: $cmd"
    else
      echo "[pre] FAILED: $cmd"; tail -n 20 "$RUN_DIR/pre.log" | sed "s/^/  [pre] /"; status=1
    fi
  done
  return $status
}

launch() { # <set name> <set dir>; runs --create then --benchmark
  local name="$1" dir="$2" save="$2/test.zip" cfg="$2/config.ini"
  rm -f "$save" "$dir/create.log" "$dir/bench.log"
  touch "$dir/bench.log"
  "$FACTORIO" --config "$cfg" --create "$save" --mod-directory "$dir/mods" --map-gen-seed 1 \
    > "$dir/create.log" 2>&1 || { echo "[$name] --create failed"; return 1; }
  "$FACTORIO" --config "$cfg" --benchmark "$save" --benchmark-ticks "$TICKS" --mod-directory "$dir/mods" \
    > "$dir/bench.log" 2>&1 || { echo "[$name] --benchmark failed"; return 1; }
}

evaluate() { # <set name> <set dir> <launch status>; prints a summary
  local name="$1" dir="$2" status="$3" logs=("$2/create.log" "$2/bench.log") pass=0 fail=0 errors
  if [ -n "$TEST_MOD" ]; then
    grep -h "$TAG " "${logs[@]}" | sed -E "s/^.*$TAG /$TAG /" > "$dir/results.txt"
    pass=$(grep -c "^$TAG PASS" "$dir/results.txt")
    fail=$(grep -c "^$TAG FAIL" "$dir/results.txt")
    grep "^$TAG FAIL" "$dir/results.txt" | sed "s/^/  [$name] /"
    [ "$fail" -gt 0 ] && status=1
    grep -q "^$TAG DONE" "$dir/results.txt" || { echo "  [$name] missing $TAG DONE"; status=1; }
  fi
  errors=$(harness_errors "${logs[@]}")
  [ -n "$errors" ] && { echo "$errors" | head -20 | sed "s/^/  [$name] ERROR: /"; status=1; }
  if [ -n "$TEST_MOD" ]; then echo "[$name] pass=$pass fail=$fail   (logs: $dir)"
  else echo "[$name] loaded, ran $TICKS ticks: $([ "$status" -eq 0 ] && echo ok || echo FAILED)   (logs: $dir)"; fi
  if [ "$status" -ne 0 ] && [ "$fail" -eq 0 ]; then tail -n 15 "${logs[@]}" | sed "s/^/  [$name] /"; fi
  return "$status"
}

run_set() { # <set name>
  local dir="$RUN_DIR/$1" status=0
  mkdir -p "$dir"
  harness_config "$dir"
  harness_stage "$dir" "$1" ${TEST_MOD:+"$DEV_DIR/mods/$TEST_MOD"} || return 1
  launch "$1" "$dir" || status=1
  evaluate "$1" "$dir" "$status"
}

mkdir -p "$RUN_DIR"
overall=0
run_pre_tests || overall=1
echo "Factorio $ENGINE_VERSION: $FACTORIO"
for set in "${WANT[@]}"; do
  case "$set" in
    base|space-age) run_set "$set" || overall=1 ;;
    *) echo "unknown set: $set (expected base or space-age)"; overall=1 ;;
  esac
done
if [ $overall -eq 0 ]; then echo "ALL PASS"; else echo "FAILED"; fi
exit $overall
