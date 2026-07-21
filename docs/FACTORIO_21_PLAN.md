# Factorio 2.1 — Implementation Plan

Execution plan for the adopted entries of `docs/FACTORIO_21_OPPORTUNITIES.md` (triage recorded there, 2026-07-20). Six phases, each independently testable in-game at its end; commit after each phase passes its checklist. No version bumps unless explicitly decided at release time.

## Decisions (from triage review, 2026-07-20)

- **Scope**: Full Tier A (A1, A2, A5, A6 + new capabilities A3, A4), plus the free B1 rider. Everything else DEFER/REJECT — see the triage table in the opportunities doc.
- **A1**: **REJECTED after in-game verification (2026-07-21).** The hub Import-from planet picker ignores both lock-derived invisibility *and* explicit `set_script_visible` per-force hides on 2.1.11 — no proactive mechanism can filter it. The reactive rewrite handler is the permanent mechanism (it already logs every correction); the soak-then-delete plan is cancelled. Engine facts recorded in ADR-0003. B8 (team-scoped picker in the hub's relative GUI) remains the only proactive alternative — still DEFER.
- **A2**: echo suppression by value-compare against `storage.color_fix_last` (kept, demoted from poll change-detector to echo suppressor). No storage-shape change, no migration.
- **A3**: alerts for **team paused/unpaused only** in v1, on **all** pauses with source-distinct wording (admin pauses get the full "an admin froze you" message; script pauses via `pause_team` get neutral "base suspended" wording — MDW docks pause routinely). Anchored to a **lazily-ensured** hidden per-team anchor entity (never trusted to survive: consumers script-kill entities and retire surfaces). Additive mts-v1 events `on_team_paused` / `on_team_resumed` ship in the same phase, mirrored to the Discord bridge for admin pauses. Flag `team_alerts_enabled`, default on, gates alerts only (never the events). Channel policy → ADR-0004.
- **A4**: team-wide pins — auto-pin joiner⇄each online teammate on every team join; plus a **Pin/Unpin button on each player row of the teams GUI (beside the follow-cam button)** for any connected player, cross-team included (consistent with open spectating). No resurrection: a dismissed or disconnect-lost pin stays gone until the next membership change or a manual re-pin. Flag `team_pins_enabled`, default on. Stateless — pin state read from `get_pins()`.
- **A6**: `disable_space_map` for **landing-pen players only** (set in `place_player`, cleared in `pen_ops.finish_spawn`). Staged-start members and spectators keep the space map.
- **Verification**: single Phase 0 console-pack session before building; results recorded below.

---

## Phase 0 — Verification pack (no production code)

Run in three saves: **(SA-MTS)** a Space Age test save with MTS and ≥2 claimed teams; **(SA-plain)** a vanilla-ish Space Age save with a platform hub; **(base)** a non-Space-Age save with MTS. `/c` disables achievements — use throwaway saves. One test (V3) needs a two-line temporary handler; control-stage edits only need a save reload, not a full restart.

Record PASS/FAIL/notes in the table, then re-check the phase gates below before building.

| # | Question | Save | Gates |
|---|---|---|---|
| V1 | Does `set_script_visible(space-location, false)` remove the entry from the hub Import-from dropdown (not just Factoriopedia/tech tree)? | SA-plain | Phase 3 entirely |
| V2 | Does omitting the value clear the override back to tech-computed? Does the override survive `force.reset()` and `reset_technology_effects()`? Does research of a discovery tech override a script-hide? Does `unlock_space_location(variant)` affect *visibility* at all? Can a force still remote-view a surface whose space location is script-hidden but whose surface is unhidden (**friend-view case**)? | SA-plain + SA-MTS | Phase 3 design |
| V3 | Does `on_player_color_changed` fire on script writes? Synchronously or deferred? On `chat_color` writes? On join? On same-value writes? | any MTS save | Phase 2 design |
| V4 | Does a custom alert anchored to a hidden, zero-box entity (test with `mts-passive-radar`) render sensibly — tray entry, map icon, dismissible? Does `LuaPlayer::add_custom_alert` exist (for mid-pause joiners)? | SA-MTS | Phase 5 entirely |
| V5 | Pin lifetime: survives save/load? Destroyed by native dismissal (visible via `get_pins()`)? Target on a force-hidden surface — what renders? Target disconnects — pin state? Target in a *remote controller* with their body parked on another surface — what does the pin track? (Universal on Brave New MTS servers.) | SA-MTS (+MP for disconnect/hidden-surface) | Phase 6 design |
| V6 | Fresh force: what do `unlock_logistic_network` / `unlock_travel_to_space_platforms` / `cargo_landing_pad_limit` / `max_cargo_bay_unloading_distance` read? Does a developed force with logistics researched read `unlock_logistic_network = true`? | SA-plain | Phase 1 safety |
| V7 | Does `disable_space_map = true` hide the button and block the space map? Does writing it on a non-SA install error or no-op? | SA-plain + base | Phase 4 |
| V8 | Does a surface `associate_surface`'d to a script-hidden planet still render normally (remote view, labels)? Can a platform already *parked above* a location that becomes script-hidden still depart / pick a new destination? | SA-MTS (+an MDW save if handy) | Phase 3 (consumer safety) |

### Headless verification results (2026-07-21, Factorio 2.1.11 headless + ported MTS)

API-semantics halves of the pack, verified by scripted headless runs (`run-vanilla.log` / `run-mts.log` in the session scratchpad):

- **Lock ⇄ visibility coupling (new engine behaviour, changes everything):** `lock_space_location` makes `is_visible` **false**; `unlock_space_location` makes it **true**. On the ported MTS with *no* script-visibility calls, team-1 already reads: own home variant visible, foreign variants invisible, base planets invisible, own undiscovered variants invisible — **the exact Phase 3 invariant, produced by the existing lock choreography alone.**
- `set_script_visible` semantics: override beats researched discovery tech (hidden stays hidden); script-`true` beats a lock (visible while unschedulable — never do this on foreign variants); override **survives** both `force.reset()` and `reset_technology_effects()`; clearing requires an **explicit `nil` second argument** — omitting the argument is an error ("Expected 2 arguments"), despite the docs marking it optional.
- **V6 PASS in full:** fresh force reads `unlock_logistic_network=false`, `unlock_travel_to_space_platforms=false`, `cargo_landing_pad_limit=1`, `max_cargo_bay_unloading_distance=0`; a fully-researched force reads `true` on both unlocks — blind copy source→target is safe. **Phase 1 is unblocked.**
- `defines.events.on_player_color_changed` exists (V3 firing semantics still need a real player — GUI session).
- Force alert API (`add_alert`/`add_custom_alert`/`remove_alert`) works, including targeted `remove_alert{entity=…}`, and works anchored to a script-created `mts-passive-radar` on a team force. `LuaEntity.protected` is writable and reads back (B1 confirmed). Rendering is the remaining V4 half.
- `create_space_platform` + `apply_starter_pack()` produces a valid platform with a valid hub (the Session A helper snippet is sound). Assigning a schedule targeting a script-hidden location is *not* rejected by the API (V8's departure half looks permissive; GUI confirmation pending).
- mts-v1 answers on 2.1.11 (`get_team_list` returned the 20-team pool; `is_team_paused` works) — the ported mod boots headless.

### V1/V2 — GUI results (2026-07-21) and the remaining check

**V1 FAILED, both ways — A1 REJECTED.** On a claimed team, the hub Import-from planet picker listed every team's variants plus base planets despite lock-derived invisibility (baseline), and an explicit bulk `set_script_visible(..., false)` over base nauvis + all foreign nauvis variants changed nothing after a full picker reopen. The picker filters on neither axis; the reactive rewrite handler stays permanently.

**Friend-view regression check (elevated — applies to the shipped port TODAY, independent of Phase 3):** locks now imply invisibility, so befriend another team and remote-view their variant surface. If navigation or rendering is broken, the 2.1 port has a live regression that needs script-`true` visibility for friends' variants (or another fix) *now*, not in Phase 3.

Manual override probes, if you want to see them with your own eyes (clear needs the explicit `nil`):
```
/c game.player.force.set_script_visible({type="space-location", name="vulcanus"}, false)
/c game.player.force.set_script_visible({type="space-location", name="vulcanus"}, nil)
/c game.print(serpent.line(game.player.force.get_script_visible({type="space-location", name="vulcanus"})))
/c game.print(tostring(game.player.force.is_visible({type="space-location", name="vulcanus"})))
```
Override vs technology (adjust tech name to the SA discovery tech, e.g. `planet-discovery-vulcanus`):
```
/c game.player.force.set_script_visible({type="space-location", name="vulcanus"}, false)
/c game.player.force.technologies["planet-discovery-vulcanus"].researched = true
-- expected per docs: still hidden (script override beats tech-computed) — confirm
```
Survival across resets (SA-MTS save, use a free slot force):
```
/c local f = game.forces["team-5"] f.set_script_visible({type="space-location", name="vulcanus"}, false) f.reset() game.print(serpent.line(f.get_script_visible({type="space-location", name="vulcanus"})))
/c local f = game.forces["team-5"] f.set_script_visible({type="space-location", name="vulcanus"}, false) f.reset_technology_effects() game.print(serpent.line(f.get_script_visible({type="space-location", name="vulcanus"})))
```
`reset()` here leaves the free slot without its pool-seeded tech/diplomacy until the next claim — fine only because this save is discarded.

Variant probe (SA-MTS, on your own team force — decides whether own-variant reveal must be script-driven): pick one of your own *undiscovered* variants, check `is_visible` and the hub dropdown, then `/c game.player.force.unlock_space_location("mts-vulcanus-1")` (adjust name) and re-check both. If unlock does not change visibility, Phase 3 drives own-variant visibility by script (expected).

Friend-view probe (SA-MTS): script-hide a foreign variant from your force while its *surface* is unhidden (`/c game.player.force.set_surface_hidden(game.surfaces["mts-vulcanus-2"], false)` — adjust), then try to remote-view that surface. If script-hiding the location blocks remote-view navigation to a visible surface, Phase 3 needs a friendship exception (see gate).

### V3 — colour event semantics

Temporarily add inside `events/player_lifecycle.lua`'s `register()` (revert after the session):
```lua
script.on_event(defines.events.on_player_color_changed, function(e)
  game.print("[21-verify] color changed: player=" .. e.player_index .. " tick=" .. e.tick)
end)
```
Reload the save. **First turn off the "Readable Player Colours" admin flag for the session** — the still-active 60-tick poll otherwise rewrites test colours mid-test and fires extra events. Use bright, non-brown colours (below is safe: luminance ≥ 0.5, hue outside the 20–50° band):
```
/c game.print("before") game.player.color = {r=0.2, g=0.9, b=0.9} game.print("after")
-- handler line BETWEEN before/after → synchronous dispatch; after → deferred
/c game.player.chat_color = {r=1, g=1, b=0}      -- does chat_color fire it?
/c game.player.color = game.player.color          -- same-value write — fires?
```
Also: change colour via the vanilla GUI and `/color`, and rejoin the save (does it fire for the initial colour on join?).

### V4 — alert on a hidden anchor

```
/c local r = game.player.surface.create_entity{name="mts-passive-radar", position=game.player.position, force=game.player.force} game.player.force.add_custom_alert(r, {type="item", name="iron-plate"}, "MTS test alert", true)
```
Check tray, map icon at your position, click-through, dismissal. Then:
```
/c local e = game.player.surface.find_entities_filtered{name="mts-passive-radar", position=game.player.position, radius=5}[1] if e then game.player.force.remove_alert{entity = e} game.print("removed by entity") else game.print("radar not found — move back to where you created it; do NOT call remove_alert with a nil entity (empty filter clears ALL alerts)") end
/c for _, e in pairs(game.player.surface.find_entities_filtered{name="mts-passive-radar", position=game.player.position, radius=5}) do e.destroy() end
/c game.print(tostring(pcall(function() return game.player.add_custom_alert end)))
```

### V5 — pin lifetime

```
/c local p = game.player.add_pin{player = game.player, label = "self-test"} game.print(tostring(p and p.valid))
/c game.print(#game.player.get_pins())
```
Dismiss the pin in the UI → re-run the count (dismissal detectable?). Save + reload → count again (persistence). In MP: pin a player on another team's (hidden) surface — what renders, and what does it do while spectating? Have the target disconnect — pin validity?

### V6 — force-state defaults

SA-plain save (cleanup: merge the test force away afterwards):
```
/c local f = game.create_force("t21") game.print(tostring(f.unlock_logistic_network) .. " " .. tostring(f.unlock_travel_to_space_platforms) .. " " .. tostring(f.cargo_landing_pad_limit) .. " " .. tostring(f.max_cargo_bay_unloading_distance))
/c local f = game.player.force game.print(tostring(f.unlock_logistic_network) .. " " .. tostring(f.unlock_travel_to_space_platforms))
/c game.merge_forces("t21", "player")
```
The second read matters most: a developed force with logistic robotics researched must read `true`, else blind copying is unsafe and the copy needs a `source-true-only` guard.

### V7 — space map flag

```
/c game.player.disable_space_map = true
/c game.player.disable_space_map = false
```
On the **base** (non-SA) save:
```
/c game.print(tostring(pcall(function() game.player.disable_space_map = true end)))
```

**End of phase:** table above filled in; re-scope any phase whose gate failed (V1 fail collapses Phase 3 to "keep handler, record REJECT"; V4 fail collapses Phase 5).

---

## Phase 1 — A5 clone parity + B1 `protected` (trivial, control stage)

**Gate:** V6.

**Changes**
- `scripts/team_slots.lua` `copy_force_state` (48-63): one `pcall` block after the space-platforms copy (line 62) mirroring `unlock_logistic_network`, `unlock_travel_to_space_platforms`, `cargo_landing_pad_limit`, `max_cargo_bay_unloading_distance` from source to target — guarded per V6's answer. All three call sites (pool create :146, claim :187, release :299) inherit it.
- B1: `protected = true` in `harden()` (`scripts/remote_api.lua:758-765`, radar — the meaningful one: team-owned, at war with biters) and in `configure()` (`gui/pen_info_panel.lua:59-62`).

**Test checklist**
- Claim a slot; console-read the four properties on the team force and compare with `game.forces.player`.
- Release + reclaim the slot; re-check (stale-state wipe still clean).
- Console-create a passive radar (V4 snippet); read `.protected == true`. Same for the pen panel entity.
- Non-SA save: claim a team without errors.

---

## Phase 2 — A2 colour event (control stage)

**Gate:** V3.

**Changes**
- `scripts/color_fix.lua`: reorder `fix_player` to store `color_fix_last` **before** writing `player.color`/`chat_color` (mirror `fix_all`, which already stores first); add `on_color_changed(player)` = echo check (`differs` vs `color_fix_last`, skip fix on match) + existing fix path; delete `poll()`; update the header comment (the "no event exists" rationale is obsolete; `color_fix_last`'s role is now echo suppression).
- New small module (e.g. `scripts/team_color.lua`): `adopt_if_leader(player)` — the body of `sync_leader_colors` for one player (epsilon compare vs `force.custom_color`, adopt, fan out to spawn_labels / gameplay GUIs / awards / follow cam / team settings).
- `events/player_lifecycle.lua` `register()`: register `on_player_color_changed` → `color_fix.on_color_changed(player)` then `team_color.adopt_if_leader(player)`. **Always** run the adopt step, echo or not — the echo of our own fix is exactly when the force adopts the fixed colour.
- Join path (`player_lifecycle.lua:70`): keep `color_fix.on_joined`; add `team_color.adopt_if_leader` after it (covers join-with-clean-colour while `custom_color` drifted).
- Admin path (`/mts-fixcolors` → `color_fix.fix_all`): do **not** rely on the event echoing for force adoption — after `fix_all`/`fix_player` writes a colour, call `team_color.adopt_if_leader(player)` directly (idempotent, harmless if the engine event also fires). This keeps the admin path correct even if V3 answers "no" on script-write events.
- `events/ticks.lua`: delete `sync_leader_colors` + the `on_nth_tick(60)` registration (:226) + now-unused requires.

**Test checklist**
- `/color red` as leader → labels, GUIs, follow cam recolour immediately (not up to 1 s later).
- Pick a very dark colour → brightened once, one notification, no flicker over the next minute.
- Pick a brown → vivid orange.
- Non-leader colour change → force colour untouched.
- Rejoin with a clashing/dark colour → fixed on join.
- Leader handover (`/mts-kick` or leave) → new leader's colour adopted.
- Grep: no remaining `on_nth_tick(60)` registration.

---

## Phase 3 — A1 planet visibility: **REJECTED, no build** (verified in GUI 2026-07-21)

The decisive test failed both ways: on a claimed team, the hub Import-from planet picker listed all teams' variants and base planets despite (a) lock-derived invisibility (2.1 couples `lock_space_location` ⇄ `is_visible` — confirmed headlessly at API level) and (b) an explicit bulk `set_script_visible(..., false)` over base nauvis and every foreign nauvis variant, re-checked after fully reopening the picker. The picker filters on neither axis, so no per-force mechanism can fix the dropdown. **The reactive rewrite handler (`planet_map.lua:424-482`) is the permanent mechanism** — it already logs every correction; the planned soak-then-delete is cancelled. Phase number retained so later phases keep their numbering.

Engine facts recorded for future work (ADR-0003): overrides beat tech-computed state and locks, survive `force.reset()` and `reset_technology_effects()`, and clear only with an explicit `nil`; never set script-`true` on a foreign variant. B8 (a team-scoped picker in MTS's existing hub relative GUI) is the only remaining proactive path — DEFER stands.

**Friend-view regression: RESOLVED — NO regression (RCON engine test, 2026-07-21).** Concern was that 2.1's lock→invisibility coupling would break friends remote-viewing each other's variant surfaces. Tested headlessly on the ported mod: with team-1's view of the friend surface `mts-nauvis-2` at space-location `is_visible=false` (locked/foreign) but the surface itself unhidden (`set_surface_hidden(false)` — what friendship does), `set_controller{type=remote, surface=mts-nauvis-2}` **succeeded** and the player rendered that surface (`REMOTE_VIEW_SET ok=true`, viewing_surface=mts-nauvis-2). An invisible space-location does not block remote-viewing its surface. Crucially, MTS's own friend/spectator navigation uses exactly this `set_controller` path (`scripts/spectator/core.lua:101-102`, `ops.lua:114-115`) + `set_surface_hidden`, never the vanilla space-map planet switcher — which is the only surface the lock-invisibility coupling touches. So no friendship-visibility patch is needed. (Method note: a GUI client couldn't be automated — the DRM-free full download ships without the Space Age entitlement, and the user's Steam client was their live session; the engine-level test via RCON is decisive for the navigation mechanism. Not covered: pixel-level rendering confirmation and whether the friend planet still appears in the vanilla space-map dropdown — the latter is expected absent and irrelevant to MTS nav.)
- Spectate: spectator force holds no locks — unaffected (unchanged from pre-2.1).

**Test checklist**
- Own hub Import-from dropdown lists only own variants (home + discovered); no base planets, no foreign variants.
- Research a discovery tech → own variant appears in the dropdown; foreign stays absent.
- Slot release + reclaim → invariant holds on the recycled force.
- `/c game.forces["team-N"].reset_technology_effects()` → invariant holds (re-applied by the existing handler).
- Befriend another team → surfaces shared as before, dropdowns still isolated.
- Spectate another team → remote view navigation unaffected.
- Non-SA save: no errors (SA-gated paths no-op).
- A platform parked above a base planet / foreign variant when the hide lands can still depart and pick a new destination (V8; Brave New MTS's expansion loop depends on this).
- On an MDW save: warp surfaces associated to now-hidden planets render normally in remote view.
- Handler still registered (safety net); factorio-current.log shows no rewrite lines during normal play.

**Follow-up (next release, not this effort):** after one release of multiplayer soak with zero rewrite log lines, delete the handler, its registration (`events/ticks.lua:133-134`), and `planet_name_to_base`.

---

## Phase 4 — A6 space-map gate (control stage)

**Gate:** V7.

**Changes**
- `gui/landing_pen.lua` `place_player` (26-50): set `disable_space_map = true` (pcall-guarded per V7's non-SA answer) **unconditionally at the top of the function** — it is a plain player flag valid in both branches. The permission-group write it would otherwise sit beside (:39-40) only runs in the already-on-pen-surface branch; a brand-new player's first entry takes the deferred-teleport branch (:44-48, resolved later in `process_pending_teleports` :52-84) and would be missed. Rejoin re-assertion comes free (`player_lifecycle.lua:72-74` re-runs `place_player`).
- **Gating must stay state-based** (`landing_pen.is_in_pen` / `storage.spawned_players`), never physical-surface-based — Brave New MTS permanently parks every character on the pen surface while players operate via remote view; a surface-name gate would strip the space map from every BNM player. Record this as a code comment at the set site.
- `gui/pen_ops.lua` `finish_spawn` (42-55): clear the flag — the documented single "left the pen" point, covering both solo claim and buddy accept.
- `gui/landing_pen.lua` `return_to_pen` (88-135): set it again for mid-session pen returns (leave/kick/disband).

**Test checklist**
- Brand-new player's **first** pen entry → space map gated immediately (the deferred-teleport branch, not just rejoin).
- Pen player: space map button hidden / space map unopenable; spectating players and staged-start members unaffected.
- Claim solo → space map back. Buddy-join → space map back.
- Leave team (back to pen) → gated again; rejoin while in pen → still gated.
- Non-SA save: pen entry/exit without errors.

---

## Phase 5 — A3 pause alerts (**data stage — full Factorio restart required**)

**Gate:** V4.

**Changes**
- New prototype (e.g. `prototypes/entities/alert-anchor.lua`): inert, hidden, force-ownable anchor (`simple-entity-with-owner` base; zero collision/selection boxes, `hidden`, not-on-map-style flags per the passive-radar template, `protected = true`, indestructible; must **not** be SA-gated). **Data-stage change — remind everyone to fully restart Factorio, not just reload the save.**
- New small module (e.g. `scripts/alert_anchor.lua`): **ensure-on-use, never create-on-claim** — no home surface exists at claim time (surfaces are created later in `spawn_into_world`, and MDW retires the claim-time home surface on the team's first warp). `ensure(force)` runs immediately before every alert raise: find a valid existing anchor on a *currently-valid* owned team surface (idempotent per surface, radius-matched like `ensure_passive_radar_impl`, `remote_api.lua:746-773`; tolerate clone-duplicated anchors by taking the first match), create at home-surface spawn if missing, fall back to any valid owned surface. Consumers can and do script-kill entities — Diggy/The Cave cave-collapse `crush` calls `entity.die()`, which bypasses both `destructible = false` and `protected`; BNM's footprint-clearing destroys `simple-entity-with-owner` near spawn — so the anchor is *expected* to die mid-life and must always be re-ensured, never trusted.
- Pause flow (`scripts/pause/`): thread a **source** through (admin command vs `pause_team` remote — internal parameter, no mts-v1 signature change). On pause → `force.add_custom_alert(anchor, icon, localised message, true)` with **source-distinct wording**: admin pauses get the full admin-froze-you message, script pauses get neutral "base suspended" wording (MDW docks pause routinely — an admin-flavoured message would be a false signal). On unpause → `force.remove_alert{entity = anchor}` **only if the anchor is valid** (never `remove_alert{}` — the empty filter clears *all* alerts; if the anchor died mid-pause, fall back to an icon-scoped filter). Mid-pause joiner: in `on_player_joined_game`, if the player's team is paused → `player.add_custom_alert(...)` (per V4's LuaPlayer check).
- **`pause_team` / `unpause_team` are a hardened surface**: MDW calls both via unprotected `remote.call` from a per-team tick handler — no code added by this phase may throw out of them. Error-contain the alert/anchor/event work (pcall) so a failure degrades to a log line, never a consumer crash.
- **Additive mts-v1 events** `on_team_paused` / `on_team_resumed`: implement the drafted `raise_team_paused` / `raise_team_resumed` stubs (`scripts/remote_api.lua:489-495`) from the pause flow, payload including the team identity and a `source` field (`"admin"` / `"script"`). Events fire for **all** pauses regardless of `team_alerts_enabled` — consumers depend on them (retires MDW's per-second `is_team_paused` polling; lets The Cave suspend collapse heartbeats). Bridge catalogue entries + `bridge_text` + labels: **Discord announcement for admin-source pauses only** (script pauses would spam Discord on every MDW dock cycle; revisit if a consumer wants opt-in). Document both events in `docs/MTS_API.md` (11 → 13 events; additive, freeze-compatible).
- `scripts/admin_flags.lua`: `team_alerts_enabled` in `FLAGS` + `FLAG_DEFAULTS` (default `true`) — gates the alerts only, never the events or bridge raise.
- Locale entries for both alert wordings.

**Test checklist**
- **Full restart first** (data stage).
- `/mts-pause team-N` → every connected member sees the alert (tray + map icon at spawn); admin wording; Discord message appears (with the paired ODB companion running).
- `/mts-resume team-N` → alert gone for everyone; Discord resume message.
- `remote.call("mts-v1", "pause_team", ...)` from console → neutral wording, **no Discord message**, both custom events observed (temporary consumer-style listener or ODB log).
- Console-`die()` the anchor, then pause and unpause → no error either way, alert re-raised on next pause (ensure-on-use works).
- On an MDW save: pause after the team's first warp (claim-time surface retired) → alert lands on a valid surface, no error; run a dock cycle → neutral blink, no crash from the `remote.call` tick context.
- Join (or rejoin) while the team is paused → alert present for the joiner.
- Dismiss the alert, stay paused → no re-spam; unpause/pause cycle re-raises it.
- Flag off → no alerts, but both mts-v1 events still fire.
- Non-SA save: pause/unpause works (alerts are base API; anchor prototype not SA-gated).

---

## Phase 6 — A4 team pins (control stage)

**Gate:** V5.

**Changes**
- New module (e.g. `scripts/team_pins.lua`), stateless — pin state is always read live from `player.get_pins()` (match by target player), never stored:
  - `pin(owner, target)` / `unpin(owner, target)` / `is_pinned(owner, target)`.
  - `on_team_joined(player)`: create mutual pins joiner⇄each *connected* teammate.
  - `on_team_left(player)`: destroy the leaver's teammate pins and teammates' pins targeting the leaver.
  - Disconnect cleanup per V5's findings (if the engine doesn't already invalidate, destroy pins targeting the leaver in `on_player_left_game`).
- Hook the team-membership funnel by direct dispatch (project preference): the sites in `scripts/remote_api.lua` (~539-540 / raise helpers at 408-421) that raise `on_player_joined_team` / `on_player_left_team` already see every join/leave path — call `team_pins` from the same spots, **but skip the `team_pins` calls (never the mts-v1 raises) when the force change is a spectate hop** (spectate enter/exit flips `player.force` via `apply_spectator_state`/`restore_player_state`, `spectator/core.lua:17,:31`; detect via the `storage.spectator_real_force[player_index]` condition). Hooked without this guard, every spectate round-trip would destroy and auto-recreate pins — violating the no-resurrection rule. No mts-v1 surface change.
- GUI: a Pin/Unpin toggle button on each **player row** of the teams GUI, beside the follow-cam button (`add_member_row`, `gui/team_card.lua:65-133`, follow-cam at :83-91; new tag e.g. `sb_pin_player`), shown for every *connected* player except yourself — **cross-team included** (consistent with open spectating; a rival pin is mainly useful while spectating, per V5). Note the `sb_spectate` button (:189-200) is per-*surface*, not per-player — a player-targeting toggle belongs on the member row. Handler dispatched beside `sb_spectate`'s in `gui/teams.lua:143-145`; caption/state from `is_pinned`; refresh the card on toggle.
- No resurrection: nothing recreates pins on rejoin — the button is the manual re-pin path; native dismissal is respected (V5 confirms dismissal is observable).
- `scripts/admin_flags.lua`: `team_pins_enabled` (default `true`) gating both auto-pins and the buttons.
- Module header: note that pin create/dismiss events are intentionally **not** emitted to the Discord bridge.

**Test checklist (needs one MP session)**
- Buddy accept → both players pinned to each other; third join → pinned with everyone online.
- Dismiss a pin, spectate someone and return → the dismissed pin stays gone (spectate-hop guard works; no churn).
- Teams GUI shows teammates as already-pinned; dismiss one natively → GUI shows unpinned; button re-pins.
- Pin a rival player → observe behaviour on their hidden surface vs while spectating (matches V5 expectations).
- Leave/kick/disband → all pins involving that player gone.
- Disconnect target → no invalid-pin errors; rejoin → no resurrection.
- Flag off → no buttons, no auto-pins; existing pins cleaned up or left per implementation choice (pick one, note it in the module header).

---

## Standing notes

- Commit at the end of each phase, **after** its in-game checklist passes. No version bumps unless explicitly decided.
- Phase 5 is the only data-stage phase — full Factorio restart, and say so in the commit/testing notes.
- mts-v1: **no signature changes anywhere**; Phase 5 adds two additive events (`on_team_paused` / `on_team_resumed`) plus bridge catalogue entries — additions are allowed under the v1 freeze. Phase 5 also changes the *failure envelope* of `pause_team`/`unpause_team`, which consumers call unprotected — hence the hardened-surface rule above.
- **Release coordination:** MTS 2.1 must ship **paired with an open-discord-bridge companion release** bumping the companion's `factorio_version` to "2.1" — it currently declares "2.0", silently fails to load on a 2.1 server, and MTS's `remote.interfaces` guard then drops every Discord announcement with no error. Note the pairing in both mods' release notes.
- Consumer-mod review (2026-07-20, all five consumers): outcome recorded in `docs/FACTORIO_21_OPPORTUNITIES.md` under "Consumer review outcome".
- Decisions recorded: triage table in `docs/FACTORIO_21_OPPORTUNITIES.md`; ADR-0003 (visibility model); ADR-0004 (notification channels); ADR-0001 amended re personal-equipment power (B15).
