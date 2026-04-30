# Mod Compatibility Strategy

This is the short version of how Multi-Team Support (MTS) integrates with other mods, especially mods that decorate Nauvis or modify worldgen. Audience: third-party mod authors checking whether they need to do anything for MTS, and MTS admins triaging combos that misbehave.

## The default: it just works

MTS gives every team its own copy of Nauvis (`team-N-nauvis` or, on Space Age, `mts-nauvis-N`). When a chunk is generated on any team surface, MTS automatically:

1. Generates the matching chunk on the real `nauvis` surface, synchronously firing every third-party mod's `on_chunk_generated` handler. Their `surface.name == "nauvis"` filters accept, their decoration runs.
2. Clones the resulting tiles, entities, and decoratives from `nauvis` to the team surface via `LuaSurface.clone_area`.

The mechanism lives in [`compat/clone_mirror.lua`](../compat/clone_mirror.lua). Net effect: whatever your mod puts on `nauvis`, every team surface gets the same. No remote interface to wire up, no surface-name predicate to update, no MTS-aware code path.

**Verified working with:** [dangOreus](https://mods.factorio.com/mod/dangOreus), [VoidBlock](https://mods.factorio.com/mod/VoidBlock), [Alien Biomes](https://mods.factorio.com/mod/alien-biomes), [Periodic Madness](https://mods.factorio.com/mod/periodic-madness), and the vanilla worldgen stack.

## When the default isn't enough: runtime gameplay rules

Some mods don't only decorate chunks at generation time. They also have rules that fire *after*, e.g.:

- "Block non-miner buildings from being placed on ore tiles" (`on_built_entity`).
- "Spill container contents when a chest is destroyed" (`on_entity_died`).
- "Damage players standing on certain tiles" (`on_nth_tick`).

If those handlers filter by `surface.name == "nauvis"`, they silently no-op on team surfaces. clone_mirror gives you the *map*; it doesn't make these runtime rules fire on the cloned terrain.

Three ways to fix this, ranked by author effort:

### 1. Use `surface.planet.name` instead of `surface.name` (~2 lines)

The smallest and most generic option. Replace this:

```lua
if surface.name == "nauvis" then ... end
```

with:

```lua
if surface.planet and surface.planet.name == "nauvis" then ... end
```

This is correct for vanilla Nauvis, modded planet variants (Maraxsis, Muluna, etc.), MTS team surfaces (each team's Nauvis variant carries `planet="nauvis"`), and skips space platforms (whose `planet` is nil). It's a generic correctness improvement that benefits planet mods even without MTS in the picture. Frame it that way when pitching it.

Use this when: your runtime rule is naturally expressible as "act on this kind of planet."

### 2. Expose your runtime rules as `remote` functions (~10–30 lines)

The cleanest option for runtime rules that don't fit a planet predicate (e.g. spill-on-death — there's no surface check that captures "spill the contents"). Refactor your handler body into a named function and expose it:

```lua
-- Your existing handler, lightly refactored:
local function apply_no_build_rule(entity)
    -- existing body
end

script.on_event(defines.events.on_built_entity, function(event)
    local entity = event.created_entity or event.entity
    if entity.surface.name ~= "nauvis" then return end
    apply_no_build_rule(entity)
end)

-- Expose for multi-surface mods to reuse:
remote.add_interface("your_mod_name", {
    apply_no_build_rule = apply_no_build_rule,
    apply_container_spill = apply_container_spill,
    apply_floor_is_lava = apply_floor_is_lava,
})
```

That's it. Your existing behavior is untouched. MTS (and any other multi-surface mod, like Cargo Ships) can now invoke your runtime rule on its own surfaces:

```lua
-- In MTS's compat shim:
if remote.interfaces["your_mod_name"] then
    remote.call("your_mod_name", "apply_no_build_rule", entity)
end
```

Use this when: your rule is genuinely behavioral (not a simple predicate) and you'd like multi-surface mods to reuse your exact logic without re-implementing it. Closed-source-friendly: you're exposing your existing logic, not sharing code.

### 3. Subscribe to `mts-v1` events (~5 lines)

The most explicit option, for cases where you want MTS-specific awareness (e.g. "do per-team setup when a team is created"):

```lua
script.on_init(function()
    if remote.interfaces["mts-v1"] then
        local id = remote.call("mts-v1", "get_event_id", "on_team_surface_created")
        script.on_event(id, function(event)
            -- event.surface_name, event.force_name
            my_mod.setup_surface(game.surfaces[event.surface_name])
        end)
    end
end)
```

The full event and query catalog lives in [`scripts/remote_api.lua`](../scripts/remote_api.lua). Versioned (`mts-v1`); breaking changes ship as a parallel `mts-v2` rather than mutating v1.

Use this when: you want first-class awareness of MTS lifecycle (team created, team released, player joined team), or your setup needs to run exactly once per team rather than per-chunk.

## Retroactive compat: `/mts-replay`

If you install a new chunk-gen mod into a save that already has team surfaces, that mod's `on_init` runs but it never sees the existing surfaces. Run `/mts-replay` (admin only) to re-fire `on_surface_created` (and optionally `on_chunk_generated` per existing chunk via `--chunks`) on every team surface. The new mod's handlers get the chance to set up retroactively.

Replay only helps mods whose handlers actually do something useful when delivered the event. Mods that filter by `surface.name == "nauvis"` will reject the replayed event the same way they reject the natural one — no event trick can spoof `LuaSurface.name`. For those mods you need option 1 or 2 above (or accept that they don't apply to team surfaces).

## What MTS will not do

- **Reverse-engineer or monkey-patch closed-source mods.** Fragile, version-coupled, breaks silently when upstream updates.
- **Spoof `surface.name`.** Not technically possible, and would lie to every other mod on the server.
- **Maintain compat shims for every mod that decorates Nauvis.** clone_mirror handles the chunk-gen layer generically. Per-mod shims exist only for runtime rules that the upstream author hasn't yet exposed via predicate or remote interface (and we'd rather delete them as upstream support lands).

## Reporting compat issues

If you maintain a mod and want to flag a specific gap, open an issue at https://github.com/bits-orio/multi-team-support/issues with the mod name and a brief description of which handler isn't firing on team surfaces. If you're an admin trying to make a specific combo work, the mod combo plus what doesn't work is enough to triage.
