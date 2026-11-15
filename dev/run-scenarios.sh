#!/usr/bin/env bash
# MTS scenario tests in the real engine, with a real client. A headless server
# runs a fresh map with this mod and dev/mods/mts-scenario-test; one graphical
# client (private X display, dev/vdisplay.sh) joins, claims a team through the
# landing pen and types the admin commands (/mts-pause, /mts-resume) into its
# console through dev/gui-drive.sh. The test mod runs the script side
# (mts-v1 calls, builds, checks) from /mtst steps sent to the server console.
#
# Sessions:
#   main       scenarios 1, 2, 3 (hand, robot, script, revive) and 5    [base]
#   update     scenario 4: a team paused under MTS 4d58890, saved, loaded with
#              committed master as a mod update (staged copy, version bumped) [base]
#   dangoreus  scenario 6, with the dangOreus zip copied from ~/.factorio/mods [base]
#   platform   scenario 3 on a space platform the team owns              [space-age]
#   calibrate  join, screenshot, quit (to find the pen button)
#
#   usage: dev/run-scenarios.sh [main update dangoreus platform]   (default: all four)
#   HARNESS_PORT=<port>   server port (default MP_PORT in harness.conf)
#
# Exit status is non-zero on any MTS_TEST FAIL, a missing MTS_TEST DONE, a Lua
# or engine error, a desync or a failed step. Everything it started (client,
# server, display) is stopped on exit, also on failure. Logs and screenshots:
# .run/scen/<session>/.
set -uo pipefail
DEV="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=harness-lib.sh
. "$DEV/harness-lib.sh"
# shellcheck source=vdisplay.sh
. "$DEV/vdisplay.sh"
# shellcheck source=scenario-lib.sh
. "$DEV/scenario-lib.sh"
PORT="${HARNESS_PORT:-${MP_PORT:?set MP_PORT in dev/harness.conf}}"
TEST_MOD_DIR="$DEV/mods/mts-scenario-test"
OLD_MTS="4d58890"                                   # the release before pause holders
DANGOREUS_ZIP="${DANGOREUS_ZIP:-$HOME/.factorio/mods/dangOreus_2.0.6.zip}"
PEN_BUTTON=(185 139)                                # "Start a new team" at 1280x720, UI scale 1
WELCOME_CLOSE=(846 53)                              # the welcome window's close button
TEAM=""
trap scen_cleanup EXIT
trap 'exit 130' INT TERM

session() { # <name> <set>
  RUN="$REPO/.run/scen/$1"; SET="$2"; SCEN_MODS="$RUN/mods"; CLIENT_N=0
  rm -rf "$RUN"; mkdir -p "$RUN/server" "$RUN/shots"
  echo "== $1 ($2)"
}

# Stage this mod, the test mod and any extra folders, then make the map.
stage_and_create() { # [extra mod folders...]
  harness_stage "$RUN" "$SET" "$TEST_MOD_DIR" "$@" || return 1
  scen_create "$RUN/world.zip"
}

# Replace the staged MTS with the committed tree at <rev>, optionally with a
# different version in its info.json (the staged copy only).
stage_mts_rev() { # <rev> [version]
  rm -rf "${SCEN_MODS:?}/$MOD"; mkdir -p "$SCEN_MODS/$MOD"
  git -C "$REPO" archive "$1" | tar -x -C "$SCEN_MODS/$MOD" || return 1
  [ -n "${2:-}" ] && sed -i -E "s/(\"version\": *\")[^\"]+\"/\1$2\"/" "$SCEN_MODS/$MOD/info.json"
  echo "  staged $MOD from $1 (version $(harness_json "$SCEN_MODS/$MOD/info.json" version))"
}

# Click the landing pen's "Start a new team" and wait for the test mod's
# fixtures on the new team's surface; sets TEAM.
claim_team() {
  local attempt line
  "$DEV/gui-drive.sh" click "${WELCOME_CLOSE[@]}"; sleep 0.5   # the first join opens the welcome window
  for attempt in 1 2 3; do
    scen_mark
    "$DEV/gui-drive.sh" click "${PEN_BUTTON[@]}"
    if scen_wait "MTS_TEST STEP fixtures: " 20; then
      line=$(scen_line "MTS_TEST STEP fixtures: ")
      TEAM=$(sed -nE 's/.*team=(team-[0-9]+).*/\1/p' <<< "$line")
      echo "  claimed $TEAM through the pen (${line##*fixtures: })"
      [ -n "$TEAM" ] && return 0
    fi
    scen_shot "claim-attempt-$attempt"
  done
  return 1
}

