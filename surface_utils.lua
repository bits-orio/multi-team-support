-- Multi-Team Support - surface_utils.lua
-- Author: bits-orio
-- License: MIT
--
-- Surface ownership queries, visibility management, and chart cleanup.
-- Extracted from spectator.lua — these are surface-level concerns, not
-- spectator-specific.

local surface_utils = {}

--- Given a surface, return the force name that owns it, or nil.
function surface_utils.get_owner(surface)
    if not surface or not surface.valid then return nil end

    -- Space platforms
    for _, force in pairs(game.forces) do
        if force.name:find("^player%-") then
            for _, plat in pairs(force.platforms) do
                if plat.surface and plat.surface.valid
                   and plat.surface.index == surface.index then
                    return force.name
                end
            end
        end
    end

    -- Vanilla per-player surfaces: "<force_name>-<planet>" e.g. "player-bob-nauvis"
    local force_name = surface.name:match("^(player%-.+)%-%w+$")
    if force_name and game.forces[force_name] then
        return force_name
    end

    return nil
end

--- Find a player's home surface: first space platform, then vanilla surface.
--- Accepts a force object (the player's effective force).
function surface_utils.get_home_surface(force, player_index)
    for _, plat in pairs(force.platforms) do
        if plat.surface and plat.surface.valid then return plat.surface end
    end
    local ps = storage.player_surfaces and storage.player_surfaces[player_index]
    if ps then
        local s = game.surfaces[ps.name]
        if s and s.valid then return s end
    end
    return nil
end

--- Update surface visibility between two forces based on friendship.
function surface_utils.update_visibility(force_a, force_b, are_friends)
    for _, surface in pairs(game.surfaces) do
        local owner = surface_utils.get_owner(surface)
        if owner == force_a.name then
            force_b.set_surface_hidden(surface, not are_friends)
        elseif owner == force_b.name then
            force_a.set_surface_hidden(surface, not are_friends)
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
        if force.name:find("^player%-") and force.name ~= owner_fn then
            local are_friends = force.get_friend(owner_force)
                and owner_force.get_friend(force)
            force.set_surface_hidden(surface, not are_friends)
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
        spec.set_surface_hidden(surface, not spectated)
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
