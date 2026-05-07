-- events/player_lifecycle.lua
-- on_player_created, on_player_joined_game, on_player_left_game

local h            = require("events.helpers")
local helpers      = require("scripts.helpers")
local admin_gui    = require("gui.admin")
local landing_pen  = require("gui.landing_pen")
local spectator    = require("scripts.spectator")
local force_utils  = require("scripts.force_utils")
local follow_cam   = require("gui.follow_cam")
local teams_gui    = require("gui.teams")

local M = {}

function M.register()
    script.on_event(defines.events.on_player_created, function(event)
        local player = game.get_player(event.player_index)
        h.register_nav_buttons(player)
        admin_gui.auto_populate_starter_items(player)

        if admin_gui.flag("landing_pen_enabled") then
            local spec_force = game.forces["spectator"]
            if spec_force then player.force = spec_force end
            landing_pen.place_player(player)
        else
            force_utils.claim_team_slot(player)
            storage.spawned_players = storage.spawned_players or {}
            storage.spawned_players[player.index] = true
            h.spawn_into_world(player)
            force_utils.start_player_clock(player)
        end
        teams_gui.update_all()
    end)

    script.on_event(defines.events.on_player_joined_game, function(event)
        local player = game.get_player(event.player_index)
        if player then spectator.on_player_joined(player) end
        if player and landing_pen.is_in_pen(player) then
            landing_pen.place_player(player)
        end
        if player then h.register_nav_buttons(player) end
        storage.pending_admin_check = storage.pending_admin_check or {}
        storage.pending_admin_check[event.player_index] = game.tick + 30
        h.rebuild_for_connectivity(nil)

        if player then
            storage.seen_players = storage.seen_players or {}
            local discord_url = settings.global["mts_discord_url"].value
            if not storage.seen_players[player.index] then
                storage.seen_players[player.index] = true
                local msg = "Welcome " .. player.name .. "!"
                if discord_url ~= "" then
                    msg = msg .. " Join our Discord for reset notifications: " .. discord_url
                end
                helpers.broadcast(msg)
            else
                local msg
                if force_utils.is_team_force(player.force.name) then
                    msg = "Welcome back " .. player.name .. " " .. helpers.team_tag_with_leader(player.force.name) .. "!"
                else
                    msg = "Welcome back " .. player.name .. "!"
                end
                helpers.broadcast(msg)
            end
        end
    end)

    script.on_event(defines.events.on_player_left_game, function(event)
        local player = game.get_player(event.player_index)
        if player then
            spectator.on_player_left(player)
            follow_cam.on_player_left(player)
            storage.player_last_seen = storage.player_last_seen or {}
            storage.player_last_seen[player.index] = game.tick
        end
        h.rebuild_for_connectivity(event.player_index)
    end)
end

return M