hand_build() { # left-click four tiles right of the player (zoom 1: 32 px a tile)
  local attempt
  for attempt in 1 2; do
    scen_mark
    "$DEV/gui-drive.sh" click 768 360
    scen_wait "MTS_TEST STEP built-hand" 6 && return 0
    scen_shot "hand-build-attempt-$attempt"
  done
  return 1
}

run_calibrate() {
  session calibrate base
  stage_and_create || return 1
  scen_server_start "$RUN/world.zip" || return 1
  scen_client_setup; scen_client_start || return 1
  sleep 3; scen_shot pen
  scen_cmd "/mtst done"; sleep 1
  scen_client_stop; scen_server_stop
}

run_main() {
  session main base
  stage_and_create || return 1
  scen_server_start "$RUN/world.zip" || return 1
  scen_client_setup; scen_client_start || return 1
  claim_team || return 1
  # 1: typed /mts-resume on a team that is not paused, then /mts-pause, /mts-resume
  scen_step "/mtst s1-notpaused" s1-notpaused || return 1
  scen_type "/mts-resume $TEAM" || return 1
  scen_step "/mtst s1-notpaused-check" s1-notpaused-check || return 1
  scen_type "/mts-pause $TEAM" || return 1
  scen_step "/mtst s1-paused-check" s1-paused-check || return 1
  scen_type "/mts-resume $TEAM" || return 1
  scen_step "/mtst s1-resumed-check" s1-resumed-check || return 1
  # 2: holders
  scen_step "/mtst s2a-script-pause" s2a-script-pause || return 1
  scen_type "/mts-pause $TEAM" || return 1
  scen_step "/mtst s2a-script-release" s2a-script-release || return 1
  scen_type "/mts-resume $TEAM" || return 1
  scen_step "/mtst s2a-check" s2a-check || return 1
  scen_step "/mtst mark" mark || return 1
  scen_type "/mts-pause $TEAM" || return 1
  scen_step "/mtst s2b-script-release" s2b-script-release || return 1
  scen_type "/mts-resume $TEAM" || return 1
  scen_step "/mtst s2b-check" s2b-check || return 1
  scen_step "/mtst s2c-holders" s2c-holders || return 1
  # 3: built while paused: by hand, by a robot, by script, revived; plus a
  # surface registered to the paused team
  scen_type "/mts-pause $TEAM" || return 1
  scen_step "/mtst s3-arm-hand" s3-arm-hand || return 1
  sleep 1; hand_build || echo "  the hand build never happened"
  scen_step "/mtst s3-robot" s3-robot-armed || return 1
  scen_mark; scen_wait "MTS_TEST STEP built-robot" 45
  scen_step "/mtst s3-script" s3-script || return 1
  scen_step "/mtst x-register-paused" x-register-paused || return 1
  scen_step "/mtst s3-paused-check" s3-paused-check || return 1
  scen_type "/mts-resume $TEAM" || return 1
  scen_step "/mtst s3-resumed-check" s3-resumed-check || return 1
  # Observation only: a source disabled by another script before a pause
  scen_step "/mtst obs-predisabled" obs-predisabled || return 1
  scen_type "/mts-pause $TEAM" || return 1
  scen_type "/mts-resume $TEAM" || return 1
  scen_step "/mtst obs-predisabled-check" obs-predisabled-check || return 1
  # 5: quiet disband, then a plain one as the control; chat by screenshot
  scen_console_shot s5-before-quiet
  scen_step "/mtst s5-quiet" s5-quiet-checked || return 1
  scen_shot s5-quiet-chat; scen_console_shot s5-quiet-console
  sleep 2; claim_team || return 1
  scen_step "/mtst s5-plain" s5-plain-checked || return 1
  scen_shot s5-plain-chat; scen_console_shot s5-plain-console
  scen_mark; scen_cmd "/mtst done"; scen_wait "MTS_TEST DONE" 10
  scen_client_stop; scen_server_stop
}

