#!/usr/bin/env bash
# Spike: LuaGuiElement.zoom_limits (camera) and LuaGuiElement.opacity
# (sprite, sprite-button). Question, results and the recorded lines are in
# FINDINGS.md beside this file.
#   usage: dev/spikes/gui-zoom-opacity/run.sh [api|wheel]   (default: api)
#
#   api    Headless, in the game's test mode (Factorio 2.1.24 and newer): the
#          API matrix, then the timing loops. Private config, write-data and
#          mod directory, as dev/run-tests.sh does it. The matrix lines are
#          compared with recorded-2.1.25.txt.
#   wheel  A graphical client on a private display at 1920x1080: turns the
#          mouse wheel over a camera element with zoom_limits and one
#          without, and logs both cameras' zoom and the player's zoom after
#          each step. Saves a screenshot of the frame. Needs xdotool, and
#          only one graphical client may run on a machine at a time.
#
#   FACTORIO=<path>    the binary (default: the one dev/run-tests.sh uses)
#   HARNESS_RUN=<dir>  where the run folder goes (default .run/spikes)
#
# Exit status: 0 the probe finished (api: and the lines match the recorded
# ones), 1 it did not finish, 2 api finished but the lines differ: the engine
# behaves differently. For wheel, read the STATE lines against
# wheel-2.1.25.txt.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../harness-lib.sh
. "$HERE/../../harness-lib.sh"
RUN="${HARNESS_RUN:-$REPO/.run/spikes}/gui-zoom-opacity"
MODE="${1:-api}"
echo "Factorio $ENGINE_FULL: $FACTORIO"

strip() { sed -E 's/^.*: GZO /GZO /'; }

run_api() {
  local status=0 arg log errors
  harness_engine_at_least 2.1.24 || { echo "Factorio $ENGINE_FULL has no test mode (needs 2.1.24 or newer)"; return 1; }
  rm -rf "$RUN/api"; mkdir -p "$RUN/api/mods"
  harness_config "$RUN/api"
  ln -s "$HERE" "$RUN/api/mods/gzo"
  cat > "$RUN/api/mods/mod-list.json" <<'EOF'
{ "mods": [
  { "name": "base", "enabled": true },
  { "name": "elevated-rails", "enabled": false },
  { "name": "quality", "enabled": false },
  { "name": "space-age", "enabled": false },
  { "name": "gzo", "enabled": true }
] }
EOF
  for arg in a t; do
    log="$RUN/api/$arg.log"
    "$FACTORIO" --config "$RUN/api/config.ini" --mod-directory "$RUN/api/mods" \
      --test-scenario base/freeplay --test-ticks 120 --test-arg "$arg" > "$log" 2>&1 \
      || { echo "[$arg] run failed"; status=1; }
    grep -h "GZO " "$log" | strip
    grep -q "GZO DONE" "$log" || { echo "[$arg] missing GZO DONE"; status=1; }
    errors=$(harness_errors "$log")
    [ -n "$errors" ] && { echo "$errors" | head -20 | sed "s/^/[$arg] ERROR: /"; status=1; }
  done
  [ $status -eq 0 ] || { echo "FAILED (logs: $RUN/api)"; return 1; }
  # The parse and version lines name the engine, so they are left out.
  grep -h "GZO " "$RUN/api/a.log" | strip | grep -v "^GZO PARSE \|^GZO version base=" > "$RUN/api/result.txt"
  if diff "$HERE/recorded-2.1.25.txt" "$RUN/api/result.txt" > "$RUN/api/diff.txt"; then
    echo "DONE: the matrix gives the same lines as recorded-2.1.25.txt"
  else
    echo "---- differs from recorded-2.1.25.txt (< recorded, > this run)"
    cat "$RUN/api/diff.txt"
    echo "DONE: the matrix differs from recorded-2.1.25.txt"; return 2
  fi
}

# dev/run-gui.sh and dev/gui-drive.sh treat the folder above dev/ as the mod
# under test. Here that mod is the probe, so the run folder gets a stand-in
# repo: the probe mod with a copy of this repo's harness in its dev/. The
# client, its display and everything they write stay inside it.
RIG="$RUN/rig"
drive() { "$RIG/dev/gui-drive.sh" "$@"; }

