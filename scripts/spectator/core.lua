-- scripts/spectator/core.lua
-- Internal primitives: state mutations, surface visibility, setup, state queries.
-- Exported so ops.lua and events.lua can share them without circular deps.

local admin_gui     = require("gui.admin")
local helpers       = require("scripts.helpers")
local surface_utils = require("scripts.surface_utils")

local M = {}

-- ─── Primitive State Mutations ─────────────────────────────────────────

function M.apply_spectator_state(player)
    if not M.is_spectating(player) then
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

--- Restore force, permission group, crafting modifier. Does NOT clear storage.
function M.restore_player_state(player)
    local real_fn    = storage.spectator_real_force[player.index]
    local real_force = real_fn and game.forces[real_fn]
    if real_force then player.force = real_force end
    local default_group = game.permissions.get_group("Default")
    if default_group then default_group.add_player(player) end
    if player.character then
        local saved = storage.spectator_saved_craft_mod[player.index]
        player.character_crafting_speed_modifier = saved or 0
    end
    storage.spectator_saved_craft_mod[player.index] = nil
    player.show_on_map = true
end

function M.clear_spectator_storage(idx)
    storage.spectator_real_force[idx]      = nil
    storage.spectating_target[idx]         = nil
    storage.spectator_saved_craft_mod[idx] = nil
    storage.spectator_saved_location[idx]  = nil
end

--- Recalculate which surfaces are visible to the spectator force.
--- Spectator force sees the union of all currently-spectated targets' surfaces.
function M.update_spectator_surfaces()
    local spec = game.forces["spectator"]
    if not spec then return end

    local visible_forces = {}
    for _, target_fn in pairs(storage.spectating_target) do
        visible_forces[target_fn] = true
    end

    for _, surface in pairs(game.surfaces) do
        if surface.name == "landing-pen" then
            helpers.set_surface_hidden(spec, surface, false)
        else
            local owner = surface_utils.get_owner(surface)
            helpers.set_surface_hidden(spec, surface, not (owner and visible_forces[owner]))
        end
    end
end

function M.announce_spectation(viewer, target_force, is_entering, target_player, surface)
    if not admin_gui.flag("spectate_notifications_enabled") then return end

    local target_name  = helpers.display_name(target_force.name)
    local action       = is_entering and "is now spectating" or "stopped spectating"
    local target_color = helpers.force_color(target_force)
    local team_tag     = helpers.colored_name(target_name, target_color)

    local surface_suffix = ""
    if surface and surface.valid then
        surface_suffix = " (" .. helpers.display_surface_name(surface.name) .. ")"
    end

    local target_text
    if target_player and target_player.valid then
        target_text = helpers.colored_name(target_player.name, target_player.chat_color)
            .. " (" .. team_tag .. ")" .. surface_suffix
    else
        target_text = team_tag .. surface_suffix
    end

    local msg = helpers.colored_name(viewer.name, viewer.chat_color)
        .. " " .. action .. " " .. target_text
    helpers.broadcast(msg)
    log("[multi-team-support:spectator] " .. viewer.name .. " " .. action
        .. " " .. (surface and surface.valid and (surface.name .. " / ") or "")
        .. (target_player and target_player.valid and (target_player.name .. " / ") or "")
        .. target_name)
end

function M.open_remote_view(player, surface, position)
    player.set_controller({
        type     = defines.controllers.remote,
        surface  = surface,
        position = position,
    })
end

-- ─── Setup ─────────────────────────────────────────────────────────────

local SPECTATOR_ALLOWED_ACTIONS = {
    "admin_action",
    "change_active_item_group_for_filters",
    -- Required so mods using player.request_translations() (e.g. factoriolab-export)
    -- can receive on_string_translated while in the spectator group.
    "translate_string",
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

local function setup_permission_group()
    local p = game.permissions.get_group("spectator")
    if not p then p = game.permissions.create_group("spectator") end
    for _, action_id in pairs(defines.input_action) do
        p.set_allows_action(action_id, false)
    end
    for _, name in ipairs(SPECTATOR_ALLOWED_ACTIONS) do
        local action = defines.input_action[name]
        if action then p.set_allows_action(action, true) end
    end
end

function M.init()
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
        if force.name:find("^team%-") then
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

    for _, surface in pairs(game.surfaces) do
        if surface.name ~= "landing-pen" then
            helpers.set_surface_hidden(spec, surface, true)
        end
    end
    log("[multi-team-support:spectator] init: complete, permission group configured")
end

function M.setup_force(new_force)
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
            helpers.set_surface_hidden(new_force, surface, true)
        end
    end
    log("[multi-team-support:spectator] setup_force: " .. new_force.name)
end

function M.init_storage()
    storage.spectator_real_force      = storage.spectator_real_force      or {}
    storage.spectating_target         = storage.spectating_target         or {}
    storage.spectator_saved_craft_mod = storage.spectator_saved_craft_mod or {}
    storage.spectator_saved_location  = storage.spectator_saved_location  or {}
    storage.friend_intents            = storage.friend_intents            or {}
end

-- ─── State Queries ─────────────────────────────────────────────────────

function M.is_spectating(player)
    return storage.spectator_real_force[player.index] ~= nil
end

function M.get_real_force(player)
    return storage.spectator_real_force[player.index]
end

function M.get_effective_force(player)
    return storage.spectator_real_force[player.index] or player.force.name
end

function M.get_target(player)
    return storage.spectating_target and storage.spectating_target[player.index]
end

function M.needs_spectator_mode(viewer_force, target_force)
    -- Viewing your own team never requires spectator mode. A LuaForce isn't
    -- its own friend by default, so without this short-circuit the function
    -- would falsely demand a force swap for same-team surface clicks.
    if viewer_force == target_force then return false end
    return not target_force.get_friend(viewer_force)
end

--- Resolve where to aim a view for a target player.
--- Returns (force, surface, position) — force is always the real team (never "spectator").
--- If the target is mts-spectating, returns their physical location to avoid chain-spectating.
function M.resolve_view_for(target)
    if not (target and target.valid) then return nil, nil, nil end
    local force = game.forces[M.get_effective_force(target)]
    local surface, position
    if M.is_spectating(target) then
        surface  = target.physical_surface
        position = target.physical_position
    else
        surface  = target.surface
        position = target.position
    end
    return force, surface, position
end

return M
