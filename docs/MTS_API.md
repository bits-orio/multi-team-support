# Multi-Team Support: Integration API

This document covers MTS-specific integration points: how MTS handles third-party chunk-gen mods automatically, the public `mts-v1` remote interface (events + queries), and the `/mts-replay` admin command for retroactive setup.

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

Event IDs are generated per session via `script.generate_event_name()` — they're stable for the duration of a session but not across sessions, so always look them up via `get_event_id` rather than caching the integer.

**Subscribing:**

```lua
-- in your control.lua's on_init AND on_load (events must be registered both)
local function register_mts_events()
    if not remote.interfaces["mts-v1"] then return end
    local id = remote.call("mts-v1", "get_event_id", "on_team_surface_created")
    script.on_event(id, function(event)
        -- event.surface_name, event.force_name
        local surface = game.surfaces[event.surface_name]
        if surface then my_mod.setup_surface(surface, event.force_name) end
    end)
end

script.on_init(register_mts_events)
script.on_load(register_mts_events)
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

A `team_info` table has the following shape:

```lua
{
    force_name           = "team-3",
    display_name         = "The Reds",     -- player-chosen name, or force_name
    status               = "occupied",      -- "occupied" | "available" | "released"
    is_occupied          = true,
    leader_player_index  = 7,
    member_count         = 4,
    is_paused            = false,
    clock_start_tick     = 1234,            -- when the team's clock started
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

### 2.3 Choosing between mirroring, events, and queries

| You want to…                                          | Use                                                      |
|-------------------------------------------------------|----------------------------------------------------------|
| Put the same terrain on every team's planet           | Nothing — mirroring handles it automatically             |
| Run per-surface setup once (not per-chunk)            | `on_team_surface_created` event                          |
| Grant starting items / research to each new team      | `on_team_created` event                                  |
| React when a player joins or leaves a team            | `on_player_joined_team` / `on_player_left_team`          |
| Check "is this a team surface?" inside another handler| `is_team_surface` query                                  |
| Walk all active teams (e.g. for a scoreboard)         | `get_team_list` query                                    |

---

## 3. Retroactive setup: `/mts-replay`

Installing a new chunk-gen or surface-decorating mod into a save that already has team surfaces creates a chicken-and-egg problem: the new mod's `on_init` runs, but its `on_chunk_generated` / `on_surface_created` handlers never see the *existing* team surfaces — those events already fired long ago.

`/mts-replay` (admin only) re-fires lifecycle events against the existing team surfaces so the new mod's handlers get a second chance:

```
/mts-replay              -- re-fires on_surface_created on every team surface
/mts-replay --chunks     -- additionally re-fires on_chunk_generated for every existing chunk
```

The `--chunks` form is much heavier (it's O(chunks generated) per team), but it's the right option for mods whose decoration runs in `on_chunk_generated` rather than `on_surface_created`.

**Limit of the technique:** replay only helps mods whose handlers actually do something useful when delivered the event. A mod that filters by `surface.name == "nauvis"` will reject the replayed event the same way it rejects the natural one — no event trick can spoof `LuaSurface.name`. For mods that filter hard, fix the filter (Pattern 5 in COMPAT.md) or subscribe to `on_team_surface_created` directly.

Implementation: [`scripts/event_replay.lua`](../scripts/event_replay.lua).

---

## 4. What MTS will not do

- **Reverse-engineer or monkey-patch closed-source mods.** Fragile, version-coupled, breaks silently when upstream updates.
- **Spoof `surface.name`.** Not technically possible, and would lie to every other mod on the server.
- **Maintain compat shims for every mod that decorates a planet.** The terrain mirror handles the chunk-gen layer generically. Per-mod shims exist only for runtime rules the upstream author hasn't yet exposed via predicate or remote interface, and they're treated as transitional — we'd rather delete them as upstream support lands.

---

## 5. Reporting integration issues

If you maintain a mod and want to flag a specific gap, open an issue at https://github.com/bits-orio/multi-team-support/issues with the mod name and a brief description of which handler isn't firing on team surfaces. If you're an admin trying to make a specific combo work, the mod combo plus what doesn't work is enough to triage.