run_wheel() {
  local log="$RIG/.run/gui/userdata/factorio-current.log" x before after
  command -v xdotool > /dev/null || { echo "xdotool not found"; return 1; }
  [ -x "$RIG/dev/gui-drive.sh" ] && drive stop   # a client left over from an earlier run
  rm -rf "$RIG"; mkdir -p "$RIG/dev"
  cp "$HERE/info.json" "$HERE/control.lua" "$RIG/"
  cp "$DEV_DIR/harness-lib.sh" "$DEV_DIR/vdisplay.sh" "$DEV_DIR/run-gui.sh" "$DEV_DIR/gui-drive.sh" "$RIG/dev/"
  printf 'ABBR=GZO\nSETS=(base)\n' > "$RIG/dev/harness.conf"
  state() { # <label>; logs the zooms and prints them
    drive lua 'remote.call("gzo","state")'; sleep 1
    echo "STATE $1: $(grep 'GZO STATE' "$log" | tail -n 1 | sed -E 's/.*STATE //')"
  }
  trap 'drive stop' EXIT
  export FACTORIO
  GUI_SIZE=1920x1080 "$RIG/dev/run-gui.sh" base game || return 1
  DISPLAY="$(cat "$RIG/.run/gui/display")"; export DISPLAY

  drive lua 'remote.call("gzo","build")'; sleep 6
  # A fixed place for the frame: the cameras are then at about 110..410 and
  # 414..714 across, 140..440 down (interface scale 1).
  drive lua 'game.players[1].gui.screen.gzo_c.location={100,100} game.players[1].zoom=1'; sleep 2
  drive shot "$RUN/frame.png"
  state start | tee "$RUN/wheel.txt"
  before="$(grep -c 'GZO STATE' "$log")"
  for x in 260 560; do
    drive move "$x" 290; sleep 0.3; drive move $((x + 3)) 292; sleep 0.3
    echo "mouse: $(xdotool getmouselocation)" | tee -a "$RUN/wheel.txt"
    xdotool click --repeat 5 --delay 150 4; sleep 1; state "wheel-in x5 at $x,290" | tee -a "$RUN/wheel.txt"
    xdotool click --repeat 5 --delay 150 5; sleep 1; state "wheel-out x5 at $x,290" | tee -a "$RUN/wheel.txt"
  done
  drive lua 'remote.call("gzo","setzoom","lim",5)'; sleep 1; state "scripted lim zoom=5" | tee -a "$RUN/wheel.txt"
  drive move 260 290; sleep 0.3
  xdotool click --repeat 3 --delay 150 5; sleep 1; state "wheel-out x3 after scripted 5" | tee -a "$RUN/wheel.txt"
  after="$(grep -c 'GZO STATE' "$log")"

  # Six states were asked for after the first. The wheel must have reached
  # the game at all: the player's zoom moves on the first wheel-in.
  [ $((after - before)) -eq 6 ] || { echo "FAILED: $((after - before)) of 6 STATE lines logged (log: $log)"; return 1; }
  sed -n 3p "$RUN/wheel.txt" | grep -qv "player.zoom=1$" \
    || { echo "FAILED: the wheel did not reach the game (player.zoom still 1)"; return 1; }
  if grep "^STATE wheel-.* at " "$RUN/wheel.txt" | grep -qv "lim zoom=1 nolim zoom=1 " \
    || grep "after scripted 5" "$RUN/wheel.txt" | grep -qv "lim zoom=5 nolim zoom=1 "; then
    echo "DONE: a camera's zoom changed under the wheel. That differs from wheel-2.1.25.txt"
  else
    echo "DONE: the wheel left both cameras' zoom alone, as in wheel-2.1.25.txt (screenshot: $RUN/frame.png)"
  fi
}

mkdir -p "$RUN"
case "$MODE" in
  api) run_api ;;
  wheel) run_wheel ;;
  *) echo "unknown mode: $MODE (expected api or wheel)"; exit 1 ;;
esac
