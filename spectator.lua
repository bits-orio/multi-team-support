-- Multi-Team Support - spectator.lua
-- Author: bits-orio
-- License: MIT
--
-- Spectator system: allows players to view other players' surfaces by
-- temporarily swapping to a dedicated spectator force that is friends
-- with all player forces (share_chart = true). A permission group
-- prevents any interaction beyond viewing and chatting.
--
-- Players whose target has friended them get a direct "friend view"
-- instead (no force swap needed — friendship grants chart access).

local admin_gui     = require("gui.admin")
local helpers       = require("helpers")
local surface_utils = require("surface_utils")

local spectator = {}

-- ─── Internal Helpers ──────────────────────────────────────────────────

--- Move a player onto the spectator force and freeze their character.
--- Saves real force, crafting speed modifier, and hides map icon.
local function apply_spectator_state(player)
    if not spectator.is_spectating(player) then
        storage.spectator_real_force[player.index] = player.force.name
    end
    player.force = game.forces["spectator"]
    game.permissions.get_group("spectator").add_player(player)
    if player.character then
        storage.spectator_saved_craft_mod[player.index] =
            player.character_crafting_speed_modifier
        player.character_crafting_speed_modifier = -1
    end
    player.show_on_map = false
end

--- Restore a player from spectator force to their real force.
--- Resumes crafting, re-enables character, restores map icon.
--- Does NOT clear spectator storage — caller must do that.
local function restore_player_state(player)
    local real_fn    = storage.spectator_real_force[player.index]
    local real_force = real_fn and game.forces[real_fn]
    if real_force then
        player.force = real_force
    end
    local default_group = game.permissions.get_group("Default")
    if default_group then default_group.add_player(player) end
    if player.character then
        local saved = storage.spectator_saved_craft_mod[player.index]
        player.character_crafting_speed_modifier = saved or 0
    end
    storage.spectator_saved_craft_mod[player.index] = nil
    player.show_on_map = true
end

--- Clear all spectator storage entries for a player index.
local function clear_spectator_storage(idx)
    storage.spectator_real_force[idx]      = nil
    storage.spectating_target[idx]         = nil
    storage.spectator_saved_craft_mod[idx] = nil
    storage.spectator_saved_location[idx]  = nil
end

--- Announce spectation start/stop to all players (if notifications enabled).
local function announce_spectation(viewer, target_force, is_entering)
    if not admin_gui.flag("spectate_notifications_enabled") then return end

    local target_name = helpers.display_name(target_force.name)
    local action      = is_entering and "is now spectating" or "stopped spectating"
    local target_color = helpers.force_color(target_force)

    local msg = helpers.colored_name(viewer.name, viewer.chat_color)
        .. " " .. action .. " "
        .. helpers.colored_name(target_name, target_color)

    helpers.broadcast(msg)
    log("[multi-team-support:spectator] announcement: " .. viewer.name .. " " .. action
        .. " " .. target_name)
end

--- Open a remote view on a target surface.
local function open_remote_view(player, surface, position)
    player.set_controller({
        type     = defines.controllers.remote,
        surface  = surface,
        position = position,
    })
end

-- ─── Setup ─────────────────────────────────────────────────────────────

-- Actions the spectator permission group should allow (from Biter Battles).
local SPECTATOR_ALLOWED_ACTIONS = {
    "admin_action",
    "change_active_item_group_for_filters",
    "change_active_quick_bar",
    "change_multiplayer_config",
    "clear_cursor",
    "edit_permission_group",
    "gui_checked_state_changed",
    "gui_click",
    "gui_confirmed",
    "gui_elem_changed",
    "gui_location_changed",
    "gui_selected_tab_changed",
    "gui_selection_state_changed",
    "gui_switch_state_changed",
    "gui_text_changed",
    "gui_value_changed",
    "map_editor_action",
    "open_character_gui",
    "quick_bar_set_selected_page",
    "quick_bar_set_slot",
    "remote_view_surface",
    "set_filter",
    "set_player_color",
    "spawn_item",
    "start_walking",
    "toggle_map_editor",
    "toggle_show_entity_info",
    "write_to_console",
}

--- Create or update the spectator permission group.
local function setup_permission_group()
    local p = game.permissions.get_group("spectator")
    if not p then
        p = game.permissions.create_group("spectator")
    end
    for _, action_id in pairs(defines.input_action) do
        p.set_allows_action(action_id, false)
    end
    for _, name in ipairs(SPECTATOR_ALLOWED_ACTIONS) do
        local action = defines.input_action[name]
        if action then p.set_allows_action(action, true) end
    end
end

