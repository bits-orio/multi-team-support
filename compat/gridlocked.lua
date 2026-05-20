-- Multi-Team Support - compat/gridlocked.lua
-- Author: bits-orio
-- License: MIT
--
-- Compatibility with Gridlocked by _CodeGreen.
-- https://mods.factorio.com/mod/gridlocked
--
-- Gridlocked gives each force a "chunk points" pool (storage.points[force.index]).
-- MTS recycles force slots: when a team disbands, force.reset() is called and the
-- slot is handed to the next player. force.reset() wipes research (including the
-- infinite gl-additional-chunk levels that earned the points) but NOT
-- storage.points, so a recycled team would inherit the previous occupant's balance.
--
-- Gridlocked exposes reset_force(force_index) in its remote interface, which
-- resets the balance to the gl-starting-chunks setting and refreshes every member's
-- HUD label. We call it on on_team_created and on_team_released so every team
-- starts from a clean slate regardless of what the previous occupant did.

local remote_api = require("scripts.remote_api")

local M = {}

function M.is_active()
    return script.active_mods["gridlocked"] ~= nil
end

local function reset_force_points(force_name)
    if not remote.interfaces["gridlocked"] then return end
    local force = game.forces[force_name]
    if not (force and force.valid) then return end
    remote.call("gridlocked", "reset_force", force.index)
end

function M.register_events()
    if not M.is_active() then return end

    script.on_event(remote_api.events.on_team_created, function(e)
        reset_force_points(e.force_name)
    end)

    script.on_event(remote_api.events.on_team_released, function(e)
        reset_force_points(e.force_name)
    end)
end

return M
