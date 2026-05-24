-- gui/buddy_requests.lua
-- Buddy request operations: send, accept, cancel, reject, rebuild.

local admin_gui        = require("gui.admin")
local helpers          = require("scripts.helpers")
local ultracube_compat = require("compat.ultracube")
local force_utils      = require("scripts.force_utils")
local pen_gui          = require("gui.pen_gui")
local pen_ops          = require("gui.pen_ops")
local team_clock       = require("scripts.team_clock")

local M = {}

-- ─── Buddy Request Dialog ──────────────────────────────────────────────

local function show_buddy_request_gui(target, requester)
    if target.gui.screen.sb_buddy_req_frame then
        target.gui.screen.sb_buddy_req_frame.destroy()
    end
    local frame = target.gui.screen.add{
        type = "frame", name = "sb_buddy_req_frame", direction = "vertical",
    }
    frame.auto_center = true
    helpers.add_title_bar(frame, "Buddy Request")

    local msg = frame.add{type = "label", caption = requester.name .. " wants to join your team."}
    msg.style.top_margin    = 6
    msg.style.bottom_margin = 4
    msg.style.left_margin   = 4
    frame.add{type = "line"}

    local btn_flow = frame.add{type = "flow", direction = "horizontal"}
    btn_flow.style.top_margin    = 4
    btn_flow.style.bottom_margin = 2
    local accept_btn = btn_flow.add{
        type = "button", name = "sb_buddy_accept", caption = "Accept",
        style = "confirm_button", tags = {sb_requester_index = requester.index},
    }
    accept_btn.style.horizontally_stretchable = true
    local reject_btn = btn_flow.add{
        type = "button", name = "sb_buddy_reject", caption = "Reject",
        style = "red_button", tags = {sb_requester_index = requester.index},
    }
    reject_btn.style.horizontally_stretchable = true
end

-- ─── Public API ────────────────────────────────────────────────────────

function M.team_has_room(target)
    local limit = admin_gui.buddy_team_limit()
    local n = 0
    for _ in pairs(target.force.players) do n = n + 1 end
    return n < limit
end

function M.rebuild_buddy_request_guis()
    storage.buddy_requests = storage.buddy_requests or {}
    for req_idx, tgt_idx in pairs(storage.buddy_requests) do
        local target    = game.get_player(tgt_idx)
        local requester = game.get_player(req_idx)
        if target and target.connected and requester and requester.valid then
            if not target.gui.screen.sb_buddy_req_frame then
                show_buddy_request_gui(target, requester)
            end
        end
    end
end

function M.send_buddy_request(requester, target)
    if not M.team_has_room(target) then
        requester.print(helpers.team_tag(target.force.name) .. " is full.")
        pen_gui.build_pen_gui(requester)
        return
    end
    storage.buddy_requests = storage.buddy_requests or {}
    storage.buddy_requests[requester.index] = target.index
    show_buddy_request_gui(target, requester)
    pen_gui.build_pen_gui(requester)

    local requester_tag = helpers.colored_name(requester.name, requester.chat_color)
    local leader_tag    = helpers.colored_name(target.name, target.chat_color)
    local team_tag      = helpers.team_tag_with_leader(target.force.name)
    requester.print("You requested to join " .. team_tag
        .. ". Waiting for " .. leader_tag .. " (leader) to approve.")
    helpers.broadcast("[Team] " .. requester_tag .. " wants to join " .. team_tag .. ".")
end

