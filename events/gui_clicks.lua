-- events/gui_clicks.lua
-- on_gui_click: nav dispatch, landing-pen spawn flow, buddy requests, module delegates.

local h             = require("events.helpers")
local nav           = require("gui.nav")
local confirm_gui   = require("gui.confirm")
local follow_cam    = require("gui.follow_cam")
local landing_pen   = require("gui.landing_pen")
local spectator     = require("scripts.spectator")
local force_utils   = require("scripts.force_utils")
local admin_gui     = require("gui.admin")
local research_gui  = require("gui.research")
local team_settings = require("gui.team_settings")
local stats_gui     = require("gui.stats")
local awards_gui    = require("gui.awards")
local teams_gui     = require("gui.teams")
local helpers       = require("scripts.helpers")

local M = {}

function M.register()
    script.on_event(defines.events.on_gui_click, function(event)
        local el = event.element
        if not el or not el.valid then return end

        if nav.dispatch_click(event) then return end
        if confirm_gui.on_gui_click(event) then return end
        if follow_cam.on_gui_click(event) then teams_gui.update_all(); return end

        if el.name == "sb_spawn_btn" then
            local player = game.get_player(event.player_index)
            if player and landing_pen.is_in_pen(player) then
                if spectator.is_spectating(player) then spectator.exit(player) end
                local force_name = force_utils.claim_team_slot(player)
                if not force_name then return end
                local default_group = game.permissions.get_group("Default")
                if default_group then default_group.add_player(player) end
                admin_gui.auto_populate_starter_items(player)
                landing_pen.grant_starter_items(player)
                landing_pen.finish_spawn(player)
                h.spawn_into_world(player)
                force_utils.start_player_clock(player)
                helpers.broadcast(helpers.colored_name(player.name, player.chat_color)
                    .. " has joined " .. helpers.team_tag(player.force.name) .. ".")
                h.refresh_all_gameplay_guis()
            end
            return
        end

        if el.name == "sb_buddy_request" then
            local player = game.get_player(event.player_index)
            if player and landing_pen.is_in_pen(player) and el.tags and el.tags.sb_target_index then
                local target = game.get_player(el.tags.sb_target_index)
                if target and target.connected and not landing_pen.is_in_pen(target) then
                    landing_pen.send_buddy_request(player, target)
                end
            end
            return
        end

        if el.name == "sb_buddy_accept" then
            local player = game.get_player(event.player_index)
            if player and el.tags and el.tags.sb_requester_index then
                landing_pen.accept_buddy_request(player, el.tags.sb_requester_index)
                h.refresh_all_gameplay_guis()
            end
            return
        end

        if el.name == "sb_buddy_reject" then
            local player = game.get_player(event.player_index)
            if player and el.tags and el.tags.sb_requester_index then
                landing_pen.reject_buddy_request(player, el.tags.sb_requester_index)
            end
            return
        end

        if el.name == "sb_buddy_cancel" then
            local player = game.get_player(event.player_index)
            if player and landing_pen.is_in_pen(player) then
                landing_pen.cancel_buddy_request(player)
            end
            return
        end

        if research_gui.on_gui_click(event)  then return end
        if admin_gui.on_gui_click(event)      then return end
        if team_settings.on_gui_click(event)  then return end
        if stats_gui.on_gui_click(event)      then return end
        if awards_gui.on_gui_click(event)     then return end
        teams_gui.on_gui_click(event)
    end)
end

return M