--- Create the spectator force, permission group, and ensure all existing
--- player forces have the correct friendship/cease-fire/share_chart.
function spectator.init()
    log("[multi-team-support:spectator] init: starting")

    local spec = game.forces["spectator"]
    if not spec then
        spec = game.create_force("spectator")
        log("[multi-team-support:spectator] init: created spectator force")
    end
    -- Spectator force must NOT share its chart — it accumulates everyone's
    -- chart data and sharing it back would leak all surfaces to all players.
    spec.share_chart = false

    for _, force in pairs(game.forces) do
        if force.name:find("^player%-") then
            spec.set_friend(force, true)
            force.set_friend(spec, true)
            force.share_chart = true
        end
        if force.name ~= "enemy" and force ~= spec then
            spec.set_cease_fire(force, true)
            force.set_cease_fire(spec, true)
        end
    end

    spec.technologies["toolbelt"].researched          = true
    spec.technologies["logistic-robotics"].researched = true

    setup_permission_group()
    log("[multi-team-support:spectator] init: complete, permission group configured")
end

--- Set up bidirectional friendship + cease-fire between a new player force
--- and the spectator force. Also hides all existing player surfaces.
function spectator.setup_force(new_force)
    new_force.share_chart = true
    local spec = game.forces["spectator"]
    if spec then
        new_force.set_friend(spec, true)
        spec.set_friend(new_force, true)
        spec.set_cease_fire(new_force, true)
        new_force.set_cease_fire(spec, true)
    end

    for _, surface in pairs(game.surfaces) do
        local owner = surface_utils.get_owner(surface)
        if owner and owner ~= new_force.name then
            new_force.set_surface_hidden(surface, true)
        end
    end

    log("[multi-team-support:spectator] setup_force: " .. new_force.name)
end

--- Ensure storage tables exist.
function spectator.init_storage()
    storage.spectator_real_force      = storage.spectator_real_force      or {}
    storage.spectating_target         = storage.spectating_target         or {}
    storage.spectator_saved_craft_mod = storage.spectator_saved_craft_mod or {}
    storage.spectator_saved_location  = storage.spectator_saved_location  or {}
    storage.friend_intents            = storage.friend_intents            or {}
end

-- ─── State Queries ─────────────────────────────────────────────────────

function spectator.is_spectating(player)
    return storage.spectator_real_force[player.index] ~= nil
end

function spectator.get_real_force(player)
    return storage.spectator_real_force[player.index]
end

function spectator.get_effective_force(player)
    return storage.spectator_real_force[player.index] or player.force.name
end

function spectator.get_target(player)
    return storage.spectating_target and storage.spectating_target[player.index]
end

function spectator.needs_spectator_mode(viewer_force, target_force)
    return not target_force.get_friend(viewer_force)
end

-- ─── Core Operations ───────────────────────────────────────────────────

--- Begin spectating a target force's surface.
function spectator.enter(player, target_force, surface, position)
    log("[multi-team-support:spectator] enter: " .. player.name
        .. " → " .. target_force.name
        .. " on " .. surface.name
        .. " at " .. serpent.line(position))

    -- Save pre-spectate location for restoring on exit.
    -- Use physical_position/physical_surface: player.position and player.surface
    -- reflect the remote-view camera when the player is in map view, which
    -- would restore them to the wrong place on exit.
    if not spectator.is_spectating(player) then
        storage.spectator_saved_location[player.index] = {
            surface_name = player.physical_surface.name,
            position     = {x = player.physical_position.x, y = player.physical_position.y},
        }
    end

    storage.spectating_target[player.index] = target_force.name
    apply_spectator_state(player)
    open_remote_view(player, surface, position)
    announce_spectation(player, target_force, true)

    log("[multi-team-support:spectator] enter: done, force=" .. player.force.name)
end

