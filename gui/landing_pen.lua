-- Multi-Team Support - landing_pen.lua
-- Author: bits-orio
-- License: MIT
--
-- A shared pre-game waiting surface ("Landing Pen") where all new players
-- land before spawning into the actual game.  Players see each other in the
-- pen and click "Spawn into game" when they're ready, so everyone can start
-- at roughly the same time.

local admin_gui = require("gui.admin")
local helpers   = require("helpers")
local terrain   = require("gui.landing_pen_terrain")

local landing_pen = {}

-- Re-export chunk handler (wired in control.lua)
landing_pen.on_chunk_generated = terrain.on_chunk_generated

local SURFACE_NAME = terrain.SURFACE_NAME

-- ─── Buddy Request GUI ─────────────────────────────────────────────────

local function show_buddy_request_gui(target, requester)
    if target.gui.screen.sb_buddy_req_frame then
        target.gui.screen.sb_buddy_req_frame.destroy()
    end
    local frame = target.gui.screen.add{
        type = "frame", name = "sb_buddy_req_frame", direction = "vertical",
    }
    frame.auto_center = true

    local title_bar = helpers.add_title_bar(frame, "Buddy Request")

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

function landing_pen.is_in_pen(player)
    storage.spawned_players = storage.spawned_players or {}
    return not storage.spawned_players[player.index]
end

function landing_pen.place_player(player)
    local surface = terrain.get_or_create_surface()
    storage.pen_slots = storage.pen_slots or {}

    if not storage.pen_slots[player.index] then
        local used = {}
        for _, s in pairs(storage.pen_slots) do used[s] = true end
        local slot = 0
        while used[slot] do slot = slot + 1 end
        storage.pen_slots[player.index] = slot
    end

    if player.surface == surface then
        local spec_group = game.permissions.get_group("spectator")
        if spec_group then spec_group.add_player(player) end
        landing_pen.build_pen_gui(player)
        landing_pen.update_pen_gui_all()
    else
        storage.pending_pen_tp = storage.pending_pen_tp or {}
        storage.pending_pen_tp[player.index] = {
            surface  = surface,
            position = terrain.get_spawn_position(storage.pen_slots[player.index]),
        }
    end
end

