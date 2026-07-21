# Multi-Team Support: Integration API

This document covers MTS-specific integration points: how MTS handles third-party chunk-gen mods automatically and the public `mts-v1` remote interface (events + queries).

For *generic* advice on making your mod work in any multi-force environment (not specific to MTS), see [COMPAT.md](COMPAT.md). This document assumes your mod is already reasonably force- and surface-aware, and you want to plug into MTS lifecycle directly.

---

## 1. Terrain mirroring (no integration needed)

MTS gives every team its own copy of each planet:

- Space Age: `mts-<planet>-<N>` (e.g. `mts-nauvis-3`, `mts-vulcanus-3`)
- Base 2.0 (no Space Age): `team-<N>-<planet>` (e.g. `team-3-nauvis`)

When a chunk is generated on any team surface, MTS automatically:

1. Generates the matching chunk on the *real* planet surface (`nauvis`, `vulcanus`, …), synchronously firing every third-party mod's `on_chunk_generated` handler. Their `surface.name == "nauvis"` filters accept, their decoration runs.
2. Mirrors the resulting tiles, entities, and decoratives from the real planet to the team surface via `LuaSurface.clone_area`.

Implementation: [`compat/clone_mirror.lua`](../compat/clone_mirror.lua).

Net effect: whatever your mod puts on a real planet, every team's variant gets the same. No remote interface to wire up, no surface-name predicate to update, no MTS-aware code path required. Works for vanilla and modded planets equally — the pattern strips the `mts-` / `team-N-` prefix and uses whatever planet name your mod registered.

