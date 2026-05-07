-- events/player_surface.lua
-- on_player_changed_surface, on_player_controller_changed

local spectator   = require("scripts.spectator")
local force_utils = require("scripts.force_utils")
local teams_gui   = require("gui.teams")
local helpers     = require("scripts.helpers")
local pop_text    = require("scripts.pop_text")

local M = {}

function M.register()
    script.on_event(defines.events.on_player_changed_surface, function(event)
        local player = game.get_player(event.player_index)
        if not (player and player.connected) then return end

        helpers.diag("on_player_changed_surface (before handlers)", player)
        if spectator.is_spectating(player)
           and player.controller_type ~= defines.controllers.remote then
            spectator.exit(player)
        end
        spectator.on_player_changed_surface(player)
        force_utils.bounce_if_foreign(player)
        teams_gui.build_gui(player)

        -- Fire spawn/join popups once the player has landed on their team
        -- surface (pending flag set in player_force.lua's on_player_changed_force).
        local pending = (storage.pending_spawn_pop or {})[player.index]
        if pending and force_utils.is_team_force(player.force.name)
           and player.surface.name ~= "landing-pen" then
            storage.pending_spawn_pop[player.index] = nil
            pop_text.spawn_confirm(player, player.position,
                "Welcome " .. helpers.colored_name(player.name, player.chat_color) .. "!")
            local force = player.force
            for _, mate in pairs(force.players) do
                if mate.connected and mate.index ~= player.index
                   and mate.surface.index == player.surface.index then
                    pop_text.team_join(mate, mate.position,
                        helpers.colored_name(player.name, player.chat_color) .. " joined!")
                end
            end
        end

        helpers.diag("on_player_changed_surface (after handlers)", player)
    end)

    script.on_event(defines.events.on_player_controller_changed, function(event)
        local player = game.get_player(event.player_index)
        if not (player and player.connected) then return end

        helpers.diag("on_player_controller_changed (before handlers, old_ctrl="
            .. tostring(event.old_type) .. ")", player)

        -- Anchor god-mode position across remote-view round-trips so pressing
        -- Esc in Platformer mode doesn't drop the god cursor onto the wrong surface.
        storage.god_pre_remote = storage.god_pre_remote or {}
        if event.old_type == defines.controllers.god
           and player.controller_type == defines.controllers.remote
           and player.physical_surface and player.physical_surface.valid then
            storage.god_pre_remote[player.index] = {
                surface_name = player.physical_surface.name,
                position     = { x = player.physical_position.x, y = player.physical_position.y },
            }
        elseif event.old_type == defines.controllers.remote
           and player.controller_type == defines.controllers.god then
            local saved = storage.god_pre_remote[player.index]
            storage.god_pre_remote[player.index] = nil
            if saved and player.physical_surface
               and player.physical_surface.name ~= saved.surface_name then
                local s = game.surfaces[saved.surface_name]
                if s and s.valid then
                    helpers.diag("god_pre_remote: restoring god to " .. saved.surface_name, player)
                    player.teleport(saved.position, s)
                end
            end
        end

        spectator.on_controller_changed(player, event.old_type)
        force_utils.bounce_if_foreign(player)
        helpers.diag("on_player_controller_changed (after handlers)", player)
    end)
end

return M
