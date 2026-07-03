-- gui/buddy_requests.lua
-- Buddy request operations: send, accept, cancel, reject, rebuild.
--
-- A request is addressed to a TEAM (force), not to the leader — any online
-- member can accept it. Storage + per-requester frame teardown live in
-- scripts/buddy_store (dependency-free); this module owns the UI + messaging.

local admin_gui         = require("gui.admin")
local helpers           = require("scripts.helpers")
local ultracube_compat  = require("compat.ultracube")
local pen_gui           = require("gui.pen_gui")
local pen_ops           = require("gui.pen_ops")
local team_clock        = require("scripts.team_clock")
local pre_start         = require("scripts.pre_start")
local start_playing_gui = require("gui.start_playing_gui")
local buddy_store       = require("scripts.buddy_store")

local M = {}

-- A pen player is one who has not yet spawned. Inlined (rather than requiring
-- landing_pen) to avoid a circular require through gui.landing_pen.
local function is_in_pen(player)
    return not (storage.spawned_players or {})[player.index]
end

-- ─── Buddy Request Dialog ──────────────────────────────────────────────

--- Show one requester's Accept/Reject dialog on a single member's screen.
local function show_frame_for(member, requester)
    local fname = buddy_store.frame_name(requester.index)
    if member.gui.screen[fname] then member.gui.screen[fname].destroy() end
    -- Cascade multiple pending requests so they don't stack dead-center on top
    -- of each other (a recruiting team can receive several at once).
    local existing = 0
    for _, c in pairs(member.gui.screen.children) do
        if c.name and c.name:find("^sb_buddy_req_") then existing = existing + 1 end
    end
    local frame = member.gui.screen.add{type = "frame", name = fname, direction = "vertical"}
    if existing == 0 then
        frame.auto_center = true
    else
        frame.location = {x = 60 + existing * 28, y = 60 + existing * 28}
    end
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

--- Show a requester's dialog to every online member of the target team,
--- including members currently on the spectator force (remote-viewing).
local function show_to_team(force_name, requester)
    if not game.forces[force_name] then return end
    for _, member in pairs(game.connected_players) do
        if buddy_store.team_of(member) == force_name then
            show_frame_for(member, requester)
        end
    end
end

-- ─── Public API ────────────────────────────────────────────────────────

function M.team_has_room(force)
    if not (force and force.valid) then return false end
    local limit = admin_gui.buddy_team_limit()
    local n = 0
    for _ in pairs(force.players) do n = n + 1 end
    return n < limit
end

--- Rebuild dialogs after a reload/reconnect: re-show every pending request to
--- all online members of its team, and drop requests whose requester is gone
--- or has already spawned.
function M.rebuild_buddy_request_guis()
    storage.buddy_requests = storage.buddy_requests or {}
    for req_idx, force_name in pairs(storage.buddy_requests) do
        local requester = game.get_player(req_idx)
        if requester and requester.valid and is_in_pen(requester) and game.forces[force_name] then
            show_to_team(force_name, requester)
        else
            buddy_store.clear(req_idx)
        end
    end
end

function M.send_buddy_request(requester, force_name)
    local force = game.forces[force_name]
    if not (force and force.valid) then return end
    if not M.team_has_room(force) then
        requester.print(helpers.team_tag(force_name) .. " is full.")
        pen_gui.build_pen_gui(requester)
        return
    end
    buddy_store.set(requester.index, force_name)
    show_to_team(force_name, requester)
    pen_gui.build_pen_gui(requester)

    local requester_tag = helpers.colored_name(requester.name, requester.chat_color)
    local team_tag      = helpers.team_tag_with_leader(force_name)
    requester.print("You requested to join " .. team_tag
        .. ". Waiting for a member to approve.")
    helpers.broadcast("[Team] " .. requester_tag .. " wants to join " .. team_tag .. ".")
end

