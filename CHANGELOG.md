# Changelog

## 0.3.7

- Fix trigger-technology progress (e.g. "craft 50 iron plates toward
  steam-power") surviving team-slot release. Team forces are pre-created
  as "team-1"…"team-N" and the same LuaForce object is reused across
  occupants, so per-force engine state — including trigger-tech counters
  and tech modifiers — persists unless explicitly cleared. The previous
  `tech.researched = false` loop only flipped completion flags; a new
  occupant who crafted one more plate completed the trigger with the
  prior team's 49 + 1. `reset_force_state` now calls `LuaForce.reset()`
  (clears researched flags, trigger counters, modifiers, research queue)
  and re-applies baseline cease-fire plus spectator-force integration
  that `reset()` wipes.
- Fix team-slot recycling leaking per-force storage state. A released
  slot's reclaim inherited the previous incarnation's tech/milestone
  record holders (fresh clock → every re-research spam-fired "new
  fastest" announcements), milestone threshold gates, research timeline,
  custom team name from `/mts-rename`, engine-level friendship flags
  (granting a stranger shared chart + turret immunity), friend-request
  intents, and "previously left this team" markers that wrongly stripped
  inventory from players joining the slot's new occupant. All of these
  are now wiped on release via a shared `wipe_slot_state` helper.

## 0.3.6

- Fix unresponsive landing pen buttons after a mod version upgrade —
  on_configuration_changed was back-filling the "spawned" flag for every
  player, including those currently in the pen, which made is_in_pen
  return false and silently gate every pen button

## 0.3.5

- Fix top-bar buttons (Teams, Stats, Research, Welcome) not working in saves
  loaded from older versions — click handlers were registered inside
  on_player_created, which never fires for existing players

## 0.3.4

- Fix landing pen GUI not refreshing after a team is disbanded
- Rebuild open GUIs on version change so stale content goes away after updates

## 0.3.3

- Add `/mts-disband` admin command to disband a team and free the slot
- Fix team clock not resetting when a team slot is released