function M.accept_buddy_request(target, requester_index)
    storage.buddy_requests = storage.buddy_requests or {}
    storage.buddy_requests[requester_index] = nil

    if target.gui.screen.sb_buddy_req_frame then
        target.gui.screen.sb_buddy_req_frame.destroy()
    end

    local requester = game.get_player(requester_index)
    if not (requester and requester.valid) then return end

    if not M.team_has_room(target) then
        local ft = helpers.force_tag(target.force.name)
        target.print("Your team is full — cannot accept "
            .. helpers.colored_name(requester.name, requester.chat_color) .. "." .. ft)
        if requester.connected then
            requester.print(helpers.colored_name(target.name, target.chat_color)
                .. "'s team is now full." .. ft)
            pen_gui.build_pen_gui(requester)
        end
        pen_gui.update_pen_gui_all()
        return
    end

    -- Anti-abuse: clear inventory if the player previously left this team.
    storage.left_teams = storage.left_teams or {}
    local is_rejoin = storage.left_teams[requester.index]
        and storage.left_teams[requester.index][target.force.name]
    if is_rejoin then
        if requester.character then requester.character.clear_items_inside() end
        requester.print("Your inventory was cleared because you previously left this team."
            .. helpers.force_tag(target.force.name))
    else
        pen_ops.grant_starter_items(requester)
    end

    local leader_tag    = helpers.colored_name(target.name, target.chat_color)
    local requester_tag = helpers.colored_name(requester.name, requester.chat_color)
    local team_tag      = helpers.team_tag_with_leader(target.force.name)

    helpers.broadcast("[Team] " .. leader_tag .. " accepted " .. requester_tag
        .. " into " .. team_tag .. ".")

    local prev_force_name = requester.force.name
    requester.force = target.force
    -- Settle online clocks for the team the requester left and the one joined.
    team_clock.refresh(prev_force_name)
    team_clock.refresh(target.force.name)
    local default_group = game.permissions.get_group("Default")
    if default_group then default_group.add_player(requester) end
    pen_ops.finish_spawn(requester)
    storage.pending_spawn_pop = storage.pending_spawn_pop or {}
    storage.pending_spawn_pop[requester.index] = requester.force.name
    local spawn_pos = target.surface.find_non_colliding_position(
        "character", target.position, 10, 1) or target.position
    requester.teleport(spawn_pos, target.surface)
    ultracube_compat.after_spawn(requester)

    storage.player_clock_start = storage.player_clock_start or {}
    if not storage.player_clock_start[requester.index] then
        storage.player_clock_start[requester.index] = game.tick
    end

    helpers.broadcast("[Team] " .. requester_tag .. " has joined " .. team_tag .. ".")

    local ft = helpers.force_tag(target.force.name)
    target.print(helpers.colored_name(requester.name, requester.chat_color)
        .. " has joined your team." .. ft)
    if requester.connected then
        requester.print("You joined " .. helpers.colored_name(target.name, target.chat_color)
            .. "'s team." .. ft)
    end
end

function M.cancel_buddy_request(requester)
    storage.buddy_requests = storage.buddy_requests or {}
    local target_idx = storage.buddy_requests[requester.index]
    if not target_idx then return end
    storage.buddy_requests[requester.index] = nil

    local target = game.get_player(target_idx)
    if target and target.valid then
        if target.gui.screen.sb_buddy_req_frame then
            target.gui.screen.sb_buddy_req_frame.destroy()
        end
        local requester_tag = helpers.colored_name(requester.name, requester.chat_color)
        local team_tag      = helpers.team_tag_with_leader(target.force.name)
        helpers.broadcast("[Team] " .. requester_tag
            .. " cancelled their request to join " .. team_tag .. ".")
    end

    if requester.connected then
        requester.print("You cancelled your join request.")
        pen_gui.build_pen_gui(requester)
    end
end

function M.reject_buddy_request(target, requester_index)
    storage.buddy_requests = storage.buddy_requests or {}
    storage.buddy_requests[requester_index] = nil

    if target.gui.screen.sb_buddy_req_frame then
        target.gui.screen.sb_buddy_req_frame.destroy()
    end

    local requester = game.get_player(requester_index)
    if not requester then return end

    local leader_tag    = helpers.colored_name(target.name, target.chat_color)
    local requester_tag = helpers.colored_name(requester.name, requester.chat_color)
    local team_tag      = helpers.team_tag_with_leader(target.force.name)
    helpers.broadcast("[Team] " .. leader_tag .. " declined " .. requester_tag
        .. "'s request to join " .. team_tag .. ".")

    if requester.connected then
        requester.print(leader_tag .. " declined your buddy request.")
        pen_gui.build_pen_gui(requester)
    end
end

return M
