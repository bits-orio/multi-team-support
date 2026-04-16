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
--   }
--
-- `elapsed` is measured from the team's clock start (team birth), so a team
-- that joins the game later isn't penalized for absolute time.

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

return records
