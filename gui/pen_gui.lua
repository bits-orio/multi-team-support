-- gui/pen_gui.lua
-- Landing pen panel: build_pen_gui, update_pen_gui_all, join-team section.

local admin_gui   = require("gui.admin")
local helpers     = require("scripts.helpers")
local force_utils = require("scripts.force_utils")
local terrain     = require("gui.landing_pen_terrain")

local SURFACE_NAME = terrain.SURFACE_NAME

local M = {}

-- ─── Join Team Section ─────────────────────────────────────────────────

--- "Request to join" row per occupied team that is actively recruiting.
local function add_join_team_section(frame, player)
    if not admin_gui.flag("buddy_join_enabled") then return end

    storage.team_looking_for_more = storage.team_looking_for_more or {}
    local rows = {}
    for i = 1, force_utils.max_teams() do
        local force_name = "team-" .. i
        if (storage.team_pool or {})[i] == "occupied"
           and storage.team_looking_for_more[force_name] then
            local force = game.forces[force_name]
            local leader_idx = (storage.team_leader or {})[force_name]
            local leader = leader_idx and game.get_player(leader_idx)
            if force and leader then
                rows[#rows + 1] = {force_name = force_name, force = force, leader = leader}
            end
        end
    end

    if #rows == 0 then return end

    local or_flow = frame.add{type = "flow", direction = "horizontal"}
    or_flow.style.horizontal_align         = "center"
    or_flow.style.horizontally_stretchable = true
    or_flow.style.top_margin               = 10
    or_flow.style.bottom_margin            = 2
    local or_label = or_flow.add{
        type    = "label",
        caption = "─────  OR  join a team that's recruiting  ─────",
    }
    or_label.style.font       = "heading-2"
    or_label.style.font_color = {1, 0.85, 0.3}

    local limit = admin_gui.buddy_team_limit()
    local limit_flow = frame.add{type = "flow", direction = "horizontal"}
    limit_flow.style.horizontal_align         = "center"
    limit_flow.style.horizontally_stretchable = true
    limit_flow.style.bottom_margin            = 4
    local limit_note = limit_flow.add{type = "label", caption = "(max " .. limit .. " per team)"}
    limit_note.style.font       = "default-small"
    limit_note.style.font_color = {0.7, 0.7, 0.7}

    storage.buddy_requests = storage.buddy_requests or {}
    local my_request = storage.buddy_requests[player.index]

    for _, row_info in ipairs(rows) do
        local row = frame.add{type = "flow", direction = "horizontal"}
        row.style.vertical_align           = "center"
        row.style.left_margin              = 4
        row.style.top_margin               = 2
        row.style.horizontally_stretchable = true

        local team_name_lbl = row.add{type = "label", caption = helpers.team_tag(row_info.force_name)}
        team_name_lbl.style.minimal_width = 140

        local leader_text = "(leader: " .. row_info.leader.name
            .. (row_info.leader.connected and "" or " — offline") .. ")"
        local leader_lbl = row.add{type = "label", caption = leader_text}
        leader_lbl.style.font       = "default-small"
        leader_lbl.style.font_color = row_info.leader.connected
            and row_info.leader.chat_color or {0.55, 0.55, 0.55}

        row.add{type = "empty-widget"}.style.horizontally_stretchable = true

        local member_count = #row_info.force.players
        local has_room = member_count < limit

        if my_request == row_info.leader.index then
            local pending = row.add{type = "label", caption = "Pending..."}
            pending.style.font         = "default-small"
            pending.style.font_color   = {1, 1, 0.4}
            pending.style.right_margin = 4
            row.add{
                type    = "button",
                name    = "sb_buddy_cancel",
                caption = "Cancel request",
                style   = "red_button",
                tooltip = "Withdraw your request to join "
                    .. helpers.display_name(row_info.force_name),
            }
        elseif not has_room then
            local full = row.add{type = "label",
                caption = "Full (" .. member_count .. "/" .. limit .. ")"}
            full.style.font       = "default-small"
            full.style.font_color = {1, 0.4, 0.4}
        elseif not row_info.leader.connected then
            local off = row.add{type = "label", caption = "Leader offline"}
            off.style.font       = "default-small"
            off.style.font_color = {0.55, 0.55, 0.55}
        elseif my_request then
            row.add{
                type    = "button",
                name    = "sb_buddy_request_disabled",
                caption = "Request to join",
                style   = "confirm_button",
                tooltip = "Cancel your pending request first to join a different team.",
                enabled = false,
            }
        else
            row.add{
                type    = "button",
                name    = "sb_buddy_request",
                caption = "Request to join",
                style   = "confirm_button",
                tags    = {sb_target_index = row_info.leader.index},
                tooltip = "Ask " .. row_info.leader.name
                    .. " to join " .. helpers.display_name(row_info.force_name),
            }
        end
    end
end

local function occupied_team_count()
    local n = 0
    for i = 1, force_utils.max_teams() do
        if (storage.team_pool or {})[i] == "occupied" then n = n + 1 end
    end
    return n
end

local function recruiting_team_exists()
    storage.team_looking_for_more = storage.team_looking_for_more or {}
    for i = 1, force_utils.max_teams() do
        local fn = "team-" .. i
        if (storage.team_pool or {})[i] == "occupied" and storage.team_looking_for_more[fn] then
            return true
        end
    end
    return false
end

-- ─── Public API ────────────────────────────────────────────────────────

function M.build_pen_gui(player)
    storage.pen_gui_location = storage.pen_gui_location or {}
    local frame = helpers.reuse_or_create_frame(
        player, "sb_pen_frame", storage.pen_gui_location, {x = 5, y = 80})

    helpers.add_title_bar(frame, "Landing Pen")
    frame.style.minimal_width = 360
    frame.style.maximal_width = 480

    storage.buddy_requests = storage.buddy_requests or {}
    local has_pending = storage.buddy_requests[player.index] ~= nil
    local btn = frame.add{
        type    = "button",
        name    = "sb_spawn_btn",
        caption = "Start a new team",
        style   = "confirm_button",
        enabled = not has_pending,
        tooltip = has_pending
            and "Cancel your pending join request first to start a new team."
            or  "Claim a new team slot and spawn into the game.",
    }
    btn.style.top_margin               = 4
    btn.style.bottom_margin            = 2
    btn.style.horizontally_stretchable = true

    if admin_gui.flag("buddy_join_enabled") and occupied_team_count() > 0 and recruiting_team_exists() then
        local scroll = frame.add{
            type      = "scroll-pane",
            direction = "vertical",
            horizontal_scroll_policy = "never",
            vertical_scroll_policy   = "auto-and-reserve-space",
        }
        scroll.style.maximal_height           = 500
        scroll.style.horizontally_stretchable = true
        add_join_team_section(scroll, player)
    end
end

--- Rebuild the pen GUI for every connected pen player.
--- Inlines the is_in_pen check to avoid a circular require on landing_pen.
function M.update_pen_gui_all()
    local surface = game.surfaces[SURFACE_NAME]
    if not surface then return end
    storage.spawned_players = storage.spawned_players or {}
    for _, player in pairs(game.players) do
        if player.connected
           and player.surface == surface
           and not storage.spawned_players[player.index] then
            M.build_pen_gui(player)
        end
    end
end

return M
