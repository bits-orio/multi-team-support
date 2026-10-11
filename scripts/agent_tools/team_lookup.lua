-- Multi-Team Support - scripts/agent_tools/team_lookup.lua
-- Author: bits-orio
-- License: MIT
--
-- Which team an agent tool call is about. The bridge injects `force` on every
-- call, and a model often writes the name players use ("Team Ace") rather
-- than the force ("team-1"), so every tool resolves it the same way here.

local helpers = require("scripts.helpers")
local reply   = require("scripts.agent_tools.reply")

local M = {}

M.NOT_A_TEAM = "not a team force; teams are named team-1, team-2 and so on"
M.UNCLAIMED  = "no team holds this slot now; a disbanded team's records are gone with it"

--- Every slot number from 1 to the highest in storage.team_pool, ascending,
--- the walk remote_api's get_team_list makes, so a lookup that could match
--- two teams resolves the same way on every peer.
local function slots()
    local n = 0
    for slot in pairs(storage.team_pool or {}) do
        if slot > n then n = slot end
    end
    local out = {}
    for slot = 1, n do out[slot] = slot end
    return out
end

--- Slot numbers a team holds right now, ascending.
function M.claimed_slots()
    local out = {}
    for _, slot in ipairs(slots()) do
        if storage.team_pool[slot] == "occupied" then out[#out + 1] = slot end
    end
    return out
end

--- Whether a team holds this force's slot right now.
function M.is_claimed(force_name)
    local slot = helpers.team_slot(force_name)
    return slot ~= nil and (storage.team_pool or {})[slot] == "occupied"
end

--- A team force from whatever the caller wrote: the force name, the display
--- name ("Team 02", "Team Ace"), or a slot spelled with a space ("team 2"),
--- case-insensitive. Nil when nothing matches. The reply still names the
--- force, so a caller that came in by label leaves with the name.
function M.force_from(text)
    if type(text) ~= "string" then return nil end
    if helpers.is_team_force(text) and game.forces[text] then return text end
    local wanted = text:lower():gsub("^%s+", ""):gsub("%s+$", "")
    local slot = wanted:match("^team[%s%-]+0*(%d+)$")
    if slot and game.forces["team-" .. slot] then return "team-" .. slot end
    for _, n in ipairs(slots()) do
        local force_name = "team-" .. n
        local force = game.forces[force_name]
        if force and force.valid and helpers.team_display(force_name):lower() == wanted then
            return force_name
        end
    end
    return nil
end

--- The found=false reply for a force the caller named. The name is the
--- caller's own text when nothing matched, so it goes back clipped.
function M.not_found(force_name, reason)
    return { found = false, force = reply.echo(force_name), reason = reason }
end

--- The claimed team a tool call names, or nil and the found=false reply to
--- send instead. Errors when force is missing, as every bridge tool does.
function M.claimed_team(args)
    local wanted = type(args) == "table" and args.force or nil
    if type(wanted) ~= "string" then error("force is required", 0) end
    local force_name = M.force_from(wanted) or wanted
    if not (helpers.is_team_force(force_name) and game.forces[force_name]) then
        return nil, M.not_found(force_name, M.NOT_A_TEAM)
    end
    if not M.is_claimed(force_name) then
        return nil, M.not_found(force_name, M.UNCLAIMED)
    end
    return force_name
end

return M
