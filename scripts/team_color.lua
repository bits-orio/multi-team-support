-- scripts/team_color.lua
-- A team's colour follows its LEADER's colour. Adoption used to be a 60-tick
-- poll (no colour event existed before Factorio 2.1); it is now driven by
-- on_player_color_changed (events/player_lifecycle.lua) plus direct calls after
-- script-side colour writes (join fix, /mts-fixcolors) -- force adoption must
-- never depend on whether the engine echoes a SCRIPT write as an event, so the
-- writers call in themselves. Idempotent and cheap by construction.

local spawn_labels  = require("scripts.spawn_labels")
local h             = require("events.helpers")
local awards_gui    = require("gui.awards")
local follow_cam    = require("gui.follow_cam")
local team_settings = require("gui.team_settings")

local M = {}

-- Adopt leader colour onto the force and refresh every GUI that renders team
-- colours. custom_color is a FORCE property -- writing it cannot re-fire the
-- player colour event, so this path is reentrancy-safe.
local function adopt(force_name, force, leader)
    local c, fc = leader.color, force.custom_color
    if fc
        and math.abs(c.r - fc.r) <= 0.001
        and math.abs(c.g - fc.g) <= 0.001
        and math.abs(c.b - fc.b) <= 0.001
    then
        return false
    end
    force.custom_color = c
    spawn_labels.refresh_for_force(force_name)
    h.refresh_all_gameplay_guis()
    awards_gui.update_all()
    follow_cam.rebuild_all()
    team_settings.update_all_for_force(force_name)
    return true
end

--- If `player` leads a team and their colour drifted from the force colour,
--- adopt it (no-op for non-leaders and settled colours).
function M.adopt_if_leader(player)
    if not (player and player.valid and player.connected) then return end
    for force_name, leader_idx in pairs(storage.team_leader or {}) do
        if leader_idx == player.index then
            local force = game.forces[force_name]
            if force and force.valid then adopt(force_name, force, player) end
            return
        end
    end
end

--- Sweep every connected team leader once -- used after bulk recolours
--- (/mts-fixcolors) where many players changed in one pass.
function M.adopt_all()
    for force_name, leader_idx in pairs(storage.team_leader or {}) do
        local force  = game.forces[force_name]
        local leader = game.get_player(leader_idx)
        if force and force.valid and leader and leader.valid and leader.connected then
            adopt(force_name, force, leader)
        end
    end
end

return M
