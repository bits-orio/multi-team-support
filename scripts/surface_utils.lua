-- Multi-Team Support - surface_utils.lua
-- Author: bits-orio
-- License: MIT
--
-- Surface ownership queries, visibility management, and chart cleanup.
-- Extracted from spectator.lua — these are surface-level concerns, not
-- spectator-specific.

local helpers = require("scripts.helpers")

local surface_utils = {}

--- Given a surface, return the force name that owns it, or nil.
function surface_utils.get_owner(surface)
    if not surface or not surface.valid then return nil end

    -- Space platforms owned by team forces
    for _, force in pairs(game.forces) do
        if force.name:find("^team%-") then
            for _, plat in pairs(force.platforms) do
                if plat.surface and plat.surface.valid
                   and plat.surface.index == surface.index then
                    return force.name
                end
            end
        end
    end

    -- Space Age: per-team planet variants have their own surfaces named
    -- after the planet (e.g. "mts-nauvis-1"). The planet_map keeps a
    -- reverse lookup built at on_init.
    local by_planet = (storage.map_planet_to_force or {})[surface.name]
    if by_planet and game.forces[by_planet] then
        return by_planet
    end

    -- Fallback (non-Space-Age): cloned surfaces named "team-N-planet"
    local force_name = surface.name:match("^(team%-%d+)%-%w+$")
    if force_name and game.forces[force_name] then
        return force_name
    end

    return nil
end

--- Find a player's home surface, preferring their actual primary
--- surface (planet variant or cloned nauvis) over any incidental
--- space platform the team might own.
---
--- Lookup order:
---   1. storage.player_surfaces[player_index]: the surface the player
---      spawned on. This is their canonical home for vanilla, voidblock,
---      Space Age (mts-nauvis-N), and Platformer (platform-N) — every
---      mode populates this entry during setup_player_surface.
---   2. Space Age home planet variant via map_force_to_planets: covers
---      buddies who joined an existing team and don't have their own
---      player_surfaces entry but should land on the team's nauvis
---      variant.
---   3. Surface-name search for any surface owned by this force: another
---      buddy fallback for non-Space-Age modes.
---   4. Any space platform owned by the force: last-resort fallback for
---      the rare case where a team has launched a platform but somehow
---      has no other surface (e.g. all planet surfaces deleted, or a
---      legacy save state we didn't anticipate).
---
--- Why platforms are now last
--- ──────────────────────────
--- Earlier versions returned a space platform first if any existed.
--- That made sense for Platformer mode (where the platform IS the
--- primary base) but broke for Space Age: any team that had ever
--- launched a rocket would have "return to base" send the player to
--- the platform instead of their planet. The Platformer case is still
--- handled correctly by step 1, because Platformer's setup_player_surface
--- populates player_surfaces with the platform's surface name.
function surface_utils.get_home_surface(force, player_index)
    -- 1. Player's stored home surface (set during setup_player_surface
    -- in vanilla / voidblock / platformer / Space Age compat).
    local ps = storage.player_surfaces and storage.player_surfaces[player_index]
    if ps then
        local s = game.surfaces[ps.name]
        if s and s.valid then return s end
    end

    -- 2. Space Age home planet variant: handles buddies on a team
    -- whose player_surfaces entry was never populated.
    local map_entry = (storage.map_force_to_planets or {})[force.name]
    if map_entry and map_entry.nauvis then
        local s = game.surfaces[map_entry.nauvis]
        if s and s.valid then return s end
    end

    -- 3. Surface-name search for any surface owned by this force.
    -- Catches non-Space-Age buddy joins.
    for _, surface in pairs(game.surfaces) do
        if surface.valid and surface.name:find("^" .. force.name:gsub("%-", "%%-") .. "%-") then
            return surface
        end
    end

    -- 4. Last resort: any space platform owned by the force. Reached
    -- only when the team has no planet surface and no cloned surface
    -- but somehow has a platform — uncommon, but the original behavior
    -- did this so we keep it as a fallback to avoid regressions.
    for _, plat in pairs(force.platforms) do
        if plat.surface and plat.surface.valid then return plat.surface end
    end

    return nil
end

--- Update surface visibility between two forces based on friendship.
function surface_utils.update_visibility(force_a, force_b, are_friends)
    for _, surface in pairs(game.surfaces) do
        local owner = surface_utils.get_owner(surface)
        if owner == force_a.name then
            helpers.set_surface_hidden(force_b, surface, not are_friends)
        elseif owner == force_b.name then
            helpers.set_surface_hidden(force_a, surface, not are_friends)
        end
    end
end

--- Hide a newly created surface from non-owner, non-friend forces.
function surface_utils.on_surface_created(surface)
    local owner_fn    = surface_utils.get_owner(surface)
    if not owner_fn then return end
    local owner_force = game.forces[owner_fn]
    if not owner_force then return end

    for _, force in pairs(game.forces) do
        if force.name:find("^team%-") and force.name ~= owner_fn then
            local are_friends = force.get_friend(owner_force)
                and owner_force.get_friend(force)
            helpers.set_surface_hidden(force, surface, not are_friends)
        end
    end

    -- Hide from spectator force unless someone is actively spectating the owner.
    local spec = game.forces["spectator"]
    if spec then
        local spectated = false
        if storage.spectating_target then
            for _, target_fn in pairs(storage.spectating_target) do
                if target_fn == owner_fn then
                    spectated = true
                    break
                end
            end
        end
        helpers.set_surface_hidden(spec, surface, not spectated)
    end
end

--- Periodic chart cleanup: clears spectator force chart data for
--- surfaces with no active spectators.
function surface_utils.cleanup_charts()
    local spec = game.forces["spectator"]
    if not spec then return end

    local active_surfaces = {}
    for _, target_fn in pairs(storage.spectating_target) do
        local force = game.forces[target_fn]
        if force then
            for _, plat in pairs(force.platforms) do
                if plat.surface and plat.surface.valid then
                    active_surfaces[plat.surface.index] = true
                end
            end
        end
    end

    for _, surface in pairs(game.surfaces) do
        if not active_surfaces[surface.index] then
            local owner = surface_utils.get_owner(surface)
            if owner and owner ~= "spectator" then
                spec.clear_chart(surface)
            end
        end
    end

    log("[multi-team-support:spectator] cleanup_charts: cleared inactive surface charts")
end

return surface_utils
