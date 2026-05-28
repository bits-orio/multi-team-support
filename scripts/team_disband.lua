-- Multi-Team Support - scripts/team_disband.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- Implements the mts-v1 `disband_team` action. It lives in its own module so it
-- can require both team_slots and landing_pen (which together would form a
-- circular require with remote_api) and inject the implementation back into
-- remote_api. Nothing else requires this module, so it's a safe leaf.

local team_slots  = require("scripts.team_slots")
local landing_pen = require("gui.landing_pen")
local spectator   = require("scripts.spectator")
local remote_api  = require("scripts.remote_api")

--- Disband a team entirely: every member back to the pen, slot freed, surfaces
--- cleaned up. Reuses the normal leave flow (remove_from_team disbands + cleans
--- up on the last member removed; return_to_pen relocates each player).
local function disband(force_name)
    if type(force_name) ~= "string" or not force_name:match("^team%-%d+$") then return end
    local force = game.forces[force_name]
    if not (force and force.valid) then return end

    local members = {}
    for _, p in pairs(force.players) do members[#members + 1] = p end

    if #members == 0 then
        team_slots.cleanup_force_surfaces(force_name)
        team_slots.release_team_slot(force_name)
        return
    end

    for _, p in pairs(members) do
        if p and p.valid then
            if spectator.is_spectating(p) then spectator.exit(p) end
            team_slots.remove_from_team(p)
            landing_pen.return_to_pen(p)
        end
    end
end

remote_api.disband_impl = disband

return { disband = disband }
