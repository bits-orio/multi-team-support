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
local remote_api   = require("scripts.remote_api")
local team_clock   = require("scripts.team_clock")

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
            -- The auto-claim on first connect coincides with on_player_joined_game's
            -- team-aware bridge message, so flag it to suppress the duplicate team-join.
            storage.odb_suppress_claim = storage.odb_suppress_claim or {}
            storage.odb_suppress_claim[player.index] = true
            force_utils.claim_team_slot(player)
            storage.spawned_players = storage.spawned_players or {}
            storage.spawned_players[player.index] = true
            storage.pending_spawn_pop = storage.pending_spawn_pop or {}
            storage.pending_spawn_pop[player.index] = player.force.name
            h.spawn_into_world(player)
            force_utils.start_player_clock(player)
            team_clock.refresh(player.force.name)
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

            -- Team-aware connect announcement to the Open Discord Bridge (replaces the
            -- bridge's team-less baseline player_joined, which we disable on init).
            remote_api.emit_player_joined(player)

            -- Resume the team's online clock if this is the first member back.
            team_clock.refresh(player.force.name)
        end
    end)

    -- Re-fit a maximized follow cam when the player resizes the window or
    -- changes UI scale, so it keeps filling the screen.
    local function refit_follow_cam(event)
        local player = game.get_player(event.player_index)
        if player then follow_cam.on_display_changed(player) end
    end
    script.on_event(defines.events.on_player_display_resolution_changed, refit_follow_cam)
    script.on_event(defines.events.on_player_display_scale_changed, refit_follow_cam)

    script.on_event(defines.events.on_player_left_game, function(event)
        local player = game.get_player(event.player_index)
        if player then
            -- Team-aware disconnect announcement to the bridge (replaces the team-less
            -- baseline player_left). Emitted while the player's force is still their team.
            remote_api.emit_player_left(player)
            spectator.on_player_left(player)
            follow_cam.on_player_left(player)
            storage.player_last_seen = storage.player_last_seen or {}
            storage.player_last_seen[player.index] = game.tick
            -- Freeze the team's online clock if this was the last member online.
            -- Exclude the leaver: the engine may not have dropped them from
            -- connected_players yet at this point.
            team_clock.refresh(spectator.get_effective_force(player), player.index)
        end
        h.rebuild_for_connectivity(event.player_index)
    end)
end

return M