function landing_pen.process_pending_teleports()
    if not storage.pending_pen_tp then return end
    if not next(storage.pending_pen_tp) then return end
    local done = {}
    for player_index, tp in pairs(storage.pending_pen_tp) do
        local player = game.get_player(player_index)
        if player and player.valid and tp.surface and tp.surface.valid then
            if player.controller_type == defines.controllers.cutscene then
                player.exit_cutscene()
            end
            local ok = player.teleport(tp.position, tp.surface)
            if ok then
                local solo_force = game.forces["player-" .. player.name]
                if solo_force and player.force ~= solo_force then
                    player.force = solo_force
                end
                local spec_group = game.permissions.get_group("spectator")
                if spec_group then spec_group.add_player(player) end
                done[#done + 1] = player_index
            end
        else
            done[#done + 1] = player_index
        end
    end
    for _, idx in ipairs(done) do
        storage.pending_pen_tp[idx] = nil
    end
    if #done > 0 then
        for _, idx in ipairs(done) do
            local player = game.get_player(idx)
            if player and player.connected then
                landing_pen.build_pen_gui(player)
            end
        end
        landing_pen.update_pen_gui_all()
    end
end

-- ���── Pen GUI ───────────────────────────────────────────────────────────

--- Add the in-pen player list to the frame.
local function add_pen_player_list(frame, viewer)
    local in_pen = {}
    for _, p in pairs(game.players) do
        if landing_pen.is_in_pen(p) then
            in_pen[#in_pen + 1] = p
        end
    end
    if #in_pen == 0 then return end

    local hdr = frame.add{type = "label", caption = "In the pen:"}
    hdr.style.font        = "default-bold"
    hdr.style.left_margin = 4
    hdr.style.top_margin  = 4
    for _, p in ipairs(in_pen) do
        local lbl = frame.add{type = "label", caption = "  \xE2\x80\xA2 " .. p.name}
        lbl.style.left_margin = 4
        if p.connected then
            lbl.style.font_color = p.chat_color
        else
            lbl.style.font_color = {0.65, 0.65, 0.65}
        end
    end
end

--- Add the already-spawned player list to the frame.
local function add_spawned_player_list(frame)
    storage.spawned_players = storage.spawned_players or {}
    local spawned = {}
    for idx in pairs(storage.spawned_players) do
        local p = game.get_player(idx)
        if p then spawned[#spawned + 1] = p end
    end
    if #spawned == 0 then return end

    table.sort(spawned, function(a, b) return a.name < b.name end)
    local hdr = frame.add{type = "label", caption = "Already spawned:"}
    hdr.style.font        = "default-bold"
    hdr.style.left_margin = 4
    hdr.style.top_margin  = 6
    for _, p in ipairs(spawned) do
        local lbl = frame.add{type = "label", caption = "  \xE2\x80\xA2 " .. p.name}
        lbl.style.left_margin = 4
        if p.connected then
            lbl.style.font_color = p.chat_color
        else
            lbl.style.font_color = {0.5, 0.5, 0.5}
        end
    end
end

--- Add the buddy-join section to the frame.
local function add_buddy_section(frame, player)
    if not admin_gui.flag("buddy_join_enabled") then return end
    storage.buddy_requests = storage.buddy_requests or {}
    local my_request = storage.buddy_requests[player.index]
    local active = {}
    for _, p in pairs(game.players) do
        if p.connected and not landing_pen.is_in_pen(p) then
            active[#active + 1] = p
        end
    end
    table.sort(active, function(a, b) return a.name < b.name end)
    if #active == 0 then return end

    frame.add{type = "line"}.style.top_margin = 4
    local hdr = frame.add{type = "label", caption = "Join as buddy:"}
    hdr.style.font        = "default-bold"
    hdr.style.left_margin = 4
    hdr.style.top_margin  = 4

    for _, p in ipairs(active) do
        local row = frame.add{type = "flow", direction = "horizontal"}
        row.style.vertical_align           = "center"
        row.style.left_margin              = 4
        row.style.horizontally_stretchable = true
        local lbl = row.add{type = "label", caption = p.name}
        lbl.style.font_color    = p.chat_color
        lbl.style.minimal_width = 100
        if my_request == p.index then
            local pending = row.add{type = "label", caption = "Pending..."}
            pending.style.font       = "default-small"
            pending.style.font_color = {1, 1, 0.4}
        elseif not my_request then
            row.add{
                type = "button", name = "sb_buddy_request", caption = "Request",
                style = "button", tags = {sb_target_index = p.index},
                tooltip = "Ask " .. p.name .. " if you can join their team",
            }
        end
    end
end

function landing_pen.build_pen_gui(player)
    storage.pen_gui_location = storage.pen_gui_location or {}
    local frame = helpers.reuse_or_create_frame(
        player, "sb_pen_frame", storage.pen_gui_location, {x = 5, y = 80})
    -- reuse_or_create_frame uses clear(), but pen GUI needs destroy+recreate
    -- because it doesn't have a collapse toggle. Actually it works fine with clear.

    helpers.add_title_bar(frame, "Landing Pen")

    local sub = frame.add{type = "label", caption = "Wait here, then spawn when ready."}
    sub.style.top_margin    = 6
    sub.style.bottom_margin = 4
    sub.style.left_margin   = 4

    add_pen_player_list(frame, player)
    add_spawned_player_list(frame)

    frame.add{type = "line"}.style.top_margin = 6
    local btn = frame.add{
        type = "button", name = "sb_spawn_btn", caption = "Spawn into game",
        style = "confirm_button",
    }
    btn.style.top_margin              = 4
    btn.style.bottom_margin           = 2
    btn.style.horizontally_stretchable = true

    add_buddy_section(frame, player)
end

function landing_pen.update_pen_gui_all()
    local surface = game.surfaces[SURFACE_NAME]
    if not surface then return end
    for _, player in pairs(game.players) do
        if player.connected and player.surface == surface and landing_pen.is_in_pen(player) then
            landing_pen.build_pen_gui(player)
        end
    end
end

-- ─── Spawn & Buddy ────────────────────────────────────────────────────

function landing_pen.finish_spawn(player)
    storage.spawned_players = storage.spawned_players or {}
    storage.spawned_players[player.index] = true
    if storage.pen_slots then storage.pen_slots[player.index] = nil end
    if player.gui.screen.sb_pen_frame then
        player.gui.screen.sb_pen_frame.destroy()
    end
    landing_pen.update_pen_gui_all()
end

function landing_pen.rebuild_buddy_request_guis()
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

function landing_pen.send_buddy_request(requester, target)
    storage.buddy_requests = storage.buddy_requests or {}
    storage.buddy_requests[requester.index] = target.index
    show_buddy_request_gui(target, requester)
    landing_pen.build_pen_gui(requester)
end

function landing_pen.accept_buddy_request(target, requester_index)
    storage.buddy_requests = storage.buddy_requests or {}
    storage.buddy_requests[requester_index] = nil

    if target.gui.screen.sb_buddy_req_frame then
        target.gui.screen.sb_buddy_req_frame.destroy()
    end

    local requester = game.get_player(requester_index)
    if not (requester and requester.valid) then return end

    requester.force = target.force
    local default_group = game.permissions.get_group("Default")
    if default_group then default_group.add_player(requester) end
    landing_pen.finish_spawn(requester)
    local spawn_pos = target.surface.find_non_colliding_position(
        "character", target.position, 10, 1
    ) or target.position
    requester.teleport(spawn_pos, target.surface)
    storage.player_clock_start = storage.player_clock_start or {}
    if not storage.player_clock_start[requester.index] then
        storage.player_clock_start[requester.index] = game.tick
    end

    target.print(requester.name .. " has joined your team.")
    if requester.connected then
        requester.print("You joined " .. target.name .. "'s team.")
    end
end

function landing_pen.reject_buddy_request(target, requester_index)
    storage.buddy_requests = storage.buddy_requests or {}
    storage.buddy_requests[requester_index] = nil

    if target.gui.screen.sb_buddy_req_frame then
        target.gui.screen.sb_buddy_req_frame.destroy()
    end

    local requester = game.get_player(requester_index)
    if requester and requester.connected then
        requester.print(target.name .. " declined your buddy request.")
        landing_pen.build_pen_gui(requester)
    end
end

return landing_pen
