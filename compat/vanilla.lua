-- Multi-Team Support - vanilla_compat.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- Support for vanilla-style games (no Platformer mod) where each player
-- spawns on their own fresh copy of the Nauvis surface generated from the
-- same seed as the shared Nauvis, giving everyone an identical starting world.
--
-- Surface naming: "<force_name>-<planet>" e.g. "force-bob-nauvis"
-- Using force name (not player name/index) so the surface is identifiable
-- by its owning force, which supports multi-player teams in the future.
--
-- storage.player_surfaces[player_index] = {name = surface_name, planet = "nauvis"}

local compat_utils = require("compat.compat_utils")

local vanilla = {}

--- Returns true when vanilla surface compat should be used.
--- Active whenever the Platformer mod is NOT loaded.
function vanilla.is_active()
    return script.active_mods["platformer"] == nil
end

vanilla.planet_display_name    = compat_utils.planet_display_name
vanilla.process_pending_teleports = compat_utils.process_pending_teleports

--- Create a personal Nauvis surface for `player` using the same map-gen
--- settings as the shared "nauvis" surface (same seed, fresh world state).
--- The surface will generate terrain identically to the original Nauvis but
--- is completely independent — only this player's force can see it.
---
--- Teleport is deferred to the next tick via storage.pending_vanilla_tp so
--- it is safe to call from on_player_created before the character is ready.
function vanilla.setup_player_surface(player)
    compat_utils.setup_player_surface(player, function(surf_name, planet)
        local nauvis = game.surfaces[planet]
        local mgs    = nauvis and nauvis.map_gen_settings or {}
        local surface = game.create_surface(surf_name, mgs)

        -- Pre-generate spawn-area chunks BEFORE the player teleports.
        -- clone_mirror.on_chunk_generated runs synchronously here for
        -- each generated chunk and calls LuaSurface.clone_area, which
        -- overwrites destination contents — including any character
        -- entity at the player's position. Doing the work up front
        -- means clone_area runs on an empty surface, so the player's
        -- character (placed during the deferred teleport on the next
        -- tick) lands on already-cloned terrain instead of being
        -- evicted by an in-flight clone.
        surface.request_to_generate_chunks({0, 0}, 3)
        surface.force_generate_chunk_requests()

        return surface
    end)
end

return vanilla
