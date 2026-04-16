-- Multi-Team Support - compat_utils.lua
-- Author: bits-orio
-- License: MIT
--
-- Shared utilities for compat modules (vanilla, voidblock).
-- Extracts common logic: surface naming, teleport queue, display names,
-- and the setup_player_surface skeleton.

local helpers    = require("helpers")
local space_age  = require("space_age")
local planet_map = require("planet_map")

local compat_utils = {}

--- Default character starting items for vanilla / VoidBlock modes.
--- Mirrors the Factorio freeplay starting loadout.
compat_utils.CHARACTER_STARTING_ITEMS = {
    {name = "iron-plate",          count = 8},
    {name = "wood",                count = 1},
    {name = "pistol",              count = 1},
    {name = "firearm-magazine",    count = 10},
    {name = "burner-mining-drill", count = 1},
    {name = "stone-furnace",       count = 1},
}

--- Capitalize first letter of planet name for display.
--- planet "nauvis" -> "Nauvis"
function compat_utils.planet_display_name(planet)
    return planet:sub(1, 1):upper() .. planet:sub(2)
end

--- Process queued surface teleports. Must be called from on_tick.
function compat_utils.process_pending_teleports()
    if not storage.pending_vanilla_tp then return end
    if not next(storage.pending_vanilla_tp) then return end
    for player_index, surface in pairs(storage.pending_vanilla_tp) do
        local player = game.get_player(player_index)
        if player and player.valid and surface and surface.valid then
            player.teleport(helpers.ORIGIN, surface)
        end
    end
    storage.pending_vanilla_tp = {}
end

--- Create a personal surface for `player` and queue a deferred teleport.
---
--- Surface selection:
---   - With Space Age: use the team's Nauvis variant planet (e.g. "mts-nauvis-1").
---     This leverages the Space Age solar system so platforms travel between
---     per-team planet variants correctly.
---   - Without Space Age: fall back to a cloned vanilla surface
---     named "<force>-<planet>" (e.g. "team-1-nauvis") created via create_surface_fn.
---
--- `create_surface_fn(surf_name, planet)` is the fallback creator, called
--- only when Space Age is inactive and no existing clone surface was found.
---
--- Teleport is deferred to the next tick via storage.pending_vanilla_tp so
--- it is safe to call from on_player_created before the character is ready.
function compat_utils.setup_player_surface(player, create_surface_fn)
    local planet_base = "nauvis"
    local surface
    local surf_name

    if space_age.is_active() then
        -- Use the team's Nauvis variant planet
        local variant = planet_map.get_home_planet(player.force.name)
        if variant then
            surface = planet_map.get_or_create_planet_surface(variant)
            surf_name = surface and surface.name or variant
        end
    end

    if not surface then
        -- Fallback: clone the base Nauvis surface under a team-scoped name
        surf_name = player.force.name .. "-" .. planet_base
        surface = game.surfaces[surf_name]
        if not surface then
            surface = create_surface_fn(surf_name, planet_base)
        end
    end

    storage.player_surfaces = storage.player_surfaces or {}
    storage.player_surfaces[player.index] = {name = surf_name, planet = planet_base}

    storage.pending_vanilla_tp = storage.pending_vanilla_tp or {}
    storage.pending_vanilla_tp[player.index] = surface
end

return compat_utils
