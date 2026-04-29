# Mod Compatibility Strategy

This document explains how Multi-Team Support (MTS) integrates with other mods, especially chunk-generation and surface-decorator mods that traditionally assume a single shared Nauvis. It's both a guide for **MTS admins** trying to make a third-party mod work on team surfaces, and a reference for **third-party mod authors** who want their mod to play well with MTS.

## The core problem

MTS gives every team its own copy of Nauvis (e.g. `team-3-nauvis` or, on Space Age, `mts-nauvis-3`). Mods that decorate Nauvis — dangOreus's ore flooding, VoidBlock's void terrain, terrain overhauls, resource modifiers — typically hook `on_chunk_generated` or `on_surface_created` and filter with:

```lua
if surface.name == "nauvis" then ... end
```

That filter rejects every team surface. The mod's logic only runs on the literal `"nauvis"` surface, which in MTS is usually unused or hidden.

There is no single trick that makes every such mod multi-surface aware. MTS uses three layers of strategy, ranked by how little work they require from third-party authors.

## Layer 1: Zero-cooperation — event replay

**Cost to other authors: nothing.** They don't need to know MTS exists.

When an admin installs a new chunk-gen mod on a save that already has team surfaces, the new mod's `on_init` runs but it never sees those surfaces. To trigger its setup retroactively, run:

```
/mts-replay
```

This re-fires `on_surface_created` (and the MTS-specific `on_team_surface_created`) for every existing team surface. To also re-fire `on_chunk_generated` for every existing chunk:

```
/mts-replay --chunks
```

`--chunks` is heavy (one event per chunk per surface) but is the right call if the new mod's logic lives in its `on_chunk_generated` handler.

### What replay can and cannot do

**Helps when** the mod's handler doesn't filter by hardcoded surface name — for example, mods keyed off `surface.planet`, off `map_gen_settings`, off prototypes, or off "any surface with biters". These act on whatever surface the event delivers.

**Does not help when** the mod's handler filters with `surface.name == "nauvis"`. The replayed event carries the real team surface, and `surface.name` is `"team-3-nauvis"`, not `"nauvis"`. There is no way to spoof `surface.name` from outside the mod — `LuaSurface` is not proxyable. For these mods you need Layer 2 or 3.

### When NOT to run replay

