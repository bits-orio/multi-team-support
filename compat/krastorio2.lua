-- Multi-Team Support - compat/krastorio2.lua
-- Author: bits-orio
-- License: MIT
--
-- Fixes crash-site entity interactability on team Nauvis surfaces.
-- Runs unconditionally — vanilla freeplay places crash-site-spaceship and
-- all wreck pieces with force="player" even without K2. When K2 base is
-- also loaded, the kr-spaceship-* pieces additionally arrive with
-- minable=false (K2's freeplay.lua hardcodes game.surfaces.nauvis so it
-- never flips them on team surfaces).
--
-- Problem: force="player" entities are not mineable by team forces even
-- with set_cease_fire + set_friend. Only force="neutral" entities are
-- universally mineable regardless of force diplomacy.
--
-- Fix: immediately after clone_mirror copies a chunk to a team Nauvis
-- surface, set force="neutral" and minable=true on all crash-site entities
-- in the chunk. Real nauvis is left untouched. K2-specific entity names
-- silently return no results when K2 base is not loaded.

local k2 = {}

local CRASH_SITE_ENTITIES = {
    -- Vanilla freeplay crash site
    "crash-site-spaceship",
    "crash-site-spaceship-wreck-big-1",
    "crash-site-spaceship-wreck-big-2",
    "crash-site-spaceship-wreck-medium-1",
    "crash-site-spaceship-wreck-medium-2",
    "crash-site-spaceship-wreck-medium-3",
    "crash-site-spaceship-wreck-small-1",
    "crash-site-spaceship-wreck-small-2",
    "crash-site-spaceship-wreck-small-3",
    "crash-site-spaceship-wreck-small-4",
    "crash-site-spaceship-wreck-small-5",
    "crash-site-spaceship-wreck-small-6",
    -- Krastorio 2 / K2 Spaced Out additions (force="player", minable gated by research on nauvis)
    "kr-spaceship-reactor",
    "kr-spaceship-research-computer",
    "kr-spaceship-material-fabricator-1",
    "kr-spaceship-material-fabricator-2",
    "crash-site-chest-1",
    "crash-site-chest-2",
}

-- Extract the base planet name from an MTS team surface name, or nil.
-- Mirrors clone_mirror's source_planet_for logic.
local function base_planet_of(surface_name)
    return surface_name:match("^mts%-(.+)%-%d+$")
        or surface_name:match("^team%-%d+%-(.+)$")
end

function k2.on_chunk_generated(event)
    local surface = event.surface
    if not (surface and surface.valid) then return end
    if base_planet_of(surface.name) ~= "nauvis" then return end

    for _, entity in pairs(surface.find_entities_filtered{ area = event.area, name = CRASH_SITE_ENTITIES }) do
        if entity.valid then
            entity.force        = "neutral"
            entity.minable      = true
            entity.destructible = true
        end
    end
end

return k2
