-- Multi-Team Support - compat/gridlocked.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
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

local remote_safe = require("compat.remote_safe")

local M = {}

function M.is_active()
    return script.active_mods["gridlocked"] ~= nil
end

local function reset_force_points(force_name)
    local force = game.forces[force_name]
    if not (force and force.valid) then return end
    -- remote_safe.call guards both the interface and the reset_force function
    -- existing before calling (CG-2).
    remote_safe.call("gridlocked", "reset_force", force.index)
end

-- Plain handlers fanned out from the single MTS-owned dispatcher in
-- events/ticks.lua. Factorio keeps only ONE script.on_event per event id per
-- mod, so the shims can't each register on_team_created/on_team_released (they'd
-- clobber each other -- CC-1). Each self-guards on is_active().
function M.on_team_created(e)
    if not M.is_active() then return end
    reset_force_points(e.force_name)
end

function M.on_team_released(e)
    if not M.is_active() then return end
    reset_force_points(e.force_name)
end

return M
