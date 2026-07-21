# Factorio 2.1 — Scripting Opportunities for MTS

## Purpose

MTS has been ported to 2.1 (commit `098f921`) — that commit fixed only what was *broken*. This document catalogues what 2.1 makes *newly possible*, so it can be triaged into work and non-work.

**This is a deliberately over-inclusive catalogue, not a roadmap.** Entries are proposals, not commitments. Several are almost certainly not worth doing; they are listed so the reviewer can reject them once, on the record, rather than have them resurface.

## How to review this

For each entry, decide one of: **ADOPT** (worth building), **DEFER** (real, not now), **REJECT** (not worth it / wrong for MTS). Record the reason on REJECT — the reason is the durable artifact.

Bias to REJECT. MTS is a mature mod with a working feature set; most of these are additive polish, and the cost of a half-adopted API is worse than not adopting it.

Useful lenses:
- **Does it delete code?** Entries that remove polling, shadow state, or a documented workaround are worth more than entries that add features.
- **Does it change save-state?** Anything touching `storage` shape needs a migration and carries multiplayer desync risk.
- **Is it Space-Age-gated?** MTS must work without Space Age (team cap 20 with SA, 60 without). Anything platform/cargo/quality-specific needs a fallback path.
- **Is the API actually verified?** See "Verification debt" — every entry rests on doc-reading, not in-game testing.

## Project constraints these must respect

From `CONTEXT.md`, `docs/PLAN.md`, and the ADRs:

