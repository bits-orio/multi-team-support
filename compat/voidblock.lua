-- Multi-Team Support - voidblock_compat.lua
-- Author: bits-orio
-- License: MIT
--
-- Support for VoidBlock mod. Similar to vanilla compat: each player spawns
-- on their own fresh copy of Nauvis generated from the same seed, but with
-- VoidBlock's void-island terrain applied (small island surrounded by void
-- ocean instead of normal terrain).
--
-- VoidBlock's own chunk generator only processes surfaces whose name matches
-- a planet name exactly (e.g. "nauvis"). Per-player surfaces are named
-- "<force_name>-<planet>" (e.g. "force-bob-nauvis"), so this module
-- replicates VoidBlock's terrain generation for those surfaces.
--
-- Surface naming & storage follow the same conventions as vanilla compat:
--   storage.player_surfaces[player_index] = {name = surface_name, planet = "nauvis"}

local compat_utils = require("compat.compat_utils")

local voidblock = {}

--- Character starting items for VoidBlock mode.
--- Edit this list to match VoidBlock's intended starting loadout.
voidblock.CHARACTER_STARTING_ITEMS = {
    {name = "iron-plate",          count = 8},
    {name = "wood",                count = 1},
    {name = "stone-furnace",       count = 1},
    {name = "burner-mining-drill", count = 1},
}

-- VoidBlock planet configuration for terrain generation.
-- Mirrored from VoidBlock's control.lua VOIDBLOCK.planets table.
-- Per-player surfaces are only created for nauvis; other planets are shared.
local PLANETS = {
    nauvis = { island = "grass-1", ocean = "s6x-voidocean" },
}

--- Returns true when VoidBlock compat should be used.
--- Active when VoidBlock is loaded and Platformer is NOT loaded.
function voidblock.is_active()
    return script.active_mods["VoidBlock"] ~= nil
       and script.active_mods["platformer"] == nil
end

voidblock.planet_display_name    = compat_utils.planet_display_name
voidblock.process_pending_teleports = compat_utils.process_pending_teleports

--- Create a personal Nauvis surface for `player` with no auto-generated
--- terrain. All tiles are placed by on_chunk_generated (void ocean + island)
--- so the player never sees pre-generated Nauvis terrain.
---
--- Teleport is deferred to the next tick via storage.pending_vanilla_tp.
function voidblock.setup_player_surface(player)
    compat_utils.setup_player_surface(player, function(surf_name)
        local surface = game.create_surface(surf_name, {
            default_enable_all_autoplace_controls = false,
            autoplace_settings = {
                entity     = { treat_missing_as_default = false, settings = {} },
                tile       = { treat_missing_as_default = false, settings = {} },
                decorative = { treat_missing_as_default = false, settings = {} },
            },
        })
        -- Pre-generate chunks around spawn so on_chunk_generated applies
        -- void-island terrain before the player arrives (next tick).
        surface.request_to_generate_chunks({0, 0}, 3)
        surface.force_generate_chunk_requests()

        -- Pre-claim the four chunks containing the starter island when
        -- gridlocked is loaded. The void-island spans radius 8 around
        -- origin, which straddles chunks (-1,-1), (-1,0), (0,-1), (0,0)
        -- — claiming all four matches the buildable starter area.
        --
        -- Without this, gridlocked deadlocks voidblock players: tile
        -- placement (including landfill) is forbidden on unclaimed
        -- chunks, but you can't easily chart enough to claim outward
        -- chunks without first expanding the island, and you can't
        -- expand without landfill. Destroying the gl-unclaimed-chunk
        -- entity at each chunk center fires gridlocked's
        -- on_object_destroyed handler, which clears its claim renders.
        --
        -- find_entity returns nil when gridlocked isn't loaded (no
        -- such entity exists), so the loop is a no-op for voidblock-
        -- only runs. No script.active_mods check needed.
        for _, pos in ipairs({{16, 16}, {-16, 16}, {16, -16}, {-16, -16}}) do
            local marker = surface.find_entity("gl-unclaimed-chunk", pos)
            if marker and marker.valid then marker.destroy() end
        end

        return surface
    end)
end

--- Get the VoidBlock planet config for a per-player surface, or nil.
--- Checks if the surface name ends with "-<planet>" and the prefix is a
--- valid player force.
local function get_planet_config(surface_name)
    for planet, config in pairs(PLANETS) do
        local suffix = "-" .. planet
        if surface_name:sub(-#suffix) == suffix then
            local prefix = surface_name:sub(1, -(#suffix + 1))
            if prefix:find("^team%-") and game.forces[prefix] then
                return config
            end
        end
    end
    return nil
end

--- Apply VoidBlock void-island terrain to per-player surfaces.
--- Replicates VoidBlock's vb_chunk_generator logic: tiles within radius ~8
--- from origin become island tiles, everything else becomes void ocean.
--- Should be called from on_chunk_generated.
function voidblock.on_chunk_generated(event)
    local surface = event.surface
    local pl = get_planet_config(surface.name)
    if not pl then return end

    local ttbl = {}
    local area = event.area

    for y = area.left_top.y, area.right_bottom.y - 1 do
        for x = area.left_top.x, area.right_bottom.x - 1 do
            local inserted = false

            if (x * x + y * y < 64) then
                table.insert(ttbl, {name = pl.island, position = {x, y}})
                inserted = true
            elseif pl.near_ocean then
                local current = surface.get_tile(x, y)
                if current then
                    if type(pl.near_ocean) == "table" then
                        if pl.near_ocean[current.name] then inserted = true end
                    else
                        if current.name == pl.near_ocean then
                            inserted = true
                        elseif pl.conv_near and current.prototype.name == pl.ocean then
                            table.insert(ttbl, {name = pl.near_ocean, position = {x, y}})
                            inserted = true
                        end
                    end
                end
            end

            if not inserted then
                table.insert(ttbl, {name = pl.ocean, position = {x, y}})
            end
        end
    end

    surface.set_tiles(ttbl)
    surface.destroy_decoratives({area = area})

    -- Clean up vanilla worldgen artifacts (trees, rocks, ores, biters,
    -- cliffs, fish) that survived the tile swap. Earlier versions of
    -- this code did `type = "character", invert = true` and destroyed
    -- everything else, which also wiped entities placed by other mods
    -- — for example gridlocked's `gl-unclaimed-chunk` markers, which
    -- were destroyed in the same tick they were placed. Allowlisting
    -- vanilla types preserves mod-placed entities while still clearing
    -- the terrain artifacts VoidBlock cares about.
    local leftover = surface.find_entities_filtered({
        type = {
            "tree", "simple-entity", "resource", "fish",
            "cliff", "unit-spawner", "turret", "unit",
        },
        area = area,
    })
    for _, ent in pairs(leftover) do
        if ent.valid then ent.destroy() end
    end
end

return voidblock
