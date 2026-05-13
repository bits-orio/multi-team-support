-- gui/landing_pen.lua
-- Core landing pen operations + facade re-exporting pen GUI and buddy requests.

local helpers          = require("scripts.helpers")
local terrain          = require("gui.landing_pen_terrain")
local force_utils      = require("scripts.force_utils")
local pen_gui          = require("gui.pen_gui")
local pen_ops          = require("gui.pen_ops")
local buddy_requests   = require("gui.buddy_requests")

local landing_pen = {}

-- Re-export chunk handler (wired in control.lua)
landing_pen.on_chunk_generated = terrain.on_chunk_generated

local SURFACE_NAME = terrain.SURFACE_NAME

-- ─── Core State ────────────────────────────────────────────────────────

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
            helpers.diag("landing_pen.process_pending_teleports: TELEPORT → "
                .. tp.surface.name, player)
            local ok = player.teleport(tp.position, tp.surface)
            if ok then
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
            if player and player.connected then landing_pen.build_pen_gui(player) end
        end
        landing_pen.update_pen_gui_all()
    end
end

-- ─── Return to Pen ────────────────────────────────────────────────────

function landing_pen.return_to_pen(player)
    storage.buddy_requests = storage.buddy_requests or {}
    for req_idx, tgt_idx in pairs(storage.buddy_requests) do
        if tgt_idx == player.index then
            storage.buddy_requests[req_idx] = nil
            local requester = game.get_player(req_idx)
            if requester and requester.connected then
                requester.print(helpers.colored_name(player.name, player.chat_color)
                    .. " is no longer available for buddy join.")
                landing_pen.build_pen_gui(requester)
            end
        end
    end

    if player.gui.screen.sb_buddy_req_frame then
        player.gui.screen.sb_buddy_req_frame.destroy()
    end
    for _, frame_name in pairs({"sb_platforms_frame", "sb_research_frame",
                                "sb_stats_frame", "sb_return_button_frame"}) do
        if player.gui.screen[frame_name] then player.gui.screen[frame_name].destroy() end
    end

    -- Mark as not spawned BEFORE die/teleport so events mid-flow see the player as in the pen.
    storage.spawned_players = storage.spawned_players or {}
    storage.spawned_players[player.index] = nil

    if player.character then player.character.die() end

    local surface = terrain.get_or_create_surface()
    storage.pen_slots = storage.pen_slots or {}
    if not storage.pen_slots[player.index] then
        local used = {}
        for _, s in pairs(storage.pen_slots) do used[s] = true end
        local slot = 0
        while used[slot] do slot = slot + 1 end
        storage.pen_slots[player.index] = slot
    end
    local pos = terrain.get_spawn_position(storage.pen_slots[player.index])

    local spec_group = game.permissions.get_group("spectator")
    if spec_group then spec_group.add_player(player) end

    if not player.connected then
        landing_pen.update_pen_gui_all()
        return
    end

    if not player.character then
        player.set_controller({type = defines.controllers.god})
    end
    helpers.diag("landing_pen.return_to_pen: TELEPORT → " .. surface.name, player)
    player.teleport(pos, surface)
    if not player.character then player.create_character() end
    pen_ops.grant_starter_items(player)
    landing_pen.build_pen_gui(player)
    landing_pen.update_pen_gui_all()
end

-- ─── Re-exports ────────────────────────────────────────────────────────

landing_pen.grant_starter_items     = pen_ops.grant_starter_items
landing_pen.finish_spawn            = pen_ops.finish_spawn

landing_pen.build_pen_gui           = pen_gui.build_pen_gui
landing_pen.update_pen_gui_all      = pen_gui.update_pen_gui_all

landing_pen.team_has_room           = buddy_requests.team_has_room
landing_pen.rebuild_buddy_request_guis = buddy_requests.rebuild_buddy_request_guis
landing_pen.send_buddy_request      = buddy_requests.send_buddy_request
landing_pen.accept_buddy_request    = buddy_requests.accept_buddy_request
landing_pen.cancel_buddy_request    = buddy_requests.cancel_buddy_request
landing_pen.reject_buddy_request    = buddy_requests.reject_buddy_request

return landing_pen