- Small files, small functions, DRY, generous comments.
- **Events over polling.** This is a standing preference and it drives the ranking below.
- Space Age is an *optional* dependency — never a hard requirement.
- MTS is a platform: `mts-v1` consumers (Brave New MTS, MTS Dimension Warp) depend on its remote interface and 11 custom events. Additive changes are fine; signature changes are not.
- `storage`-backed registries are deliberate (a mid-game joiner can't `remote.call` in `on_load`; session-scoped registries would desync). Don't propose moving them.
- Verify API behaviour empirically in-game before building on it.

---

# Tier A — Strong candidates

## A1. `LuaForce::set_script_visible` on space locations — retire the platform-hub leak workaround

**This is the highest-value entry in the document.** It is the only one that can delete a documented, load-bearing workaround rather than add a feature.

**API:** `set_script_visible(unlockable, value?)`, `is_visible(unlockable)`, `get_script_visible(unlockable)` — all new in 2.1. Critically, `UnlockableID` is `{type, name?}` where `type` accepts **`"space-location"`**, plus `recipe`, `quality`, `item`, `entity`, `fluid`, `asteroid-chunk`, `tile`, `ammo-category`. *"When set to explicitly hidden or visible the value overrides the state computed through technologies."*

**MTS today:** `scripts/planet_map.lua:400-445` implements a **reactive correction** for a limitation stated in its own comment: *"every team's hub still lists every planet variant (and every base planet) in the dropdown"*. Because the native space-platform-hub `import_from` dropdown cannot be filtered per force in 2.x, MTS instead hooks `on_entity_logistic_slot_changed` and rewrites the slot *after* the player picks a foreign team's planet. The handler carries substantial incidental complexity: gating on `surface.platform` so inert ground-chest copies aren't rewritten, handling `import_from` arriving as a string / `{name=}` table / `LuaSpaceLocationPrototype` userdata, and avoiding spam through logistic-group propagation.

**Proposal:** Hide every *other* team's planet variants from each team force via `set_script_visible({type = "space-location", name = variant}, false)`, applied wherever `planet_map` already applies per-force planet locks (`planet_map.lua:148,167` hide base planets via `set_surface_hidden`). If the hidden location drops out of the hub dropdown, the reactive rewrite becomes dead code.

**Value:** Potentially very high. Turns a reactive, player-visible correction into a proactive invariant, and deletes ~45 lines plus an event handler. Also aligns with MTS's core premise — a team shouldn't *see* other teams' planets in the first place.

**Risks / unknowns:**
- **The decisive question is unverified:** does `set_script_visible(space-location, false)` actually remove the entry from the native platform-hub `import_from` dropdown, or does it only affect Factoriopedia and tech-tree presentation? If the latter, this entry collapses to nothing. **Test this before any design work.**
- Interaction with MTS's existing `set_surface_hidden` and discovery-tech unlock re-derivation (`on_technology_effects_reset`, `planet_map.lua:185-215`) is unknown. Script-set visibility *overrides* technology-computed state, which could fight the existing unlock logic.
- Hiding a team's *own* variant by accident would be a severe bug. Needs careful set arithmetic across the 20-team cap.
- Keep the reactive handler until the proactive path is proven in multiplayer.

**Effort:** Medium. **Recommendation:** ADOPT the investigation at top priority; the build is contingent on the dropdown test.

---

## A2. `on_player_color_changed` — delete two polling loops

**API:** `defines.events.on_player_color_changed`, payload `{player_index, name, tick}` (new in 2.1).

**MTS today:** Two independent polling loops exist *solely* because this event didn't exist, and both say so in their own comments:

- `events/ticks.lua:44-68` — `sync_leader_colors()`, run from the 60-tick handler. Comment: *"No engine event fires on a player colour change, so this is polled"*. Iterates every team leader, float-compares `leader.color` against `force.custom_color` with a 0.001 epsilon, and on drift fans out to five refreshes: `spawn_labels.refresh_for_force`, `refresh_all_gameplay_guis`, `awards_gui.update_all`, `follow_cam.rebuild_all`, `team_settings.update_all_for_force`.
- `scripts/color_fix.lua:189-200` — `M.poll()`, called from `ticks.lua:47`. Comment: *"Poll for colour changes (no engine event exists)"*. Walks `game.connected_players` comparing against the `storage.color_fix_last` shadow table.

**Proposal:** Register `on_player_color_changed`. Route both behaviours through it, preserving today's ordering (`color_fix` first, so the team adopts the *fixed* colour rather than the raw one).

**Value:** High. Deletes per-tick work that scales with player count, removes the float-epsilon comparison, and potentially lets `storage.color_fix_last` be deleted — its only purpose is change detection.

**Risks:**
- **`color_fix` writes `player.color`, which will re-fire the event.** Needs reentrancy handling. This is the main design question — force an answer. Options: an in-flight flag; or keep `color_fix_last` demoted to a pure write-echo suppressor (far smaller than its current role).
- Deleting `storage.color_fix_last` is a storage-shape change → migration.
- Does the event fire for the initial colour on join? If not, the `on_player_joined_game` path in `events/player_lifecycle.lua` must stay.

**Effort:** Small–medium. **Recommendation:** ADOPT.

---

## A3. `LuaForce::add_alert` / `add_custom_alert` / `remove_alert` — the missing notification channel

**API:**
- `add_alert(entity, type)` — `type` is a `defines.alert_type`.
- `add_custom_alert(entity, icon, message, show_on_map)` — `icon` is a `SignalID`, `message` a `LocalisedString`, `show_on_map` boolean.
- `remove_alert(filter)` — `AlertFilter`; empty table clears all.

All three add to *every connected player on the force* — exactly MTS's unit of addressing.

**MTS today:** MTS has six ways to tell a player something — `helpers.broadcast` (`scripts/helpers.lua:297-302`, loops players calling `p.print`), direct `player.print`, `game.print` fallback, `rendering.draw_text` (pop text / spawn labels / pen labels), GUI panels, and the Discord bridge. It uses **zero** alerts and **zero** chart tags. Milestone and global-milestone announcements currently go out as chat broadcasts, which are transient and easily missed in a busy server.

**Proposal:** Add an alert channel for events that deserve persistence: team paused/unpaused, buddy request received, milestone reached, rival team overtook you.

**Value:** Potentially high — alerts are persistent, map-visible, and dismissible, which chat broadcasts are not. This and A4 are the only entries offering a genuinely *new capability* rather than a cleaner way to do something MTS already does.

**Risks:**
- **All three require an entity anchor**, and MTS won't always have a sensible one. The team's passive radar (`scripts/remote_api.lua:718-772`) is the obvious candidate — one exists per team per surface and is already inert. **But it is `hidden = true` with a zero collision box and an empty icon** (`prototypes/entities/passive-radar.lua`), so whether an alert anchored to it renders sensibly is genuinely doubtful. Test before designing.
- Alert spam is a real UX failure. Needs an explicit policy on what earns an alert vs a chat line, and probably an admin flag.
- Adopting this *alongside* the existing six channels without retiring or delineating any of them makes the codebase worse. Pair with a decision about what `broadcast` is still for.

**Effort:** Medium. **Recommendation:** ADOPT the anchor test; gate the build on it.

---

## A4. `LuaPlayer::add_pin` — buddy locate, spectator navigation

**API:** `add_pin{label?, preview_distance? (default 16), always_visible? (default true), entity?, player?, surface?, resource?, chart_tag?, position?}` → `LuaPin`. *"Either entity, player, or surface and position must be defined."* Plus `get_pins()`, `clear_pins()`. `LuaPin` exposes RW `player`, `targets`, `position`, `surface_index`, `label`, `chart_tag`, `alert_type`.

**The important detail:** the `player` parameter is the pin *target*, and it is read/write — so MTS can give player A a pin that live-tracks player B, and retarget it later.

**MTS today:** Locating people is done via follow cam (`gui/follow_cam.lua`, a 2-tick-polled grid of `camera` widgets), spectator jumps (`scripts/spectator/ops.lua`), and world-space `rendering.draw_text` spawn labels (`scripts/spawn_labels.lua`). MTS uses no chart tags at all, so the map/chart layer is currently unused real estate.

**Proposal:** In descending confidence —
1. **Buddy locate** — pin your buddy, live-tracking. Nothing in MTS does this today.
2. **Spectator navigation** — pin each team's spawn or leader.
3. **New-joiner orientation** — pin the landing pen and/or your team spawn on arrival.

**Value:** Medium-high for the buddy case; the live `player` target is a capability MTS currently lacks entirely.

**Risks:**
- Pins are per-player state that MTS would create on players' behalf. Needs opt-out and a cleanup story. **`clear_pins()` is too blunt** — it would destroy the player's own pins too, so MTS must track its `LuaPin` objects individually.
- Pin lifetime across surface change, force change, and disconnect is unverified.
- A pin pointing at a surface the player will be *bounced off* (MTS enforces surface ownership) would be actively confusing.
- `LuaPin::chart_tag` hints pins and chart tags interoperate; since MTS uses neither, adopting both at once is a bigger bite than it looks.

**Effort:** Medium. **Recommendation:** ADOPT for buddy locate; DEFER the rest.

---

## A5. `LuaForce::unlock_logistic_network` / `unlock_travel_to_space_platforms` — force-state clone parity

**API:** Both are **read/write booleans** on `LuaForce` (new in 2.1) — *not* the `unlock_x()` / `is_x_unlocked()` method pair the older space-platform API uses.

**MTS today:** `scripts/team_slots.lua:52-61` clones force state onto a claimed team slot. Team forces are pre-created at init and **never destroyed** — a slot is claimed and released, so stale state from a previous occupant is a live concern. The clone currently covers researched technologies, quality unlocks, and space platforms. Logistic-network and travel-to-platforms unlock state are **not** copied, because they weren't scriptable before 2.1.

**Proposal:** Add both to the clone. While there, audit clone *completeness* — 2.1 also adds `cargo_landing_pad_limit` (RW uint32) and `max_cargo_bay_unloading_distance` (RW double) as per-force state that a recycled slot arguably should inherit.

**Value:** Medium-high. Closes a real correctness gap in a slot-recycling design where leaked state is the known hazard.

**Risks:** Low. Verify what a fresh force reports when the granting technology *is* researched — if it reports `false`, blind copying could revoke access. `unlock_travel_to_space_platforms` needs the same Space-Age guard as the existing `pcall(target.unlock_space_platforms)`.

**Effort:** Trivial. **Recommendation:** ADOPT.

---

## A6. `LuaPlayer::disable_space_map` — landing pen gating

**API:** RW boolean. *"Set to `true` to disallow opening the space map and hide the space map button."*

**MTS today:** MTS works hard to constrain what players see and reach — three permission groups (`Default`, `spectator`, `mts-pre-start`), surface-ownership bouncing, `set_surface_hidden`, and per-force planet locks. The `mts-pre-start` group (`scripts/pre_start.lua:57-70`) denies *every* input action except a GUI allowlist. The space map is another route toward surfaces a player doesn't own.

**Proposal:** Set `disable_space_map = true` for players in the landing pen / pre-start, cleared when they claim a team. Evaluate for spectators separately (spectators are *meant* to roam).

**Value:** Medium. One property write instead of permission-group gymnastics, and it hides a button that is meaningless pre-team.

**Risks:** Space-Age-relevant only; must no-op otherwise. **Must be reliably cleared** on team claim or the player is stuck. Re-assert on join since it's player state. Note the pre-start group may already block this via its deny-all posture — check whether this is redundant before building.

**Effort:** Small. **Recommendation:** ADOPT for the landing pen, after checking redundancy against `mts-pre-start`.

---

# Tier B — Plausible, needs a decision

## B1. `LuaEntity::protected` — harden MTS's scripted entities

RW boolean; prevents *automated weapons* targeting the entity (does not prevent other damage). MTS hardens two scripted entities with `destructible = false` / `operable = false` / `minable_flag = false`: the passive radar (`scripts/remote_api.lua:758-765`) and the pen info panel (`gui/pen_info_panel.lua:59-62`). `destructible = false` already prevents the damage; `protected` additionally stops turrets wasting ammo. Nearly free.

**Recommendation:** ADOPT if touching those files anyway; otherwise REJECT as noise.

## B2. `LuaEntity` runtime tooltip fields

`set_tooltip_field()` (returns id), `get_tooltip_fields()`, `clear_tooltip_field(id)`, `clear_tooltip_fields()`. MTS sets no world-entity tooltips today (all ~98 `tooltip =` sites are GUI elements). Could surface team ownership on the passive radar, or echo run info on the pen panel.

**Risk:** the passive radar is hidden with a zero collision/selection box — likely not hoverable at all, which would make this dead on arrival for the more interesting of the two targets.

**Recommendation:** DEFER.

## B3. `LuaSurface::global_electric_network` + `LuaEntity::electric_network(s)` — audit the pause freeze

`global_electric_network` → `LuaElectricSubNetwork` or nil; `LuaEntity::electric_network` / `electric_networks` give per-entity access. `scripts/pause/power.lua` freezes a team by disabling every power *source* across owned surfaces (ADR-0001), via `find_entities_filtered{type = POWER_SOURCE_TYPES, force = force}`.

**Proposal:** Use network-level reads to *assert* the freeze held (zero production post-freeze) — a correctness check, not an optimisation. ADR-0001 records that airtightness was hard-won; a cheap assertion that it *stays* airtight is worth more than a faster freeze.

**Risk:** sub-network identity across save/load is unverified — do not store references in `storage`.

**Recommendation:** ADOPT the audit. REJECT the rewrite — see B4.

## B4. `LuaElectricNetwork::get/set_accumulators_energy` — do NOT rewrite the pause system

*Recorded as a standing rejection so it isn't re-proposed.* `set_accumulators_energy{name?, quality?, energy, equalize?}` sets only a **total**, with optional equalisation. `scripts/pause/power.lua:91-102` snapshots each accumulator's energy by `unit_number` and restores it exactly. Switching trades ADR-0001's exact-restore guarantee for fewer entity writes.

**Recommendation:** REJECT.

## B5. `LuaElectricNetwork::flow_last_tick` — per-team power in the stats GUI

Exposes accumulator energy/capacity, production and demand by priority tier, satisfaction percentages, usage fractions; plus `LuaElectricNetwork::statistics`. `gui/stats_data.lua` builds per-team comparison columns from item/fluid production statistics across each force's own surfaces; power is absent.

**Value:** Genuinely new comparison data — power satisfaction is a "how healthy is this team" signal item counts miss.

**Risk:** a team owns many surfaces and many networks; collapsing to one comparable number needs a defensible aggregation rule. Cost must be measured against the existing refresh throttle (`ticks.lua:224-225`, already throttled 6t→30t under PF-10 and gated by `any_team_researching()`).

**Recommendation:** DEFER — good idea, wants a design.

## B6. `LuaGameScript::delete_blueprint_library()`

`scripts/blueprint_lock.lua:26-37` blocks `import_blueprint`, `import_blueprint_string`, `import_blueprints_filtered`, and `open_blueprint_library_gui` on the `Default` group, wired to the `allow_blueprint_imports` admin flag (default false). Permission gating is *preventive*; the library still holds whatever a player had before the lock.

**Risk: high.** This deletes player data server-wide and is irreversible.

**Recommendation:** REJECT as automatic behaviour. DEFER as an explicit, confirmed admin command *only if* the reviewer believes the lock has a real gap.

## B7. `on_blueprint_settings_pasted`

New event: `{entity, player_index?, tags?, previous_direction?, mirrored}`. Check whether settings-paste routes around `blueprint_lock`'s input-action gating. Cheap to check; build only if the gap is real.

**Recommendation:** ADOPT the check.

## B8. `choose-elem-button` new types — `surface`, `space-connection`, `quality`, `shortcut`

MTS has exactly two `choose-elem-button` sites, both `elem_type = "item"`: stats column headers (`gui/stats.lua:135-155`) and the starter-item picker (`gui/admin.lua:167-174`). There is **no surface or planet picker anywhere** — surface selection is implicit, derived from `storage.map_force_to_planets`.

**Proposal:** Two candidates. (a) The max-team-size `drop-down` (`gui/admin.lua:94-106`) is not prototype-based, so it doesn't apply. (b) More interesting: MTS already anchors a **relative GUI** into the native platform hub (`gui/platform_hub.lua`). A filtered `space-connection` / `surface` picker there could offer a *correct* team-scoped alternative to the native dropdown.

**Important:** (b) does **not** replace A1 — players can still use the native dropdown, so the reactive correction stays either way. Treat this as a supplement to A1, not a substitute.

**Risk:** an unfiltered `surface` chooser lists every team's surfaces — an isolation leak in a mod built on team isolation. Whether `elem_filters` can constrain it is unverified.

**Recommendation:** DEFER pending the filtering question.

## B9. GUI `"inventory"` element + `on_gui_inventory_action` — starter kit editor

New `LuaGuiElement` type `"inventory"` with `inventory`, `slots_per_row`, `empty_slot_info`, `handle_cursor_transfer`, `handle_cursor_split`, etc., plus `defines.inventory_actions`. `scripts/admin_flags.lua` builds starter kits by *capturing* a player's inventory (`serialize_grid`, ~210-260) and replaying it (`restore_grid_equipment`, ~127-158).

**Value:** "Edit the kit directly" is much better UX than "get your inventory right, then capture it".

**Risk:** substantial rework of a subsystem touched recently (equipment-grid preservation landed in `228c368`), and the stored kit format would likely change → migration.

**Recommendation:** DEFER. Strong idea, poor timing.

## B10 / B11. `LuaInventory::transfer_from_stack` / `transfer_from_inventory`, and `LuaPlayer::stack_transfers` / `cursor_transfers` / `cursor_split`

**Treat as one question.** The player-level methods perform transfers *as if the player did it* and explicitly mention equipment-grid and armour-validation parameters; `stack_transfers` returns what moved or nil if blocked.

MTS's complexity in `scripts/admin_flags.lua` is almost entirely **equipment-grid reconstruction** (capturing name/position/quality/energy per equipment, then replaying with per-item `pcall`). If these methods preserve grids natively, a meaningful chunk of that code becomes unnecessary. If they don't, both entries are worthless.

**Recommendation:** Verify grid preservation first. That single answer decides both.

## B12. `LuaPlayer::saved_logistic_filters` + `respawn_quality`

`saved_logistic_filters` (RW) = *"filters that will be applied when this player respawns"*; `respawn_quality` (R prototype / W QualityID?). MTS moves players between forces and surfaces constantly (team join/leave, spectator enter/exit, pen finish-spawn) and already carefully saves/restores force, position, controller, zoom, and hub state in `scripts/spectator/core.lua`.

**Proposal:** Add these to the saved/restored set if they're currently lost.

**Risk:** the premise — that they're lost today — is unverified. Quality is Space-Age-gated.

**Recommendation:** ADOPT if the loss is confirmed.

## B13. `play_music` on Player / Force / Surface

`LuaForce::play_music(music_specification)` plays for every player on the force; also Player/Surface/GameScript variants, plus `LuaPlayer::current_music` and `on_player_music_changed`. `scripts/global_milestones.lua` already plays achievement *sounds* with a fallback path list.

**Value:** low functionally, potentially high for feel — MTS is a racing mod and a sting for "your team took the lead" is on-theme.

**Risk:** music is intrusive and overrides player audio; needs an admin flag, default off. `PlayMusicSpecification` shape unverified.

**Recommendation:** DEFER — cheap, fun, not important.

## B14. `LuaSurface::override_pollution_type`

RW `Pollutant` or nil, overriding planet/platform values. Per-team pollution variation as a handicap or run modifier. Undermines "same start, different finish" unless deliberately opted into.

**Recommendation:** REJECT for core MTS; expose via `mts-v1` if consumers want asymmetric scenarios.

## B15. `LuaEquipment::power_production` / `power_usage` / `electric_buffer_size` (now RW)

ADR-0001's freeze covers power *sources on the surface*. Personal equipment (portable fusion/solar) keeps working when the grid is down — the same category of leak as the burner-machine gap ADR-0001 explicitly accepted.

**Proposal:** Extend the freeze to personal equipment, restoring on thaw.

**Risk:** equipment is *player* state, not force state — join/leave/armour-swap mid-pause complicates restore, and the same exact-restore concern as B4 applies.

**Recommendation:** DEFER — but worth an explicit ADR-0001 amendment recording the decision either way, since "is personal power a hole in the pause guarantee?" is currently unanswered rather than answered-no.

## B16. `defines.relative_gui_type` additions — `radar_gui`, `boiler_gui`, `alerts_config_gui`, `electric_energy_interface_equipment_gui`

MTS uses relative GUIs already (`space_platform_hub_gui` in `gui/platform_hub.lua`). `radar_gui` looks relevant given MTS's passive radar, but that entity is deliberately `operable = false` and hidden, so its GUI never opens by design.

**Recommendation:** REJECT `radar_gui`. Others have no MTS surface.

## B17. `LuaPlayer::toggle_menu_leaves_remote_view`

RW boolean; *"Set to `false` to disallow leaving remote view using the toggle menu hotkey."* Spectator mode manages controller state carefully (`set_controller`, saved zoom/hub/position); `player.zoom` writes are already `pcall`-wrapped, suggesting the area is fiddly.

**Risk:** trapping a player in remote view with no exit is worse than the bug it fixes.

**Recommendation:** DEFER pending evidence the hotkey escape causes real problems today.

## B18. `LuaPlayer::hide_locked_prototypes_in_factoriopedia`

RW boolean. Optional "blind race" mode where teams can't browse un-researched content. Trivial to wire as an admin flag alongside the existing ones (`allow_blueprint_imports`, `buddy_join_enabled`, `popup_text_enabled`).

**Recommendation:** DEFER as an admin flag.

## B19. `set_script_visible` for non-space-location types

The same API as A1, applied to `recipe` / `item` / `entity` / `quality` unlockables — per-team content gating for restricted-tech scenarios.

**Recommendation:** REJECT for core MTS; document in `docs/MTS_API.md` as a capability `mts-v1` consumers can use directly. Do **not** bundle with A1 — A1 stands on the space-location case alone and shouldn't be widened before it's proven.

## B20. `LuaNotificationQueue` + `defines.target_type.force`

`LuaBootstrap::new_notification_queue()` with `add`/`find`/`remove`/`clear`/`poll`/`poll_all`. **Despite the name this is object-destruction tracking, not player notifications** — flagged to prevent a wasted investigation. Its interface is `poll()`-based, so adopting it moves *toward* polling, against project preference, and MTS's force lifecycle is already event-driven.

**Recommendation:** REJECT the queue. The new `defines.target_type.force` may still be worth noting for `register_on_object_destroyed` (which is event-driven) — though MTS never destroys team forces, so probably moot.

## B21. `ScriptRenderMode "build-cursor"` + `"cursor"` / `"build-cursor"` render targets

New render targets drawing at the player's cursor or snapped build cursor; build-cursor offset rotates with direction and mirrors. MTS uses `rendering.draw_text` heavily (pop text, spawn labels, pen terrain labels) and bounces players off surfaces they don't own.

**Proposal:** cursor-level build hints — warn *while placing* rather than after the fact.

**Recommendation:** DEFER. Real UX value, no urgency.

## B22. `LuaHelpers::stage`

New read reporting the current mod stage. Useful in `scripts/commands/debug_cmd.lua` / error reporting, and specifically for the `mts-v1` consumer ecosystem where "called at the wrong stage" is a known failure mode (consumers must defer `remote.call` out of `on_load`, per ADR-0002).

**Recommendation:** DEFER — trivial, mildly useful for consumer diagnostics.

## B23. Small items — check usage, likely N/A

| API | Note |
|---|---|
| `LuaSpacePlatform::apply_starter_pack()` `silent` param | Useful only if MTS applies starter packs programmatically; would suppress N notifications during bulk team setup. Check usage. |
| `take_technology_screenshot` / `auto_save` `allow_in_replay` | Relevant only if MTS triggers autosaves (e.g. around team resets). Check usage. |
| `LuaRecord::label` / `planner_description` (RW) | Only if MTS manipulates blueprint records; blueprint handling is lock-only today. |
| `LuaEntity::request_missing_construction_materials` | No obvious MTS use. |
| `LuaEntity::saved_set_requests`, `override_logistic_mode`, `saved_request_filters`, `saved_storage_filters` | Adjacent to `planet_map`'s logistic-slot work, but none filter the dropdown — they don't substitute for A1. |
| `LuaRenderObject::light_mode`, `light_mode` on `draw_sprite`/`draw_animation` | Cosmetic. MTS uses neither `draw_sprite` nor `draw_animation` — only `draw_text`. |

**Recommendation:** REJECT unless a usage check surprises.

---

# Tier D — Verified non-applicable

Checked against the codebase; recorded so nobody re-investigates.

| 2.1 change | Why it doesn't affect MTS |
|---|---|
| `LuaFluidBox` removal + entire fluid API overhaul | No fluidbox access anywhere. Only read-only `get_fluid_production_statistics` and `prototypes.fluid[...]` lookups. |
| Control-behaviour removals (`circuit_exclusive_mode_of_operation`, `include_fuel` rename) | MTS uses no control behaviours. |
| `defines.inventory.assembling_machine_*` / `furnace_*` / `rocket_silo_*` → `crafter_*` | MTS uses only `character_main/guns/ammo/armor` and `chest`. The `for i = 1, 255` scan in `compat/dangoreus.lua:169` is index-based over containers/wagons/cars — unaffected. |
| `SelectionModeFlags` semantic change | MTS declares no selection tools. |
| `LuaEntity::display_panel_text` no longer accepts `LocalisedString` | `gui/pen_info_panel.lua:44` writes a plain string. **Verified safe.** |
| `get_quick_bar_slot` / `set_quick_bar_slot` signature change | MTS references quick-bar *input action names* in permission lists only (`scripts/pre_start.lua:31,45-46`, `scripts/spectator/core.lua:116,132-133`), never the API. |
| `draw_light()` changed to lower-resolution gradient lights | **Verified: MTS calls no `draw_light`, `draw_sprite`, or `draw_animation` — `draw_text` only.** No visual regression. |
| `defines.default_icon_size` → `defines.constant.default_icon_size` | Not referenced. |
| `defines.relative_gui_type.storage_tank_gui` removal | Not referenced. |
| Recipe-category prototype removals, `forced_symmetry`, `build_base_evolution_requirement`, asteroid `mass`, `max_fluid_flow`, `rocket_lift_weight` | MTS defines no recipes, crafting machines, or asteroids, and overrides no utility constants. |
| `LuaPlayer::pipette_entity`, `game.create_profiler` | Not used. |
| `neighbours` / `pump_rail_target` removals | Not used. |

## Polling that 2.1 does *not* fix

MTS has twelve tick loops in `events/ticks.lua:163-239`. Recorded so the reviewer doesn't hunt for 2.1 answers that don't exist:

- **`spectator.track_home_zoom()` @ 20t** (`spectator/core.lua:236-260`) — polls player zoom and remote-view camera position. 2.1 adds **no** zoom-changed event. Still unavoidable.
- **`milestones.tick()` @ 300t** (`milestones/engine.lua:195-217`) — the heaviest scan in the mod (trackers × items × teams). 2.1 adds no production-threshold event. Still unavoidable.
- **`platform_hub.refresh_open`** — re-scans `player.opened`. Unchanged in 2.1.

Separately, three loops look convertible **for reasons unrelated to 2.1**, and are noted only so they aren't mistaken for 2.1 work: `debug_engine.tick()` runs every tick for an idle admin queue; `lfm_hint.tick()` runs every tick for a 2-minute timer; and the `storage.pending_admin_check` sweep (`ticks.lua:195-205`) may be redundant now that `on_player_promoted` / `on_player_demoted` are registered (`events/player_force.lua:27,34`). **Out of scope for this document** — file separately if worth doing.

---

# Verification debt

Everything here rests on the 2.1 changelog and the API docs at 2.1.11. **None of it has been tested in-game.** Per project practice, verify empirically before building.

| # | Question | Blocks |
|---|---|---|
| 1 | Does `set_script_visible({type="space-location"}, false)` remove the entry from the native platform-hub `import_from` dropdown, or only affect Factoriopedia/tech-tree presentation? | **A1 entirely** |
| 2 | How does script-set visibility interact with MTS's existing `set_surface_hidden` and discovery-tech unlock re-derivation? | A1 |
| 3 | Does `on_player_color_changed` fire on *script* writes to `player.color`? Does it fire for the initial colour on join? | A2 design |
| 4 | Does an alert anchored to the hidden, zero-collision-box passive radar render sensibly? | A3 entirely |
| 5 | Pin lifetime across surface change, force change, and disconnect. | A4 |
| 6 | Does a fresh force report `unlock_logistic_network = false` even when the granting tech is researched? | A5 safety |
| 7 | Is `disable_space_map` already covered by the `mts-pre-start` deny-all group? | A6 (redundancy) |
| 8 | Do `transfer_from_inventory` / `stack_transfers` preserve equipment grids? | B10/B11 both |
| 9 | Can a `surface` `choose-elem-button` be filtered via `elem_filters`? | B8 |
| 10 | Is `LuaElectricSubNetwork` identity stable across save/load? | B3 (must not be stored) |
| 11 | Are `saved_logistic_filters` / `respawn_quality` actually lost across MTS's force/surface moves today? | B12 premise |

Note: the one item in the original sweep that could have been a *missed break* rather than an opportunity — `draw_light` — has been checked and is clear.

---

# Suggested triage order

1. **A1 verification** (debt #1). Highest value in the document, and a single in-game test decides whether it's real or nothing.
2. **A5** — trivial, closes a real correctness gap in slot recycling.
3. **A2** — best code-deletion value; needs the reentrancy decision (debt #3).
4. **A6**, **B1** — small and contained (check A6 redundancy first).
5. **A3**, **A4** — the two genuinely new capabilities; both gated on verification.
6. **B10/B11** — one test (debt #8) decides both.
7. Everything else — DEFER or REJECT.