**Verified working with:** [dangOreus](https://mods.factorio.com/mod/dangOreus), [VoidBlock](https://mods.factorio.com/mod/VoidBlock), [Alien Biomes](https://mods.factorio.com/mod/alien-biomes), [Periodic Madness](https://mods.factorio.com/mod/periodic-madness), and the vanilla worldgen stack.

### When mirroring isn't enough

Some mods don't only decorate at chunk-gen. They also have **runtime rules** that fire later — `on_built_entity`, `on_entity_died`, `on_nth_tick`, etc. — and filter those handlers by `surface.name == "nauvis"`. Mirroring gives you the *terrain*; it doesn't make those runtime rules fire on the mirrored terrain.

For those, see Pattern 5 in [COMPAT.md](COMPAT.md) ("Expose runtime rules so other mods can reuse them") or the `mts-v1` event subscription below.

---

## 2. The `mts-v1` remote interface

A stable, versioned API for mods that want first-class awareness of MTS lifecycle. Source: [`scripts/remote_api.lua`](../scripts/remote_api.lua).

**Stability contract:** the interface name `mts-v1` and every function/event listed below is frozen for the v1 lifetime. Adding new functions/events is safe; renaming or removing is not. Breaking changes will ship as a parallel `mts-v2` rather than mutating v1. Always guard your calls with `if remote.interfaces["mts-v1"] then ...` so your mod stays compatible across MTS versions and works in saves where MTS is absent.

### 2.1 Events

Custom events you can subscribe to:

| Event name                  | Payload fields                          | Raised when                                   |
|-----------------------------|-----------------------------------------|-----------------------------------------------|
| `on_team_created`           | `force_name`, `player_index` (leader)   | A team slot is claimed and the force is set up |
| `on_team_released`          | `force_name`                            | A team slot is released (team disbanded)       |
| `on_team_surface_created`   | `surface_name`, `force_name`            | A new team surface (planet variant) is created |
| `on_player_joined_team`     | `player_index`, `force_name`            | A player moves onto a team force               |
| `on_player_left_team`       | `player_index`, `force_name`            | A player leaves a team force                   |
| `on_team_clock_started`     | `force_name`, `start_tick`              | A team's clock starts (team has started playing) — fires once, on direct claim or on the staged-start "Start Playing" commit |
| `on_team_renamed`           | `force_name`, `new_name`                | A team is renamed (refresh anything showing the team name) |
| `on_team_tab_built`         | `player_index`, `tab_name`, `element`   | A player's Team Settings panel is (re)built — once per registered custom tab; `element` is the empty content frame to populate |
| `on_welcome_tab_built`      | `player_index`, `tab_name`, `element`   | The welcome screen is (re)built — once per registered welcome tab; `element` is the empty content frame to populate |
| `on_platform_hub_gui_built` | `player_index`, `widget_name`, `element`, `entity` | A player opens a space platform hub — once per registered widget; `element` is the anchored content frame, `entity` the hub |
| `on_starter_items_added`    | `items` (`{name=, count=}` list)        | An admin adds starter items while a delivery override is registered — the override consumer must deliver them |
| `on_team_paused`            | `force_name`, `source` (`"admin"`/`"script"`) | A team is paused — `/mts-pause` or the `pause_team` action. Fires on actual transitions only, and regardless of the `team_alerts_enabled` admin flag (that flag gates only the in-game alert) |
| `on_team_resumed`           | `force_name`, `source`                  | A team resumes — `/mts-resume` or `unpause_team`. Same transition-only guarantee as `on_team_paused` |

The last four events pair with the registration functions in §2.4: register a tab / widget / override once, then listen to the matching `*_built` / `*_added` event to fill the frame (or deliver the items) each time MTS raises it.

Event IDs are generated per session via `script.generate_event_name()` — they're stable for the duration of a session but not across sessions, so always look them up via `get_event_id` rather than caching the integer.

**Subscribing:**

`remote.call` is **not** legal during `on_load`, yet event handlers must be registered in both `on_init` and `on_load` for determinism. Bridge the gap with a one-shot `on_nth_tick(1)` — it fires on the same tick for every peer (so it stays multiplayer-deterministic), and both `remote.call` and `script.on_event` are legal inside it:

```lua
-- Resolve the event ID and register the real handler. Safe from a runtime
-- context (on_nth_tick / on_init), never from on_load.
local function subscribe_mts_events()
    if not remote.interfaces["mts-v1"] then return end
    local id = remote.call("mts-v1", "get_event_id", "on_team_surface_created")
    script.on_event(id, function(event)
        -- event.surface_name, event.force_name
        local surface = game.surfaces[event.surface_name]
        if surface then my_mod.setup_surface(surface, event.force_name) end
    end)
end

-- Defer to the next tick so we can remote.call for the ID even on a load path.
-- Registering on_nth_tick itself is legal in on_load (no remote.call, no
-- storage write); the deferred body runs in a normal context.
local function defer_subscribe()
    script.on_nth_tick(1, function()
        script.on_nth_tick(1, nil)  -- one-shot: unregister after the first fire
        subscribe_mts_events()
    end)
end

script.on_init(defer_subscribe)
script.on_load(defer_subscribe)
```

The `on_team_surface_created` event is the most useful one for terrain/decoration mods that need to run setup exactly once per team surface (rather than reacting per-chunk). The `on_team_created` event is useful for force-level setup — granting starting research, applying buffs, etc.

### 2.2 Queries

Synchronous queries you can call any time:

| Call                                                | Returns                                            |
|-----------------------------------------------------|----------------------------------------------------|
| `get_event_id(name)`                                | Event ID for the named event, or `nil`             |
| `get_team_list()`                                   | Array of team info tables (one per claimed slot)   |
| `get_team_info(force_name)`                         | Team info table, or `nil` if not a team force      |
| `is_team_surface(surface_name)`                     | `true` if the surface is owned by a team           |
| `get_surface_owner(surface_name)`                   | The owning team's `force_name`, or `nil`           |
| `list_team_surfaces(force_name)`                    | Array of surface names owned by that team          |
| `is_team_paused(force_name)`                        | `true` if the team is currently paused             |
| `is_team_online(force_name)`                        | `true` if any member is connected — counts a member spectating another team |
| `get_effective_force(player_index)`                 | The player's effective team `force_name` — their real team even while spectating another surface — or `nil` |
| `get_team_label(force_name)`                         | MTS-styled rich-text label (team's coloured tag + current leader in brackets), or `nil`. Reflects live state — re-fetch after a rename/leader/colour change |
| `get_starter_items()`                               | Array of admin-configured starter items (`{name=, count=}`), for a delivery-override consumer seeding teams that spawn later |

### 2.3 Actions

Functions that mutate world state. Call from a real event context (not `on_load`):

| Call                                                | Effect                                                                                  |
|-----------------------------------------------------|-----------------------------------------------------------------------------------------|
| `pause_team(force_name)`                            | Freeze the team: disable every power source (the airtight freeze), deactivate remaining entities via the amortized sweep, and (Space Age) cut pole wires for a visible "unplugged" look. Returns `true` if a pause started. |
| `unpause_team(force_name, opts)`                     | Resume the team: re-enable power sources, reactivate entities, and (Space Age) staggered-reconnect the pole wires so the lights ripple back. `opts = {mode, duration}` reserved for a future timed-pause v2. Returns `true` if a resume started. |
| `create_team_surface(force_name, spec)`             | Create (or look up) an ephemeral, caller-seeded surface for a team. `spec = {name, planet, map_gen_settings}` — `name` is **required** and must be non-variant (not `mts-<planet>-N` / `team-N-<planet>`); `planet` is used only for Space Age planet association; `map_gen_settings` carries the caller's seed. Returns the surface name, or `nil`. Works with or without Space Age. |
| `retire_team_surface(force_name, surface_name)`     | Delete a team-owned surface and unwind its bookkeeping. Returns `true` on success, `false` if the surface is invalid or not owned by that team. |
| `set_spawn_label_enabled(surface_name, enabled)`    | Suppress (`false`) or restore (`true`) MTS's default spawn label on a surface a consumer labels itself. |
| `disband_team(force_name)`                          | Disband a team: move every member back to the landing pen, release the slot, and clean up the team's surfaces. Use for a loss condition (e.g. a critical structure destroyed). |
| `ensure_passive_radar(force_name, surface, position)` | Ensure a hidden, powerless, non-charting passive radar exists so an empty team surface stays live-viewable for spectators. `surface` may be a name, index, or `LuaSurface`. Idempotent per `(surface, position)`; re-call after every surface clone. Returns the `LuaEntity`, or `nil` if the surface/force is invalid. |

A `team_info` table has the following shape:

```lua
{
    force_name           = "team-3",
    display_name         = "The Reds",     -- player-chosen name, or force_name
    status               = "occupied",      -- "occupied" | "available"
    is_occupied          = true,
    leader_player_index  = 7,
    member_count         = 4,
    is_paused            = false,
    clock_start_tick     = 1234,            -- tick the team's clock started
    online_ticks         = 98760,           -- total ticks a member has been online
}
```

**Examples:**

```lua
-- Is this surface owned by a team?
if remote.interfaces["mts-v1"]
   and remote.call("mts-v1", "is_team_surface", surface.name) then
    -- handle team-surface case
end

-- Who owns this surface?
local owner = remote.call("mts-v1", "get_surface_owner", "mts-nauvis-3")
-- → "team-3" or nil

-- All current teams:
for _, info in ipairs(remote.call("mts-v1", "get_team_list")) do
    game.print(info.display_name .. " has " .. info.member_count .. " members")
end
```

### 2.4 Registration (call once, then listen)

These extend MTS's own UI or milestone machinery. Register **once**, from your `on_init` **and** `on_configuration_changed` (where `remote.call` is legal and storage writes are allowed) — the registry persists in `storage`, so it survives save/load and stays identical on every peer. Re-registering the same `name` overwrites; it is safe to call on every config change.

| Call                                                     | Effect                                                                                       |
|----------------------------------------------------------|----------------------------------------------------------------------------------------------|
| `register_team_tab(spec)`                                | Add a tab to the Team Settings panel. `spec = {name, caption, order, mod}`. Then fill the frame handed to you by `on_team_tab_built`. |
| `register_welcome_tab(spec)`                             | Add a tab to the welcome screen (rendered **before** MTS's About/Discord; the first registered tab is selected by default). Same `spec` shape; listen to `on_welcome_tab_built`. |
| `register_platform_hub_widget(spec)`                     | Anchor a widget into the native space-platform-hub GUI. `spec = {name, caption, order, position, mod}` (`position` is a `relative_gui_position`, default `"right"`); listen to `on_platform_hub_gui_built`. |
| `register_starter_item_delivery(mod_name)`              | Take over delivery of the admin-configured starter items (MTS then stops inserting them into player inventories). Pass **your mod name** so the override self-clears if your mod is removed. Listen to `on_starter_items_added` for live additions and read `get_starter_items()` for teams that spawn later. |
| `register_milestone(spec)`                               | Define a consumer milestone. `spec = {category, verb, noun, first_threshold, thresholds}`. `first_threshold` (optional) gets a first-to-reach announcement only; each entry in `thresholds` gets both first **and** fastest. |
| `report_milestone(force_name, category, count)`         | Report a team's current counter for a registered milestone; MTS announces first/fastest via the same records + broadcast + Discord path as its built-in milestones. Event-driven — call it as the counter advances, don't poll. |

**Include a `mod` field** (your mod name) in any `register_team_tab` / `register_welcome_tab` / `register_platform_hub_widget` spec: MTS sweeps registrations whose owning mod was removed on the next `on_configuration_changed`. Entries registered without a `mod` field persist indefinitely.

```lua
-- Register a Team Settings tab, then populate it when MTS builds it.
local function register_mts_ui()
    if not remote.interfaces["mts-v1"] then return end
    remote.call("mts-v1", "register_team_tab",
        { name = "my-mod", caption = "My Mod", order = "z", mod = "my-mod" })
end
script.on_init(register_mts_ui)
script.on_configuration_changed(register_mts_ui)

-- Fill the content frame each time the panel is (re)built (subscribe via the
-- deferred one-shot from §2.1).
local function on_tab_built(event)
    if event.tab_name ~= "my-mod" then return end
    event.element.add{ type = "label", caption = "Hello from my mod" }
end
```

### 2.5 Choosing between mirroring, events, and queries

| You want to…                                          | Use                                                      |
|-------------------------------------------------------|----------------------------------------------------------|
| Put the same terrain on every team's planet           | Nothing — mirroring handles it automatically             |
| Run per-surface setup once (not per-chunk)            | `on_team_surface_created` event                          |
| Grant starting items / research to each new team      | `on_team_created` event                                  |
| React when a player joins or leaves a team            | `on_player_joined_team` / `on_player_left_team`          |
| Check "is this a team surface?" inside another handler| `is_team_surface` query                                  |
| Walk all active teams (e.g. for a scoreboard)         | `get_team_list` query                                    |
| Add your own UI to Team Settings / welcome / hub      | `register_team_tab` / `register_welcome_tab` / `register_platform_hub_widget` + the matching `*_built` event |
| Announce your own per-team milestones                 | `register_milestone` + `report_milestone`                |

---

## 3. Mods added to an existing save

MTS makes one promise about timing, and it deliberately matches vanilla: **lifecycle events fire for every team and surface created from the moment the mod is installed onward.** A mod added mid-save takes effect on subsequently-created teams and surfaces, not retroactively on ones that already exist.

This is the same boundary Factorio itself enforces — adding a worldgen or decoration mod to a running save does not redecorate already-generated chunks. MTS does not promise more than the base game, and there is **no admin command** to force retroactive setup.

Why there's no retroactive mechanism:

- **It can't help the mods that need it most.** A handler that filters `surface.name == "nauvis"` rejects a re-fired event exactly as it rejects the live one — no event trick can spoof `LuaSurface.name`. Those mods need a real fix (generalize the filter, or subscribe to `on_team_surface_created`), not a replay.
- **Retroactive grants are wrong, not just unsafe.** Re-firing `on_team_created` against a team that's been playing for hours would dump a starting kit onto an established base. New teams get their setup live; existing teams correctly don't.

So: write your integration against the `mts-v1` events (§2) and it works for every team created while your mod is installed. If you need a mod's terrain on surfaces that predate its install, regenerate those surfaces (recycle the slot) — the same answer vanilla gives.

---

## 4. What MTS will not do

- **Reverse-engineer or monkey-patch closed-source mods.** Fragile, version-coupled, breaks silently when upstream updates.
- **Spoof `surface.name`.** Not technically possible, and would lie to every other mod on the server.
- **Maintain compat shims for every mod that decorates a planet.** The terrain mirror handles the chunk-gen layer generically. Per-mod shims exist only for runtime rules the upstream author hasn't yet exposed via predicate or remote interface, and they're treated as transitional — we'd rather delete them as upstream support lands.

---

## 5. Reporting integration issues

If you maintain a mod and want to flag a specific gap, open an issue at https://github.com/bits-orio/multi-team-support/issues with the mod name and a brief description of which handler isn't firing on team surfaces. If you're an admin trying to make a specific combo work, the mod combo plus what doesn't work is enough to triage.