- **Right after a normal MTS-only update.** The mod ecosystem hasn't changed; replay would just double-fire handlers that already saw the surfaces. Reserve replay for "I just installed a new chunk-gen mod" situations.
- **If the new mod is already MTS-aware** (subscribes to `mts-v1`'s `on_team_surface_created`). Its setup is already running on every team surface; replay would double-apply it.
- **For mods whose setup is non-idempotent.** If their handler spawns entities or grants items per chunk, replay duplicates them. Test on a backup save first.

## Layer 2: Light cooperation — `mts-v1` remote interface

**Cost to other authors: ~5–25 lines of Lua. No source disclosure required.**

MTS exposes a public remote interface, `mts-v1`, with custom events and queries. Closed-source mod authors can subscribe without sharing code.

### Minimal — per-surface setup mods

Use this if your mod only needs to run a one-time setup function per surface (e.g. building a config table, registering a force entry, scheduling some state) and doesn't have a per-chunk handler:

```lua
script.on_init(function()
    if remote.interfaces["mts-v1"] then
        local id = remote.call("mts-v1", "get_event_id", "on_team_surface_created")
        script.on_event(id, function(event)
            -- event.surface_name, event.force_name
            local surface = game.surfaces[event.surface_name]
            my_mod.setup_surface(surface)  -- the function you already have
        end)
    end
end)
```

That's it. You don't touch your existing logic; you just add a second entry point that runs your existing setup function on each team surface.

### Chunk-gen mods (dangOreus-style)

Mods that decorate Nauvis chunks via `on_chunk_generated` need to address a second problem: their handler typically guards with `if surface.name == "nauvis"`, which rejects MTS team surfaces. The fix is a single shared predicate that's vanilla-correct, Space-Age-correct, and MTS-correct, used in *both* the per-surface setup path and the per-chunk decoration path:

```lua
-- "Is this one of the surfaces I should decorate?"
local function is_target_surface(surface)
    if not (surface and surface.valid) then return false end
    -- Preferred check: works for vanilla nauvis, modded nauvis-planet
    -- mods, and MTS Space Age team variants (mts-nauvis-N).
    if surface.planet and surface.planet.name == "nauvis" then
        return true
    end
    -- Non-Space-Age fallback: MTS clones surfaces named "team-N-nauvis".
    if remote.interfaces["mts-v1"]
       and remote.call("mts-v1", "is_team_surface", surface.name)
       and surface.name:find("nauvis") then
        return true
    end
    return false
end

-- Existing setup function — gated by the same predicate.
local function setup_surface(surface)
    if not is_target_surface(surface) then return end
    -- ... your existing setup_surface body, unchanged ...
end

-- Wire it up: native event for live surface creation, mts-v1 for any
-- team surfaces that already exist when this mod is loaded.
script.on_event(defines.events.on_surface_created, function(e)
    setup_surface(game.surfaces[e.surface_index])
end)

script.on_init(function()
    if remote.interfaces["mts-v1"] then
        local id = remote.call("mts-v1", "get_event_id", "on_team_surface_created")
        script.on_event(id, function(e)
            setup_surface(game.surfaces[e.surface_name])
        end)
    end
end)

-- Per-chunk handler: same predicate, no name hardcoding.
script.on_event(defines.events.on_chunk_generated, function(event)
    if not is_target_surface(event.surface) then return end
    -- ... your existing on_chunk_generated body, unchanged ...
end)
```

The point is that you maintain *one* predicate (`is_target_surface`) and thread it through every entry point. Your decoration logic stays exactly as it is. The only behavioral change is *which surfaces* trigger it — and that's now driven by what each surface actually is, not by a hardcoded name.

If your mod targets a planet other than Nauvis, swap the `surface.planet.name == "nauvis"` literal accordingly. The pattern works the same way for Vulcanus, Gleba, etc.

### Stateless chunk-gen mods (VoidBlock-style)

Some chunk-gen mods are *stateless per surface* — they only react to `on_chunk_generated`, set tiles based on the chunk's coordinates and the event payload, and never need a per-surface init. VoidBlock is the canonical example: each chunk gets a "void ocean" tile fill plus an "island" carve at the origin, with no surface-level config to track.

For mods like this you don't need to subscribe to `on_team_surface_created` at all. The minimum change is just the filter:

```lua
local function is_target_surface(surface)
    if not (surface and surface.valid) then return false end
    if surface.planet and surface.planet.name == "nauvis" then
        return true
    end
    -- Non-Space-Age fallback: MTS clones surfaces named "team-N-nauvis".
    if remote.interfaces["mts-v1"]
       and remote.call("mts-v1", "is_team_surface", surface.name)
       and surface.name:find("nauvis") then
        return true
    end
    return false
end

script.on_event(defines.events.on_chunk_generated, function(event)
    if not is_target_surface(event.surface) then return end
    -- ... your existing tile-fill / decoration body, unchanged ...
end)
```

That's the entire diff. No `on_init` block, no `on_team_surface_created` subscription, no second entry point. A stateless chunk-gen mod ports to MTS by replacing one `if surface.name == "nauvis"` line with the predicate above.

One caveat: stateless mods that need the surface to be *created with specific generation settings* (e.g. VoidBlock disables all autoplace controls so vanilla terrain doesn't appear before tiles are overwritten) can't enforce that on team surfaces themselves — MTS owns surface creation. MTS's compat shim for VoidBlock currently handles this by replicating those creation settings; the upstream-friendly fix is for MTS to expose creation hooks in a future `mts-v2`. For now, if your mod has hard requirements on `LuaSurface` creation parameters, file an issue and we'll work out a path together.

The full event and query catalog lives in [`scripts/remote_api.lua`](../scripts/remote_api.lua). The interface name is versioned (`mts-v1`); breaking changes will ship as a parallel `mts-v2` rather than mutating v1.

## Layer 3: Upstream — `surface.planet.name`

**Cost to other authors: 2 lines of Lua. Doesn't even mention MTS.**

This is the right long-term fix and the easiest pitch to a closed-source mod author, because it is framed as a generic correctness improvement rather than an MTS-specific accommodation.

Most chunk-gen mods filter their `on_chunk_generated` handler with:

```lua
if surface.name == "nauvis" then ... end
```

This is wrong even without MTS. In Factorio 2.0 with Space Age, modded planets ("Maraxsis", "Muluna", etc.) have surfaces whose `surface.name` is *not* `"nauvis"` but whose `surface.planet.name` is. The filter should be:

```lua
if surface.planet and surface.planet.name == "nauvis" then ... end
```

This is correct for vanilla Nauvis, correct for modded planets, correct for space platforms (whose `planet` is `nil`), and **correct for MTS team surfaces**, because each team's Nauvis variant carries `planet="nauvis"`. No MTS-specific code needed.

When pitching this change to a third-party author, frame it as: *"Your mod targets the Nauvis planet, not specifically the surface called 'nauvis'. Filtering by `surface.planet.name` makes the mod compatible with planet mods generally."* MTS compatibility is a free side effect.

## Strategy summary

| Layer | Tool                          | Cost to other author | Works for surface-name filters? |
| :---- | :---------------------------- | :------------------- | :------------------------------ |
| 1     | `/mts-replay` event replay    | Nothing              | No                              |
| 2     | `mts-v1` remote interface     | ~5 lines             | Yes                             |
| 3     | `surface.planet.name` upstream | ~2 lines             | Yes                             |

The layers stack. Run replay to catch what it can, file an upstream PR or feature request for what it can't, and document the remaining gaps.

## What MTS will *not* do

- **Reverse-engineer or monkey-patch closed-source mods.** The pattern is fragile, version-coupled, and breaks silently when the upstream mod updates. We use it nowhere in the codebase.
- **Spoof `surface.name`.** It's not technically possible, and even if it were, it would lie to every other mod on the server.
- **Bundle compat shims for arbitrary chunk-gen mods.** The repo currently carries shims for [`compat/dangoreus.lua`](../compat/dangoreus.lua) and [`compat/voidblock.lua`](../compat/voidblock.lua) because those mods are widely used and don't yet support multi-surface. Each shim is tracked as technical debt; the long-term plan is to delete them as upstream support lands.

## Reporting compat issues

If you maintain a chunk-gen or surface-modifying mod and want to integrate cleanly with MTS, open an issue at https://github.com/bits-orio/multi-team-support/issues and we'll help you pick the right layer. If you're an admin trying to make a specific combo work, the same applies — a brief description of what doesn't work plus the mod combo is enough to triage.