run_update() {
  session update base
  harness_stage "$RUN" "$SET" "$TEST_MOD_DIR" || return 1
  stage_mts_rev "$OLD_MTS" || return 1
  scen_create "$RUN/world.zip" || return 1
  scen_server_start "$RUN/world.zip" || return 1
  scen_client_setup; scen_client_start || return 1
  claim_team || return 1
  scen_step "/mtst s4-pause" s4-pause || return 1
  scen_client_stop
  scen_server_stop
  grep -q "Saving map as $RUN/world.zip" "$RUN/server.log" || { echo "  the server did not save on SIGTERM"; return 1; }
  # The mod update: committed master, as a release would ship it (one version up).
  local v; v=$(git -C "$REPO" show master:info.json | python3 -c 'import json,sys; v=json.load(sys.stdin)["version"].split("."); v[-1]=str(int(v[-1])+1); print(".".join(v))')
  stage_mts_rev master "$v" || return 1
  "$FACTORIO" --config "$RUN/server/config.ini" --benchmark "$RUN/world.zip" --benchmark-ticks 300 \
    --mod-directory "$SCEN_MODS" > "$RUN/bench.log" 2>&1 || { echo "  --benchmark failed"; tail -20 "$RUN/bench.log"; return 1; }
}

run_dangoreus() {
  session dangoreus base
  [ -f "$DANGOREUS_ZIP" ] || { echo "  no dangOreus zip at $DANGOREUS_ZIP: skipped"; SKIPPED+=(dangoreus); return 0; }
  harness_stage "$RUN" "$SET" "$TEST_MOD_DIR" || return 1
  cp "$DANGOREUS_ZIP" "$SCEN_MODS/"
  python3 - "$SCEN_MODS/mod-list.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["mods"].append({"name": "dangOreus", "enabled": True})
json.dump(d, open(sys.argv[1], "w"), indent=1)
PY
  scen_create "$RUN/world.zip" || return 1
  scen_server_start "$RUN/world.zip" || return 1
  scen_client_setup; scen_client_start || return 1
  claim_team || return 1
  scen_step "/mtst s6-dangoreus" s6-dangoreus 60 || return 1
  scen_step "/mtst mark" mark || return 1
  scen_type "/mts-pause $TEAM" || return 1
  scen_step "/mtst s1-paused-check" s1-paused-check || return 1
  scen_step "/mtst s3-arm-hand" s3-arm-hand || return 1
  sleep 1; hand_build || echo "  the hand build never happened"
  scen_step "/mtst s3-script" s3-script || return 1
  scen_type "/mts-resume $TEAM" || return 1
  scen_step "/mtst s3-resumed-check" s3-resumed-check || return 1
  scen_mark; scen_cmd "/mtst done"; scen_wait "MTS_TEST DONE" 10
  scen_client_stop; scen_server_stop
}

run_platform() {
  session platform space-age
  stage_and_create || return 1
  scen_server_start "$RUN/world.zip" || return 1
  scen_client_setup; scen_client_start || return 1
  claim_team || return 1
  scen_step "/mtst s3-platform-setup" s3-platform-ready || return 1
  scen_step "/mtst mark" mark || return 1
  scen_type "/mts-pause $TEAM" || return 1
  scen_step "/mtst s1-paused-check" s1-paused-check || return 1
  scen_step "/mtst s3-platform-build" s3-platform-build || return 1
  scen_mark; scen_wait "MTS_TEST STEP built-platform" 45
  scen_step "/mtst s3-script" s3-script || return 1
  scen_type "/mts-resume $TEAM" || return 1
  scen_step "/mtst s3-resumed-check" s3-resumed-check || return 1
  scen_mark; scen_cmd "/mtst done"; scen_wait "MTS_TEST DONE" 10
  scen_client_stop; scen_server_stop
}

WANT=("$@"); [ ${#WANT[@]} -eq 0 ] && WANT=(main update dangoreus platform)
SKIPPED=()
scen_preflight || exit 1
echo "Factorio $ENGINE_VERSION: $FACTORIO"
overall=0
for s in "${WANT[@]}"; do
  case "$s" in
    calibrate|main|update|dangoreus|platform) ;;
    *) echo "unknown session: $s"; overall=1; continue ;;
  esac
  "run_$s" || { echo "  [$s] a step failed"; overall=1; }
  scen_cleanup
  [[ " ${SKIPPED[*]} " == *" $s "* ]] && continue
  [ "$s" = calibrate ] || scen_evaluate "$s" || overall=1
done
[ ${#SKIPPED[@]} -gt 0 ] && echo "skipped: ${SKIPPED[*]}"
if [ $overall -eq 0 ]; then echo "ALL PASS"; else echo "FAILED"; fi
exit $overall
