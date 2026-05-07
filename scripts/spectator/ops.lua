-- scripts/spectator/ops.lua
-- Public spectation operations: enter, exit, switch, friend-view.

local helpers       = require("scripts.helpers")
local surface_utils = require("scripts.surface_utils")
local core          = require("scripts.spectator.core")

local M = {}

function M.enter(player, target_force, surface, position, target_player)
    log("[multi-team-support:spectator] enter: " .. player.name
        .. " → " .. target_force.name
        .. " on " .. surface.name
        .. " at " .. serpent.line(position))

    -- Save pre-spectate location. Use physical_position/surface because
    -- player.position is the camera position when already in map view.
    if not core.is_spectating(player) then
        storage.spectator_saved_location[player.index] = {
            surface_name    = player.physical_surface.name,
            position        = {x = player.physical_position.x, y = player.physical_position.y},
            controller_type = player.controller_type,
            -- hub is non-nil when the player is sitting in a space platform hub.
            -- enter_space_platform() is needed on exit to restore the pilot
            -- relationship (set_controller alone doesn't).
            was_in_hub      = player.hub ~= nil,
        }
    end

    helpers.diag("spectator.enter: BEFORE state changes", player)
    storage.spectating_target[player.index] = target_force.name
    core.apply_spectator_state(player)
    helpers.diag("spectator.enter: AFTER apply_spectator_state", player)
    core.open_remote_view(player, surface, position)
    helpers.diag("spectator.enter: AFTER open_remote_view", player)
    core.announce_spectation(player, target_force, true, target_player, surface)
    core.update_spectator_surfaces()

    log("[multi-team-support:spectator] enter: done, force=" .. player.force.name)
end

function M.exit(player)
    if not core.is_spectating(player) then return end
    log("[multi-team-support:spectator] exit: " .. player.name)
    helpers.diag("spectator.exit: BEFORE restore_player_state", player)

    local target_fn       = storage.spectating_target[player.index]
    local spectated_surface = player.surface  -- capture before force restore repoints it
    core.restore_player_state(player)
    helpers.diag("spectator.exit: AFTER restore_player_state", player)

    local saved = storage.spectator_saved_location[player.index]
    local target_surface, target_pos
    if saved then
        target_surface = game.surfaces[saved.surface_name]
        target_pos     = saved.position
    end
    if not target_surface then
        target_surface = surface_utils.get_home_surface(player.force, player.index)
        target_pos     = helpers.ORIGIN
    end

    if target_surface then
        -- Collision avoidance only for fallback origin — skip when restoring to
        -- saved pre-spectate position because the character is still there and
        -- find_non_colliding_position would treat it as a blocker and shift them.
        if not saved and player.character then
            local safe = target_surface.find_non_colliding_position(
                player.character.name, target_pos, 8, 0.5)
            target_pos = safe or target_pos
        end
        helpers.diag("spectator.exit: TELEPORT → " .. target_surface.name
            .. " at " .. string.format("(%.1f,%.1f)", target_pos.x, target_pos.y), player)
        player.teleport(target_pos, target_surface)

        -- Restore remote view when:
        --   1. Player was in remote view before spectating (e.g. sitting in a hub).
        --   2. Destination is a space platform (hub-view is the natural state there).
        local restore_remote = false
        if saved and saved.controller_type == defines.controllers.remote then
            restore_remote = true
        end
        if target_surface.platform then restore_remote = true end

        if restore_remote then
            -- Platform-bound remote (hub) vs position-based remote (planet variant).
            -- Use enter_space_platform when available — it restores the pilot
            -- relationship; set_controller alone only moves the camera.
            local platform = target_surface.platform
            local hub_entered = false
            if platform and platform.valid
               and (saved and saved.was_in_hub or target_surface.platform) then
                hub_entered = player.enter_space_platform(platform)
            end
            if not hub_entered then
                player.set_controller{
                    type     = defines.controllers.remote,
                    surface  = target_surface,
                    position = target_pos,
                }
            end
        end
    end
    storage.spectator_saved_location[player.index] = nil

    if target_fn then
        local target_force = game.forces[target_fn]
        if target_force then
            core.announce_spectation(player, target_force, false, nil, spectated_surface)
        end
    end

    core.clear_spectator_storage(player.index)
    core.update_spectator_surfaces()
    log("[multi-team-support:spectator] exit: done, force=" .. player.force.name)
end

function M.switch_target(player, target_force, surface, position, target_player)
    log("[multi-team-support:spectator] switch_target: " .. player.name
        .. " → " .. target_force.name .. " on " .. surface.name)
    storage.spectating_target[player.index] = target_force.name
    core.open_remote_view(player, surface, position)
    core.announce_spectation(player, target_force, true, target_player, surface)
    core.update_spectator_surfaces()
end

--- Like enter() but skips set_controller — used when the engine already moved
--- the player into remote view (GPS click, map click on a foreign surface).
function M.enter_from_remote(player, target_force, surface, position)
    log("[multi-team-support:spectator] enter_from_remote: " .. player.name
        .. " → " .. target_force.name
        .. " on " .. surface.name
        .. " at " .. serpent.line(position))

    if not core.is_spectating(player) then
        storage.spectator_saved_location[player.index] = {
            surface_name    = player.physical_surface.name,
            position        = {x = player.physical_position.x, y = player.physical_position.y},
            controller_type = player.controller_type,
            was_in_hub      = player.hub ~= nil,
        }
    end
    storage.spectating_target[player.index] = target_force.name
    core.apply_spectator_state(player)
    core.announce_spectation(player, target_force, true, nil, surface)
    core.update_spectator_surfaces()

    log("[multi-team-support:spectator] enter_from_remote: done, force=" .. player.force.name)
end

--- Open a friend-view: direct remote view without spectator force swap.
--- When target_force and target_player are both given, broadcasts the
--- announcement (follow-cam expand). Other callers suppress it.
function M.enter_friend_view(player, surface, position, target_force, target_player)
    log("[multi-team-support:spectator] enter_friend_view: " .. player.name
        .. " on " .. surface.name)
    -- Save pre-view location. Use physical_position/surface for the same
    -- reason as enter(): player.position is camera pos in map view.
    if not core.is_spectating(player)
       and not storage.spectator_saved_location[player.index] then
        storage.spectator_saved_location[player.index] = {
            surface_name    = player.physical_surface.name,
            position        = {x = player.physical_position.x, y = player.physical_position.y},
            controller_type = player.controller_type,
            was_in_hub      = player.hub ~= nil,
        }
    end
    core.open_remote_view(player, surface, position)
    if target_force and target_player then
        core.announce_spectation(player, target_force, true, target_player, surface)
    end
end

return M
