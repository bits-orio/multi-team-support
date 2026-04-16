-- Multi-Team Support - tech_records.lua
-- Author: bits-orio
-- License: MIT
--
-- Tracks first/fastest research records per technology across all teams.
-- Announces "first to research" and "new speed record" to all players.
--
-- Uses the shared records module for first/fastest logic.
-- Uses team clocks (storage.team_clock_start) for elapsed-time measurement.

local records       = require("records")
local helpers       = require("helpers")
local force_utils   = require("force_utils")
local planet_map    = require("planet_map")

local tech_records = {}

--- Ensure storage is initialized.
function tech_records.init_storage()
    storage.tech_records        = storage.tech_records        or {}
    storage.tech_research_ticks = storage.tech_research_ticks or {}
end

--- Handler for on_research_finished.
--- Records the research tick and checks for first/fastest records.
function tech_records.on_research_finished(event)
    local tech  = event.research
    local force = tech.force

    -- Only track team forces (skip player/enemy/neutral/spectator)
    if not force_utils.is_team_force(force.name) then return end

    tech_records.init_storage()

    -- Record the raw tick for legacy research diff UI
    storage.tech_research_ticks[force.name] = storage.tech_research_ticks[force.name] or {}
    storage.tech_research_ticks[force.name][tech.name] = game.tick

    -- Space Age: unlock team's variant planet for planet-discovery techs.
    -- No-op when Space Age is inactive or tech isn't a discovery.
    planet_map.on_research_finished(tech)

    -- Update first/fastest records
    local result = records.update(storage.tech_records, tech.name, force.name, game.tick)

    local team_tag = helpers.team_tag(force.name)
    local tech_tag = helpers.tech_rich_name(tech.name)

    if result.is_first then
        helpers.broadcast(string.format(
            "[Records] %s was the first to research %s!",
            team_tag, tech_tag
        ))
    elseif result.is_fastest then
        local prev = result.previous_fastest
        local new_entry = storage.tech_records[tech.name].fastest
        helpers.broadcast(string.format(
            "[Records] %s is fastest to research %s in %s (previous record: %s in %s)",
            team_tag,
            tech_tag,
            helpers.format_elapsed(new_entry.elapsed),
            helpers.team_tag(prev.team),
            helpers.format_elapsed(prev.elapsed)
        ))
    end
end

return tech_records
