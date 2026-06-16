-- scripts/pre_start.lua
-- Pre-start staging: when "Staged Start" is enabled, a new team leader is placed
-- in a locked-down permission group immediately after claiming their slot. Their
-- team clock (birth tick + online time) does not begin until they click
-- "Start Playing". This lets speedrunners inspect their map and plan before
-- committing to a run.
--
-- Storage:
--   storage.pre_start_pending[force_name] = true   -- team is waiting for Start Playing

local team_clock  = require("scripts.team_clock")
local force_utils = require("scripts.force_utils")
local helpers     = require("scripts.helpers")

local M = {}

local GROUP_NAME = "mts-pre-start"

-- All GUI interactions must be kept so the player can click "Start Playing"
-- and interact with mod panels. Everything game-world is blocked.
local ALLOWED_ACTIONS = {
    "admin_action",
    "change_active_item_group_for_filters",
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
    "quick_bar_set_selected_page",
    "quick_bar_set_slot",
    "remote_view_surface",
    "set_player_color",
    "toggle_map_editor",
    "toggle_show_entity_info",
    "write_to_console",
}

-- ─── Permission Group ─────────────────────────────────────────────────

-- Called from control.lua on_init and on_configuration_changed.
function M.ensure_permission_group()
    local p = game.permissions.get_group(GROUP_NAME)
    if not p then p = game.permissions.create_group(GROUP_NAME) end
    -- Disable every defined game action.
    for _, action_id in pairs(defines.input_action) do
        p.set_allows_action(action_id, false)
    end
    -- Re-enable only what we need.
    for _, name in ipairs(ALLOWED_ACTIONS) do
        local id = defines.input_action[name]
        if id then p.set_allows_action(id, true) end
    end
end

-- ─── Storage ──────────────────────────────────────────────────────────

function M.init_storage()
    storage.pre_start_pending = storage.pre_start_pending or {}
end

function M.is_pending(force_name)
    return (storage.pre_start_pending or {})[force_name] == true
end

-- ─── Enter ────────────────────────────────────────────────────────────

-- Put player in the restricted group and mark their team as pending.
function M.enter(player, force_name)
    M.init_storage()
    storage.pre_start_pending[force_name] = true
    local group = game.permissions.get_group(GROUP_NAME)
    if group then group.add_player(player) end
end

-- Called when a buddy-join member lands in a team that is still pre-start.
function M.enter_member(player)
    local group = game.permissions.get_group(GROUP_NAME)
    if group then group.add_player(player) end
end

-- ─── Commit (Start Playing) ───────────────────────────────────────────

-- Restore full permissions, start all clocks, clear pending state.
function M.commit(player)
    local force_name = player.force.name
    M.init_storage()
    storage.pre_start_pending[force_name] = nil

    -- Restore every current team member to the Default group.
    local default = game.permissions.get_group("Default")
    if default then
        local force = game.forces[force_name]
        if force then
            for _, member in pairs(force.players) do
                if member.valid then default.add_player(member) end
            end
        end
    end

    -- Start the team birth clock. raise on_team_clock_started exactly once,
    -- only when this commit is the call that actually stamps the start tick
    -- (the staged-start path defers the clock until this "Start Playing" click).
    storage.team_clock_start = storage.team_clock_start or {}
    local clock_started_now = false
    if not storage.team_clock_start[force_name] then
        storage.team_clock_start[force_name] = game.tick
        clock_started_now = true
        log("[multi-team-support] pre_start committed for " .. force_name
            .. " at tick " .. game.tick)
    end
    team_clock.on_claim(force_name)
    team_clock.refresh(force_name)
    if clock_started_now then
        -- Lazy require to keep pre_start's load free of any remote_api cycle.
        require("scripts.remote_api").raise_team_clock_started(
            force_name, storage.team_clock_start[force_name])
    end

    -- Start the leader's personal clock.
    force_utils.start_player_clock(player)

    helpers.broadcast("[Team] " .. helpers.team_tag(force_name) .. " has started playing!")
end

-- ─── Cancel (team disbanded during pre-start) ─────────────────────────

-- Clear pending state only — callers handle permission restoration themselves
-- (via direct Default group assignment in team_slots.lua's remove_from_team).
function M.cancel(force_name)
    M.init_storage()
    storage.pre_start_pending[force_name] = nil
end

return M