--- Stop spectating. Safe to call if not spectating (no-ops).
--- Always teleports the player home to prevent stranding on foreign surfaces
--- (especially in God mode where there's no character anchor).
function spectator.exit(player)
    if not spectator.is_spectating(player) then return end
    log("[multi-team-support:spectator] exit: " .. player.name)

    local target_fn = storage.spectating_target[player.index]
    restore_player_state(player)

    -- Restore to saved location, or fall back to home surface origin.
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
        -- Collision avoidance only for the fallback origin: bots could have built
        -- there while the player was spectating. Skipped when restoring to the
        -- saved pre-spectate position because the character is still standing
        -- there — find_non_colliding_position would see the character itself as
        -- a blocker and return an offset position, shifting the player by ~1 tile.
        if not saved and player.character then
            local safe = target_surface.find_non_colliding_position(
                player.character.name, target_pos, 8, 0.5)
            target_pos = safe or target_pos
        end
        player.teleport(target_pos, target_surface)
    end
    storage.spectator_saved_location[player.index] = nil

    if target_fn then
        local target_force = game.forces[target_fn]
        if target_force then announce_spectation(player, target_force, false) end
    end

    clear_spectator_storage(player.index)
    log("[multi-team-support:spectator] exit: done, force=" .. player.force.name)
end

--- Switch spectation target without leaving spectator force.
function spectator.switch_target(player, target_force, surface, position)
    log("[multi-team-support:spectator] switch_target: " .. player.name
        .. " → " .. target_force.name .. " on " .. surface.name)

    storage.spectating_target[player.index] = target_force.name
    open_remote_view(player, surface, position)
    announce_spectation(player, target_force, true)
end

--- Open a friend-view: direct remote view without spectator force swap.
function spectator.enter_friend_view(player, surface, position)
    log("[multi-team-support:spectator] enter_friend_view: " .. player.name
        .. " on " .. surface.name)
    -- Save pre-view location so "return to base" restores it.
    -- Use physical_position/physical_surface for the same reason as spectator.enter():
    -- player.position is the camera position when already in remote map view.
    if not spectator.is_spectating(player)
       and not storage.spectator_saved_location[player.index] then
        storage.spectator_saved_location[player.index] = {
            surface_name = player.physical_surface.name,
            position     = {x = player.physical_position.x, y = player.physical_position.y},
        }
    end
    open_remote_view(player, surface, position)
end

-- ─── Event Handlers ────────────────────────────────────────────────────

--- Detects remote-view exit and calls exit().
function spectator.on_controller_changed(player, old_controller_type)
    if old_controller_type ~= defines.controllers.remote then return end
    if player.controller_type == defines.controllers.remote then return end

    if spectator.is_spectating(player) then
        log("[multi-team-support:spectator] on_controller_changed: " .. player.name
            .. " exited remote view, restoring force")
        spectator.exit(player)
    end
end

--- Upgrade a spectator to friend-view (restore force, keep remote view).
local function upgrade_to_friend_view(p, idx)
    restore_player_state(p)
    clear_spectator_storage(idx)
    if p.crafting_queue_size > 0 then
        p.print("[multi-team-support] You are now viewing as a friend. Crafting resumed.")
    else
        p.print("[multi-team-support] You are now viewing as a friend.")
    end
    log("[multi-team-support:spectator] upgraded " .. p.name .. " from spectator to friend-view")
end

--- Downgrade a friend-viewer to spectator (swap force, keep remote view).
local function downgrade_to_spectator(p, player_force)
    log("[multi-team-support:spectator] downgrading " .. p.name
        .. " from friend-view to spectator (unfriended)")

    storage.spectating_target[p.index] = player_force.name
    apply_spectator_state(p)

    local unfriender = helpers.display_name(player_force.name)
    if p.crafting_queue_size > 0 then
        p.print("[multi-team-support] " .. unfriender .. " unfriended you. Now spectating (crafting paused).")
    else
        p.print("[multi-team-support] " .. unfriender .. " unfriended you. Now spectating.")
    end
end

--- Handle friendship changes that affect active spectators/friend-viewers.
function spectator.on_friend_changed(player_force, target_force, is_friend)
    log("[multi-team-support:spectator] on_friend_changed: "
        .. player_force.name .. (is_friend and " friended " or " unfriended ")
        .. target_force.name)

    if is_friend then
        -- Upgrade spectators whose real force is target_force watching player_force
        for idx, spectated_fn in pairs(storage.spectating_target) do
            if spectated_fn == player_force.name
               and storage.spectator_real_force[idx] == target_force.name then
                local p = game.get_player(idx)
                if p and p.connected then
                    upgrade_to_friend_view(p, idx)
                end
            end
        end
    else
        -- Downgrade target_force players friend-viewing player_force's surfaces
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

--- Called from on_player_left_game.
function spectator.on_player_left(player)
    if not spectator.is_spectating(player) then return end
    log("[multi-team-support:spectator] on_player_left: restoring " .. player.name)
    restore_player_state(player)
    clear_spectator_storage(player.index)
end

--- Called from on_player_joined_game. Defensive cleanup.
function spectator.on_player_joined(player)
    local real_fn = storage.spectator_real_force[player.index]

    if real_fn then
        -- There is live spectator storage: restore force, permission group, and
        -- crafting modifier regardless of which force the player is currently on.
        -- The old code skipped restore_player_state when the force was already
        -- non-spectator, leaving character_crafting_speed_modifier at -1 and the
        -- player stuck in the spectator permission group.
        local was_on_spectator = (player.force.name == "spectator")
        restore_player_state(player)
        clear_spectator_storage(player.index)
        if was_on_spectator then
            log("[multi-team-support:spectator] on_player_joined: restored " .. player.name
                .. " from spectator force")
        else
            log("[multi-team-support:spectator] on_player_joined: cleaned stale storage for "
                .. player.name)
        end
        return
    end

    -- No spectator storage, but the player may still be stuck in the spectator
    -- permission group or have a negative crafting modifier from a previous
    -- session where storage was cleared without restoring state.  Fix both
    -- defensively on every join when the player is on their own (non-spectator)
    -- force.
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

--- Returns the chat context prefix for a player, or "".
function spectator.get_chat_prefix(player)
    local target_fn = spectator.get_target(player)
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

return spectator
