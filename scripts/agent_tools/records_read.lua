-- Multi-Team Support - scripts/agent_tools/records_read.lua
-- Author: bits-orio
-- License: MIT
--
-- Reads over the record tables scripts/records.lua writes, for the agent
-- tools: what a team holds, what it finished, and the replay that counts how
-- often it beat the fastest time standing when it finished. Pure reads.
--
-- A record names a slot ("team-4"), never a person. Releasing a slot strips
-- its entries and recomputes first and fastest from the survivors
-- (team_slots.strip_team_from_records), so everything here describes teams
-- still on the server.
--
-- A first-only record is a milestone a mod registered with a first
-- threshold (milestones/external_keys.lua). The engine announces who got
-- there first and never races its time, though records.update stores a
-- fastest for it anyway. Here it is a first record only: nobody holds its
-- fastest and nobody beats it.

local helpers       = require("scripts.helpers")
local reply         = require("scripts.agent_tools.reply")
local external_keys = require("milestones.external_keys")

local M = {}

local TABLES = { tech = "tech_records", milestone = "milestone_records" }
local ALL_KINDS = { "tech", "milestone" }

--- The kinds one `kind` argument covers, or nil for a word it does not know.
function M.kinds(kind)
    if kind == nil or kind == "any" then return ALL_KINDS end
    if TABLES[kind] then return { kind } end
    return nil
end

--- Calls fn(kind, key, record, first_only) for every record of the given
--- kinds; first_only is true on a first-only record.
function M.each(kinds, fn)
    local first_only = external_keys.first_only()
    for _, kind in ipairs(kinds) do
        for key, rec in pairs(storage[TABLES[kind]] or {}) do
            if type(rec) == "table" then
                fn(kind, key, rec, kind == "milestone" and first_only[key] == true)
            end
        end
    end
end

local function usable(e)
    return type(e) == "table" and type(e.team) == "string"
        and type(e.tick) == "number" and type(e.elapsed) == "number"
end

--- Every team that finished a record, once each: its entries, plus first and
--- fastest when a save from before entries existed never filled them in
--- (records.update backfills them the same way).
function M.finishers(rec)
    local out, seen = {}, {}
    local function add(e)
        if usable(e) and not seen[e.team] then
            seen[e.team] = true
            out[#out + 1] = e
        end
    end
    for _, e in pairs(rec.entries or {}) do add(e) end
    add(rec.first)
    add(rec.fastest)
    return out
end

--- The entry `team` has on a record, or nil when it never finished it.
function M.entry_of(rec, team)
    local e = rec.entries and rec.entries[team]
    if usable(e) and e.team == team then return e end
    if usable(rec.first) and rec.first.team == team then return rec.first end
    if usable(rec.fastest) and rec.fastest.team == team then return rec.fastest end
    return nil
end

--- What `team` holds on a record now: "both", "first", "fastest" or nil.
--- Only "first" or nil on a first-only record.
function M.holds(rec, team, first_only)
    local first   = usable(rec.first)   and rec.first.team   == team
    local fastest = not first_only and usable(rec.fastest) and rec.fastest.team == team
    if first and fastest then return "both" end
    if first then return "first" end
    if fastest then return "fastest" end
    return nil
end

--- The time to beat: the standing fastest, or first on a record that has no
--- fastest. Nil on a record nobody has finished.
function M.best(rec)
    if usable(rec.fastest) then return rec.fastest end
    if usable(rec.first) then return rec.first end
    return nil
end

--- Replay order: by tick, and within one tick by slot, the order the
--- milestone poll visits teams, so two identical games replay alike.
local function replay_before(a, b)
    if a.tick ~= b.tick then return a.tick < b.tick end
    local sa, sb = helpers.team_slot(a.team) or 0, helpers.team_slot(b.team) or 0
    if sa ~= sb then return sa < sb end
    return a.team < b.team
end

--- How many times each team beat the fastest time standing when it
--- finished, replaying the record's finishers in the order they finished.
--- The first finisher beats nothing. Equal is not a beat, as in
--- records.update. Only surviving teams take part. Nobody beats a
--- first-only record: there is no time to beat.
function M.beats(rec, first_only)
    if first_only then return {} end
    local list = M.finishers(rec)
    table.sort(list, replay_before)
    local wins, standing = {}, nil
    for _, e in ipairs(list) do
        if standing ~= nil and e.elapsed < standing then
            wins[e.team] = (wins[e.team] or 0) + 1
        end
        if standing == nil or e.elapsed < standing then standing = e.elapsed end
    end
    return wins
end

local function new_tally()
    return { first = 0, fastest = 0, held = 0, finished = 0 }
end

--- Adds one record to one team's tally. Returns the team's entry and what it
--- holds, nil when it never finished the record.
local function credit(t, rec, team, first_only)
    local e = M.entry_of(rec, team)
    if not e then return nil end
    t.finished = t.finished + 1
    local holds = M.holds(rec, team, first_only)
    if holds then
        t.held = t.held + 1
        if holds ~= "fastest" then t.first = t.first + 1 end
        if holds ~= "first" then t.fastest = t.fastest + 1 end
    end
    return e, holds
end

local function held_row(kind, key, holds, e)
    return {
        kind          = kind,
        what          = key,
        holds         = holds,
        elapsed_hours = reply.hours(e.elapsed),
        online_hours  = reply.hours(e.online_elapsed),
    }
end

--- One team over the given kinds: its tally plus set_fastest_ever, and the
--- records it holds as rows, newest first.
function M.team(kinds, team)
    local t, held = new_tally(), {}
    t.set_fastest_ever = 0
    M.each(kinds, function(kind, key, rec, first_only)
        local e, holds = credit(t, rec, team, first_only)
        if not e then return end
        t.set_fastest_ever = t.set_fastest_ever + (M.beats(rec, first_only)[team] or 0)
        if holds then
            held[#held + 1] = { tick = e.tick, row = held_row(kind, key, holds, e) }
        end
    end)
    table.sort(held, function(a, b)
        if a.tick ~= b.tick then return a.tick > b.tick end
        if a.row.kind ~= b.row.kind then return a.row.kind < b.row.kind end
        return a.row.what < b.row.what
    end)
    local rows = {}
    for i, h in ipairs(held) do rows[i] = h.row end
    return t, rows
end

--- Every team's tally over the given kinds, keyed by force name. A team
--- that finished nothing has no tally.
function M.all_teams(kinds)
    local tallies = {}
    M.each(kinds, function(_, _, rec, first_only)
        for _, e in ipairs(M.finishers(rec)) do
            tallies[e.team] = tallies[e.team] or new_tally()
            credit(tallies[e.team], rec, e.team, first_only)
        end
    end)
    return tallies
end

M.new_tally = new_tally

return M
