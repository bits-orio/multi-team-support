-- scripts/spectator/events.lua
-- Spectator event handlers and chat prefix helper.

local helpers       = require("scripts.helpers")
local surface_utils = require("scripts.surface_utils")
local core          = require("scripts.spectator.core")
local ops           = require("scripts.spectator.ops")

local M = {}

-- ─── Friendship Up/Downgrade ───────────────────────────────────────────

local function upgrade_to_friend_view(p, idx)
    core.restore_player_state(p)
    core.clear_spectator_storage(idx)
    core.update_spectator_surfaces()
    -- crafting_queue_size errors when no crafting queue exists; guard on character.
    if p.character and p.crafting_queue_size > 0 then
        p.print("[multi-team-support] You are now viewing as a friend. Crafting resumed.")
    else
        p.print("[multi-team-support] You are now viewing as a friend.")
    end
    log("[multi-team-support:spectator] upgraded " .. p.name .. " from spectator to friend-view")
end

local function downgrade_to_spectator(p, player_force)
    log("[multi-team-support:spectator] downgrading " .. p.name
        .. " from friend-view to spectator (unfriended)")
    storage.spectating_target[p.index] = player_force.name
    core.apply_spectator_state(p)
    core.update_spectator_surfaces()
    local unfriender = helpers.display_name(player_force.name)
    -- Same crafting_queue_size guard as upgrade_to_friend_view.
    if p.character and p.crafting_queue_size > 0 then
        p.print("[multi-team-support] " .. unfriender
            .. " unfriended you. Now spectating (crafting paused).")
    else
        p.print("[multi-team-support] " .. unfriender .. " unfriended you. Now spectating.")
    end
end

-- ─── Event Handlers ────────────────────────────────────────────────────

--- Detects GPS/map-click entry into remote view on a foreign surface and
--- wraps the player in spectate mode; also detects remote-view exit.
function M.on_controller_changed(player, old_controller_type)
    -- Case 1: Player entered remote view on a foreign surface.
    if player.controller_type == defines.controllers.remote
       and old_controller_type ~= defines.controllers.remote
       and not core.is_spectating(player) then
        local surface = player.surface
        local owner   = surface_utils.get_owner(surface)
        if owner then
            local viewer_force = game.forces[core.get_effective_force(player)]
            local target_force = game.forces[owner]
            if viewer_force and target_force and viewer_force ~= target_force then
                local position = player.position
                if core.needs_spectator_mode(viewer_force, target_force) then
                    ops.enter_from_remote(player, target_force, surface, position)
                else
                    ops.enter_friend_view(player, surface, position)
                end
            end
        end
        return
    end

    -- Case 2: Player exited remote view while spectating.
    if old_controller_type == defines.controllers.remote
       and player.controller_type ~= defines.controllers.remote
       and core.is_spectating(player) then
        log("[multi-team-support:spectator] on_controller_changed: " .. player.name
            .. " exited remote view, restoring force")
        ops.exit(player)
    end
end

--- Auto-exit when the spectated camera moves off the target's surfaces.
--- Handles the case where pressing Escape in a spectator session reverts
--- the camera to the player's own physical surface without firing
--- on_player_controller_changed, leaving them stuck in spectator mode.
function M.on_player_changed_surface(player)
    if not (player and player.valid) then return end
    if not core.is_spectating(player) then return end

    local target_force_name = storage.spectating_target[player.index]
    if not target_force_name then return end

    local owner = surface_utils.get_owner(player.surface)
    if owner == target_force_name then return end

    log("[multi-team-support:spectator] on_player_changed_surface: "
        .. player.name .. " camera left target force territory ("
        .. target_force_name .. " → "
        .. (owner or "<unowned>")
        .. " on " .. player.surface.name .. "), auto-exiting spectator")
    ops.exit(player)
end

--- Handle friendship changes for active spectators/friend-viewers.
function M.on_friend_changed(player_force, target_force, is_friend)
    log("[multi-team-support:spectator] on_friend_changed: "
        .. player_force.name .. (is_friend and " friended " or " unfriended ")
        .. target_force.name)

    if is_friend then
        for idx, spectated_fn in pairs(storage.spectating_target) do
            if spectated_fn == player_force.name
               and storage.spectator_real_force[idx] == target_force.name then
                local p = game.get_player(idx)
                if p and p.connected then upgrade_to_friend_view(p, idx) end
            end
        end
    else
        for _, p in pairs(target_force.connected_players) do
            if p.controller_type == defines.controllers.remote then
                local owner = surface_utils.get_owner(p.surface)
                if owner == player_force.name then
                    downgrade_to_spectator(p, player_force)
                end
            end
        end
    end
end

function M.on_player_left(player)
    if not core.is_spectating(player) then return end
    log("[multi-team-support:spectator] on_player_left: restoring " .. player.name)
    core.restore_player_state(player)
    core.clear_spectator_storage(player.index)
    core.update_spectator_surfaces()
end

function M.on_player_joined(player)
    local real_fn = storage.spectator_real_force[player.index]

    if real_fn then
        local was_on_spectator = (player.force.name == "spectator")
        core.restore_player_state(player)
        core.clear_spectator_storage(player.index)
        core.update_spectator_surfaces()
        if was_on_spectator then
            log("[multi-team-support:spectator] on_player_joined: restored " .. player.name
                .. " from spectator force")
        else
            log("[multi-team-support:spectator] on_player_joined: cleaned stale storage for "
                .. player.name)
        end
        return
    end

    -- Defensive cleanup: fix leftover spectator permission group or negative
    -- crafting modifier from a previous session where storage was cleared
    -- without restoring state.
    if player.force.name ~= "spectator" then
        local pg = player.permission_group
        if pg and pg.name == "spectator" then
            local default_group = game.permissions.get_group("Default")
            if default_group then default_group.add_player(player) end
            log("[multi-team-support:spectator] on_player_joined: fixed leftover spectator"
                .. " permission group for " .. player.name)
        end
        if player.character and player.character_crafting_speed_modifier < 0 then
            player.character_crafting_speed_modifier = 0
            log("[multi-team-support:spectator] on_player_joined: reset negative crafting"
                .. " modifier for " .. player.name)
        end
    end
end

-- ─── Chat ──────────────────────────────────────────────────────────────

function M.get_chat_prefix(player)
    local target_fn = core.get_target(player)
    if target_fn then
        return "[on " .. helpers.display_name(target_fn) .. "'s base][spectator] "
    end
    if player.controller_type == defines.controllers.remote then
        local owner = surface_utils.get_owner(player.surface)
        if owner and owner ~= player.force.name then
            return "[on " .. helpers.display_name(owner) .. "'s base][friend] "
        end
    end
    return ""
end

return M