--- Accept a request. `member` is the clicking team member (any member, not just
--- the leader). Re-validates the request is still live and still targets this
--- member's team before mutating (DB-2), since many members can race to accept.
function M.accept_buddy_request(member, requester_index)
    local force_name = buddy_store.request_of(requester_index)
    -- Stale/already-handled: the frame this member clicked is orphaned; drop it.
    if not force_name then
        buddy_store.destroy_frames(requester_index)
        return
    end
    -- The clicker must really belong to the requested team. team_of sees through
    -- a temporary spectator force, so a member accepting while remote-viewing
    -- still qualifies; a genuine non-member's stale frame is torn down.
    if buddy_store.team_of(member) ~= force_name then
        if member.gui.screen[buddy_store.frame_name(requester_index)] then
            member.gui.screen[buddy_store.frame_name(requester_index)].destroy()
        end
        return
    end

    local requester = game.get_player(requester_index)
    if not (requester and requester.valid) or not is_in_pen(requester) then
        -- Requester left or already spawned via another path — cancel cleanly.
        buddy_store.clear(requester_index)
        pen_gui.update_pen_gui_all()
        return
    end

    local force = game.forces[force_name]
    if not (force and force.valid) then
        buddy_store.clear(requester_index)
        return
    end
    if not M.team_has_room(force) then
        local ft = helpers.force_tag(force_name)
        member.print("Your team is full — cannot accept "
            .. helpers.colored_name(requester.name, requester.chat_color) .. "." .. ft)
        if requester.connected then
            requester.print(helpers.team_tag(force_name) .. " is now full." .. ft)
            pen_gui.build_pen_gui(requester)
        end
        buddy_store.clear(requester_index)
        pen_gui.update_pen_gui_all()
        return
    end

    -- Commit: this request is now consumed; tear its frames down on all members.
    buddy_store.clear(requester_index)

    -- Anti-abuse: clear inventory if the player previously left this team.
    storage.left_teams = storage.left_teams or {}
    local is_rejoin = storage.left_teams[requester.index]
        and storage.left_teams[requester.index][force_name]
    if is_rejoin then
        if requester.character then requester.character.clear_items_inside() end
        requester.print("Your inventory was cleared because you previously left this team."
            .. helpers.force_tag(force_name))
    else
        pen_ops.grant_starter_items(requester)
    end

    local member_tag    = helpers.colored_name(member.name, member.chat_color)
    local requester_tag = helpers.colored_name(requester.name, requester.chat_color)
    local team_tag      = helpers.team_tag_with_leader(force_name)

    helpers.broadcast("[Team] " .. member_tag .. " accepted " .. requester_tag
        .. " into " .. team_tag .. ".")

    local prev_force_name = requester.force.name
    requester.force = force
    -- Settle online clocks for the team the requester left and the one joined.
    team_clock.refresh(prev_force_name)
    team_clock.refresh(force_name)

    -- If the team is still in pre-start staging, lock the new member down too.
    if pre_start.is_pending(force_name) then
        pre_start.enter_member(requester)
        if requester.connected then start_playing_gui.show(requester) end
    end

    -- Auto-clear recruiting flag when the team is now full.
    -- Returns the force name to the caller so it can refresh team settings.
    local lfm_cleared_force = nil
    if not M.team_has_room(force) then
        storage.team_looking_for_more = storage.team_looking_for_more or {}
        if storage.team_looking_for_more[force_name] then
            storage.team_looking_for_more[force_name] = nil
            helpers.broadcast("[Team] " .. helpers.team_tag(force_name)
                .. " is no longer recruiting (team is now full).")
            lfm_cleared_force = force_name
        end
    end
    -- Only restore Default if the team isn't in staging; pre_start.enter_member
    -- already assigned the restricted group and must not be overwritten.
    if not pre_start.is_pending(force_name) then
        local default_group = game.permissions.get_group("Default")
        if default_group then default_group.add_player(requester) end
    end
    pen_ops.finish_spawn(requester)
    storage.pending_spawn_pop = storage.pending_spawn_pop or {}
    storage.pending_spawn_pop[requester.index] = force_name
    -- Spawn next to the accepting member's CHARACTER (physical_*), not their
    -- current view — a member may accept while remote-viewing another surface,
    -- and we must not drop the requester onto that surface.
    local surf      = member.physical_surface or member.surface
    local pos       = member.physical_position or member.position
    local spawn_pos = surf.find_non_colliding_position("character", pos, 10, 1) or pos
    requester.teleport(spawn_pos, surf)
    ultracube_compat.after_spawn(requester)

    storage.player_clock_start = storage.player_clock_start or {}
    if not storage.player_clock_start[requester.index] then
        storage.player_clock_start[requester.index] = game.tick
    end

    helpers.broadcast("[Team] " .. requester_tag .. " has joined " .. team_tag .. ".")

    local ft = helpers.force_tag(force_name)
    member.print(helpers.colored_name(requester.name, requester.chat_color)
        .. " has joined your team." .. ft)
    if requester.connected then
        requester.print("You joined " .. team_tag .. "." .. ft)
    end
    return lfm_cleared_force
end

function M.cancel_buddy_request(requester)
    local force_name = buddy_store.request_of(requester.index)
    if not force_name then return end
    buddy_store.clear(requester.index)

    local requester_tag = helpers.colored_name(requester.name, requester.chat_color)
    local team_tag      = helpers.team_tag_with_leader(force_name)
    helpers.broadcast("[Team] " .. requester_tag
        .. " cancelled their request to join " .. team_tag .. ".")

    if requester.connected then
        requester.print("You cancelled your join request.")
        pen_gui.build_pen_gui(requester)
    end
end

--- Reject a request. `member` is any team member holding the dialog.
function M.reject_buddy_request(member, requester_index)
    local force_name = buddy_store.request_of(requester_index)
    if not force_name then
        buddy_store.destroy_frames(requester_index)
        return
    end
    if buddy_store.team_of(member) ~= force_name then
        if member.gui.screen[buddy_store.frame_name(requester_index)] then
            member.gui.screen[buddy_store.frame_name(requester_index)].destroy()
        end
        return
    end
    buddy_store.clear(requester_index)

    local requester = game.get_player(requester_index)
    if not requester then return end

    local member_tag    = helpers.colored_name(member.name, member.chat_color)
    local requester_tag = helpers.colored_name(requester.name, requester.chat_color)
    local team_tag      = helpers.team_tag_with_leader(force_name)
    helpers.broadcast("[Team] " .. member_tag .. " declined " .. requester_tag
        .. "'s request to join " .. team_tag .. ".")

    if requester.connected then
        requester.print(member_tag .. " declined your buddy request.")
        pen_gui.build_pen_gui(requester)
    end
end

return M
