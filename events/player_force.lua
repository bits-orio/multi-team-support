-- events/player_force.lua
-- on_player_changed_force, on_player_promoted, on_player_demoted, on_player_died

local remote_api    = require("scripts.remote_api")
local team_settings = require("gui.team_settings")
local force_utils   = require("scripts.force_utils")
local admin_gui     = require("gui.admin")
local pop_text      = require("scripts.pop_text")

local M = {}

function M.register()
    script.on_event(defines.events.on_player_changed_force, function(event)
        -- Public mts-v1: translate force changes into player_joined_team /
        -- player_left_team events before our own handlers run.
        remote_api.on_player_changed_force(event)

        local player = game.get_player(event.player_index)
        if player and player.connected then
            team_settings.refresh_nav_button(player)
            if player.gui.screen.sb_team_settings_frame then
                team_settings.build_gui(player)
            end
        end
    end)

    script.on_event(defines.events.on_player_promoted, function(event)
        local player = game.get_player(event.player_index)
        if player and player.connected then
            admin_gui.refresh_nav_button(player)
        end
    end)

    script.on_event(defines.events.on_player_demoted, function(event)
        local player = game.get_player(event.player_index)
        if player then
            admin_gui.refresh_nav_button(player)
            if player.gui.screen.sb_admin_frame then
                player.gui.screen.sb_admin_frame.destroy()
            end
        end
    end)

    script.on_event(defines.events.on_player_died, function(event)
        local player = game.get_player(event.player_index)
        if player and force_utils.is_team_force(player.force.name) then
            pop_text.rip(player, player.position)
        end
    end)
end

return M
