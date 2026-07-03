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
            -- The GUI spectate button fires before the view changes, so the
            -- live zoom is still the home zoom.
            zoom            = (function() local ok, z = pcall(function() return player.zoom end) return ok and z or nil end)(),
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
    local used_fallback = false
    if saved then
        target_surface = game.surfaces[saved.surface_name]
        target_pos     = saved.position
    end
    if not target_surface then
        target_surface = surface_utils.get_home_surface(player.force, player.index)
        target_pos     = helpers.ORIGIN
        used_fallback  = true
    end

    if target_surface then
        -- Collision avoidance only on the ORIGIN fallback (saved surface deleted or
        -- unresolved). Skip on the normal saved-position restore, where the
        -- character is still there and find_non_colliding_position would treat it
        -- as a blocker. (Was gated on `not saved`, but `saved` stays truthy even
        -- when saved.surface_name no longer resolves, so the fallback was skipped.)
        if used_fallback and player.character then
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

        local saved_zoom = saved and saved.zoom
        -- Whether we set the view's zoom ourselves. False when control was
        -- handed to enter_space_platform (hub view) — Platformer's normal
        -- return — where the hub owns its own zoom and we must not touch it.
        local applied_zoom = false
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
                -- The camera returns to where the map was looking (saved view
                -- position); the character already teleported to its physical
                -- spot above and stays there. Falls back to the physical spot.
                local cam_surface = (saved and saved.view_surface_name
                    and game.surfaces[saved.view_surface_name]) or target_surface
                local cam_pos = (saved and saved.view_position) or target_pos
                player.set_controller{
                    type     = defines.controllers.remote,
                    surface  = cam_surface,
                    position = cam_pos,
                }
                -- set_controller's start_zoom only seeds a transition, not the
                -- remote view's resting zoom (it opens at the engine default).
                -- Set the controller's zoom directly, like the physical path.
                if saved_zoom then
                    pcall(function() player.zoom = saved_zoom end)
                    applied_zoom = true
                end
            end
        elseif saved_zoom then
            -- Returned to the physical character view: restore its zoom too.
            pcall(function() player.zoom = saved_zoom end)
            applied_zoom = true
        end
        -- Re-apply a few ticks later: the controller change can reset zoom on
        -- the frame it settles, so one delayed write makes it stick. Only when
        -- we actually set the zoom (never over a hub view).
        if applied_zoom then
            storage.zoom_apply = storage.zoom_apply or {}
            storage.zoom_apply[player.index] = { at = game.tick + 4, zoom = saved_zoom }
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

--- Exit every player tied to a team whose slot is being disbanded/released:
--- members currently spectating AWAY (spectator_real_force == force_name), so
--- they are restored to their real force and counted/relocated by the disband
--- loop instead of being orphaned; and outside viewers spectating INTO the team
--- (spectating_target == force_name), so stale visibility doesn't carry onto the
--- recycled slot. M.exit restores force / view and refreshes visibility.
function M.exit_all_for_force(force_name)
    local reals   = storage.spectator_real_force or {}
    local targets = storage.spectating_target or {}
    -- Snapshot the indices first; M.exit mutates these tables as it clears state.
    local hits = {}
    for idx, real in pairs(reals) do
        if real == force_name or targets[idx] == force_name then hits[#hits + 1] = idx end
    end
    for _, idx in ipairs(hits) do
        local p = game.get_player(idx)
        if p and p.valid then M.exit(p) end
    end
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
--- original_controller_type is the controller the player was in BEFORE the
--- click. The click has already flipped player.controller_type to remote by
--- now, so reading it here would always record "remote" and exit would always
--- restore remote view; the caller supplies the real pre-click value so exit
--- restores physical view for a click made from the character.
function M.enter_from_remote(player, target_force, surface, position, original_controller_type)
    log("[multi-team-support:spectator] enter_from_remote: " .. player.name
        .. " → " .. target_force.name
        .. " on " .. surface.name
        .. " at " .. serpent.line(position))

    if not core.is_spectating(player) then
        -- For a click made from inside the map (remote controller), the camera
        -- should return to where it was looking, not the character's physical
        -- spot — use the polled map-view position (the GPS click already moved
        -- the camera off our base before we run).
        local rv = (original_controller_type == defines.controllers.remote)
            and storage.spectator_last_remote_view
            and storage.spectator_last_remote_view[player.index]
        storage.spectator_saved_location[player.index] = {
            surface_name      = player.physical_surface.name,
            position          = {x = player.physical_position.x, y = player.physical_position.y},
            controller_type   = original_controller_type or player.controller_type,
            was_in_hub        = player.hub ~= nil,
            -- The GPS click already flipped the zoom, so use the polled
            -- home-view value (core.track_home_zoom) rather than the live one.
            zoom              = (storage.spectator_last_zoom or {})[player.index],
            view_surface_name = rv and rv.surface_name or nil,
            view_position     = rv and rv.position or nil,
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
