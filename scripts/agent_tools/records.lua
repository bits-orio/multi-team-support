-- Multi-Team Support - scripts/agent_tools/records.lua
-- Author: bits-orio
-- License: MIT
--
-- The `records` agent tool: what one team holds, or one row of counts per
-- claimed team. Its sweep block lets the bridge's sweep tool answer "which
-- team holds the most records" in one call (the contract is the comment at
-- the top of the companion's scripts/sweep/registry.lua). Pure read.
--
-- The sweep refuses a reply that shows fewer rows than its total, because a
-- ranking over the survivors of a cut names whoever survived. Full rows for
-- 60 teams, the most a server can have, fit the reply budget only while
-- every count is one digit: with 160 records finished by each team, 58 of
-- the 60 fit. So the sweep asks for held_only rows instead, force and held,
-- about 30 bytes each and 1.8 KB for all 60.

local helpers        = require("scripts.helpers")
local team_modifiers = require("scripts.team_modifiers")
local reply          = require("scripts.agent_tools.reply")
local team_lookup    = require("scripts.agent_tools.team_lookup")
local records_read   = require("scripts.agent_tools.records_read")

local DEFAULT_ROWS = 20
local MAX_ROWS     = 100

local M = {}

M.manifest = {
    desc = "Records one team holds. A record is first or fastest to research a technology or reach a "
        .. "production milestone, timed on the team's own clock since it started playing, never game time. "
        .. "Records belong to teams: a player's are their current team's. A disbanded team's are gone, so "
        .. "first means first among teams still here. first and fastest count what it holds now; a "
        .. "milestone a mod counts first only has no fastest. "
        .. "set_fastest_ever counts every time it beat the fastest time standing then, even if beaten since: "
        .. "that is how many records it broke. noncompetitive marks a team that has played with a "
        .. "handicap. rows: held, newest first. A milestone reads category:item@count, @0 the first one "
        .. "made. all=true counts every team, most held first.",
    params = {
        all       = "boolean default false: one row of counts per claimed team instead of one team's records; force is ignored",
        held_only = "boolean default false: with all=true, each row is just force and held, so every team fits even on the biggest server",
        kind      = "enum<tech,milestone,any> tech is research, milestone is production; default any",
        limit     = "integer rows for one team, default " .. DEFAULT_ROWS .. ", max " .. MAX_ROWS,
    },
    sweep = {
        axes = { "force" }, rows = "teams", name = "force", value = "held",
        unit = "records", metric = "records_held", args = { all = true, held_only = true },
    },
}

--- true for a team that ever played with a handicap (peaceful biters, say),
--- whose records the announcements tagged; absent for every other team.
local function noncompetitive(force_name)
    return team_modifiers.is_marked(force_name) or nil
end

local function kinds_of(args)
    local kinds = records_read.kinds(args.kind)
    if not kinds then error("kind must be tech, milestone or any", 0) end
    return kinds
end

local function one_team(args, kinds)
    local force_name, refusal = team_lookup.claimed_team(args)
    if not force_name then return refusal end
    local t, rows = records_read.team(kinds, force_name)
    local limited = reply.cut(rows, reply.limit(args.limit, DEFAULT_ROWS, MAX_ROWS))
    return reply.fit(limited, function(shown)
        return {
            found = true, force = force_name, label = helpers.team_display(force_name),
            kind = args.kind or "any", noncompetitive = noncompetitive(force_name),
            first = t.first, fastest = t.fastest, held = t.held, finished = t.finished,
            set_fastest_ever = t.set_fastest_ever,
            total = #rows, shown = #shown, rows = shown,
        }
    end)
end

--- One team's row in the all=true table. No label: the bridge prints a
--- force name as its label, so the model only ever reads force names, and a
--- label here would cost bytes on every row for nothing.
local function team_row(force_name, t, held_only)
    if held_only then return { force = force_name, held = t.held } end
    return {
        force = force_name,
        first = t.first, fastest = t.fastest, held = t.held, finished = t.finished,
        noncompetitive = noncompetitive(force_name),
    }
end

--- Every claimed team, zeros included, most held first.
local function every_team(args, kinds)
    local tallies = records_read.all_teams(kinds)
    local rows, slot_of = {}, {}
    for _, slot in ipairs(team_lookup.claimed_slots()) do
        local force_name = "team-" .. slot
        local row = team_row(force_name, tallies[force_name] or records_read.new_tally(), args.held_only == true)
        rows[#rows + 1] = row
        slot_of[row] = slot
    end
    table.sort(rows, function(a, b)
        if a.held ~= b.held then return a.held > b.held end
        return slot_of[a] < slot_of[b]
    end)
    return reply.fit(rows, function(shown)
        return { kind = args.kind or "any", total = #rows, shown = #shown, teams = shown }
    end)
end

function M.call(args)
    if type(args) ~= "table" then error("force is required", 0) end
    local kinds = kinds_of(args)
    if args.all == true then return every_team(args, kinds) end
    return one_team(args, kinds)
end

return M
