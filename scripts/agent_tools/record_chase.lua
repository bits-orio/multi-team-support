-- Multi-Team Support - scripts/agent_tools/record_chase.lua
-- Author: bits-orio
-- License: MIT
--
-- The `record_chase` agent tool: for one team, every record it does not
-- hold and whether it still could. The tool gives the verdict and the model
-- reports it, for the reason the bridge's rank_by_rate exists: a model left
-- to compare figures gets the arithmetic right and the verdict wrong.
-- Pure read.

local helpers      = require("scripts.helpers")
local reply        = require("scripts.agent_tools.reply")
local team_lookup  = require("scripts.agent_tools.team_lookup")
local records_read = require("scripts.agent_tools.records_read")

local DEFAULT_ROWS = 20
local MAX_ROWS     = 100

local M = {}

M.manifest = {
    desc = "Records one team does not hold, and which it can still take. Only speed is left to win: "
        .. "first is gone once another team got there, so a milestone that counts first only is never in reach. "
        .. "A record is in reach while the team has not finished it and its own clock, running since the team "
        .. "started playing, is under the record time. Equal is out, "
        .. "and so is one it finished slower. rows: in reach, closing soonest first; hours_left is the time "
        .. "until its clock passes the record. Answer 'can I still beat the records' with in_reach and "
        .. "out_of_reach.",
    params = {
        kind  = "enum<tech,milestone,any> tech is research, milestone is production; default any",
        limit = "integer rows, default " .. DEFAULT_ROWS .. ", max " .. MAX_ROWS,
    },
}

--- The team's clock now. A staged team whose leader has not pressed Start
--- Playing has no clock yet; it starts from zero, so it is zero here.
local function elapsed_now(force_name)
    local start = (storage.team_clock_start or {})[force_name]
    if not start then return 0, false end
    return game.tick - start, true
end

--- "held", "out", or "in" plus the record to beat; nil for a record nobody
--- has finished. A first-only record has no time to beat, so it is out for
--- every team but the one that got there first.
local function verdict(rec, force_name, now, first_only)
    local best = records_read.best(rec)
    if not best then return nil end
    if records_read.holds(rec, force_name, first_only) then return "held" end
    if first_only or records_read.entry_of(rec, force_name) then return "out" end
    if now < best.elapsed then return "in", best end
    return "out"
end

local function chase(kinds, force_name, now)
    local counts, open = { held = 0, ["in"] = 0, out = 0 }, {}
    records_read.each(kinds, function(kind, key, rec, first_only)
        local v, best = verdict(rec, force_name, now, first_only)
        if not v then return end
        counts[v] = counts[v] + 1
        if v == "in" and best then
            open[#open + 1] = { kind = kind, what = key, holder = best.team,
                                record = best.elapsed, left = best.elapsed - now }
        end
    end)
    table.sort(open, function(a, b)
        if a.left ~= b.left then return a.left < b.left end
        if a.kind ~= b.kind then return a.kind < b.kind end
        return a.what < b.what
    end)
    return counts, open
end

local function row_of(o)
    return {
        kind = o.kind, what = o.what, holder = o.holder,
        record_hours = reply.hours(o.record), hours_left = reply.hours(o.left),
    }
end

function M.call(args)
    local kinds = records_read.kinds(type(args) == "table" and args.kind or nil)
    if not kinds then error("kind must be tech, milestone or any", 0) end
    local force_name, refusal = team_lookup.claimed_team(args)
    if not force_name then return refusal end
    local now, started = elapsed_now(force_name)
    local counts, open = chase(kinds, force_name, now)
    local rows = {}
    for i, o in ipairs(reply.cut(open, reply.limit(args.limit, DEFAULT_ROWS, MAX_ROWS))) do
        rows[i] = row_of(o)
    end
    -- Only said when it is news: a staged team waiting on Start Playing.
    local clock_started
    if not started then clock_started = false end
    return reply.fit(rows, function(shown)
        return {
            found = true, force = force_name, label = helpers.team_display(force_name),
            kind = args.kind or "any", elapsed_hours = reply.hours(now), clock_started = clock_started,
            held = counts.held, in_reach = counts["in"], out_of_reach = counts.out,
            total = #open, shown = #shown, rows = shown,
        }
    end)
end

return M
