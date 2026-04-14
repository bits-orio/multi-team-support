-- Multi-Team Support - compat_utils.lua
-- Author: bits-orio
-- License: MIT
--
-- Shared utilities for compat modules (vanilla, voidblock).
-- Extracts common logic: surface naming, teleport queue, display names,
-- and the setup_player_surface skeleton.

local helpers = require("helpers")

local compat_utils = {}

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
--- `create_surface_fn(surf_name, planet)` is called when the surface does
--- not yet exist and must return the newly created LuaSurface.
---
--- Teleport is deferred to the next tick via storage.pending_vanilla_tp so
--- it is safe to call from on_player_created before the character is ready.
function compat_utils.setup_player_surface(player, create_surface_fn)
    local planet    = "nauvis"
    local surf_name = player.force.name .. "-" .. planet

    local surface = game.surfaces[surf_name]
    if not surface then
        surface = create_surface_fn(surf_name, planet)
    end

    storage.player_surfaces = storage.player_surfaces or {}
    storage.player_surfaces[player.index] = {name = surf_name, planet = planet}

    storage.pending_vanilla_tp = storage.pending_vanilla_tp or {}
    storage.pending_vanilla_tp[player.index] = surface
end

return compat_utils
