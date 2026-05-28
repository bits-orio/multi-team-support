-- Multi-Team Support - compat/reassign_player_force.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- Generic fix for naturally-generated structures stuck on force="player"
-- on team surfaces. Observed cases:
--   • Nauvis freeplay crash-site-spaceship-* wreck pieces.
--   • Fulgora ruins and the Fulgoran lightning attractor (Space Age).
--   • Krastorio 2's kr-spaceship-* additions, plus crash-site-chest-1/2.
--   • Any modded equivalent we don't know about yet.
--
-- The common failure: force="player" entities are not mineable by team
-- forces even with set_cease_fire + set_friend. clone_mirror copies these
-- entities verbatim from the source planet (where they belong to the real
-- "player" force, which has no players in MTS) onto each team surface,
-- where they then sit there un-interactable.
--
-- Fix: after clone_mirror has placed the chunk, sweep every force="player"
-- entity in the chunk and reassign it to the team that owns the surface.
-- Nothing else is touched — minable and destructible are left at whatever
-- the prototype (or another script) set them to, so we don't accidentally
-- override an intentional minable=false on a scripted-scenario entity.
-- The previous "unmineable" symptom was a pure consequence of the force
-- mismatch; once force matches, mining works because the prototype's
-- default already says it should.
--
-- Cross-force diplomacy doesn't enter the picture in MTS because each
-- team has its own surface variant (mts-<planet>-<N> / team-<N>-<planet>)
-- and only that team's players are ever standing on it — so making the
-- team the owner is both safe and preserves entity behavior the team
-- would otherwise lose (naturally-spawned power poles wiring into the
-- team's electric grid, chests joining the team's logistic network,
-- bot-repair on attractors, etc.).
--
-- Filtering by force is cheap when nothing matches — find_entities_filtered
-- returns an empty array without iterating the chunk's full entity set.

local surface_utils = require("scripts.surface_utils")

local M = {}

function M.on_chunk_generated(event)
    local surface = event.surface
    if not (surface and surface.valid) then return end

    local owner = surface_utils.get_owner(surface)
    if not owner then return end

    for _, entity in pairs(surface.find_entities_filtered{
        area  = event.area,
        force = "player",
    }) do
        if entity.valid then
            entity.force = owner
        end
    end
end

return M
