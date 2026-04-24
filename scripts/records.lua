-- Multi-Team Support - records.lua
-- Author: bits-orio
-- License: MIT
--
-- Shared first/fastest record tracking for any keyed event.
-- Used by tech_records (per technology) and milestones (per category:item:threshold).
--
-- Record structure:
--   records[key] = {
--     first   = { team = force_name, tick = game.tick, elapsed = ticks },
--     fastest = { team = force_name, tick = game.tick, elapsed = ticks },
--     entries = { [force_name] = { team, tick, elapsed } }   -- every finisher
--   }
--
-- `elapsed` is measured from the team's clock start (team birth), so a team
-- that joins the game later isn't penalized for absolute time.
-- `entries` is keyed by force_name so each team is counted once per achievement;
-- the Awards GUI consumes this to render top-N leaderboards.

local records = {}

--- Compute elapsed ticks since a team's clock started.
--- Returns nil if the team has no clock yet (shouldn't happen for claimed teams).
local function get_elapsed(force_name, tick)
    local clock = (storage.team_clock_start or {})[force_name]
    if not clock then return nil end
    return tick - clock
end

--- Update first/fastest records for a given key.
--- Returns a result table describing what changed:
---   { is_first = bool, is_fastest = bool, previous_fastest = {team, tick, elapsed} or nil }
--- Note: when is_first is true, is_fastest is false (would be redundant to announce both).
function records.update(records_table, key, force_name, tick)
    records_table[key] = records_table[key] or {}
    local entry = records_table[key]

    local elapsed = get_elapsed(force_name, tick)
    if not elapsed then return { is_first = false, is_fastest = false } end

    -- Backfill entries from first/fastest for saves created before the
    -- leaderboard tracking was added.
    entry.entries = entry.entries or {}
    if entry.first and not entry.entries[entry.first.team] then
        entry.entries[entry.first.team] = entry.first
    end
    if entry.fastest and not entry.entries[entry.fastest.team] then
        entry.entries[entry.fastest.team] = entry.fastest
    end

    -- Record this team's completion (only the first time — second calls for
    -- the same team are no-ops; callers already dedupe per-threshold).
    if not entry.entries[force_name] then
        entry.entries[force_name] = { team = force_name, tick = tick, elapsed = elapsed }
    end

    -- First record for this key?
    if not entry.first then
        entry.first   = { team = force_name, tick = tick, elapsed = elapsed }
        entry.fastest = { team = force_name, tick = tick, elapsed = elapsed }
        -- Skip announcing "fastest" on the initial record (it's implied by "first")
        return { is_first = true, is_fastest = false }
    end

    -- New fastest record?
    if elapsed < entry.fastest.elapsed then
        local previous = entry.fastest
        entry.fastest = { team = force_name, tick = tick, elapsed = elapsed }
        return { is_first = false, is_fastest = true, previous_fastest = previous }
    end

    return { is_first = false, is_fastest = false }
end

--- Return an array of all finishers for a record, sorted by elapsed ascending.
--- Empty array if the record doesn't exist or has no finishers yet.
function records.sorted_entries(record)
    local out = {}
    if not (record and record.entries) then return out end
    for _, e in pairs(record.entries) do out[#out + 1] = e end
    table.sort(out, function(a, b) return a.elapsed < b.elapsed end)
    return out
end

return records
