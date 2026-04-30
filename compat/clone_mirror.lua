-- Multi-Team Support - compat/clone_mirror.lua
-- Author: bits-orio
-- License: MIT
--
-- Generic terrain compatibility for any third-party mod that decorates
-- the real "nauvis" surface via on_chunk_generated and filters by
-- hardcoded surface name. When a chunk is generated on a team-N-nauvis
-- (or mts-nauvis-N) surface, this module:
--
--   1. Ensures the same chunk has been generated on real nauvis. That
--      synchronously fires every third-party mod's on_chunk_generated
--      handler (dangOreus, VoidBlock, Alien Biomes' autoplace, etc.)
--      against the nauvis surface, where their filters DO accept it.
--   2. Mirrors the resulting tiles + entities + decoratives from
--      nauvis to the team surface via clone_area.
--
-- Net effect: whatever the mod stack puts on nauvis, every team
-- surface gets the same. Per-team variety is traded for "same map
-- across teams", which suits the head-to-head race format MTS targets.
--
-- This handler is mod-agnostic. Adding a new terrain decorator does
-- not require any per-mod compat code on the MTS side as long as the
-- mod's logic ends up writing to nauvis. Per-mod shims are only
-- needed for runtime gameplay rules that fire AFTER chunk generation
-- (e.g. dangOreus's on_built_entity, on_entity_died, on_nth_tick) and
-- those tend to be small and stable.
--
-- Cost model: marginal cost per team chunk approaches 1× as the team
-- count grows, because nauvis is generated once per chunk-area and
-- amortized across all teams. The first team to explore a chunk pays
-- ~2×; subsequent teams exploring the same chunk pay ~1×.

local clone_mirror = {}

local CHUNK_SIZE = 32

--- Identify a team-owned planet variant and return the source planet
--- name to clone from, or nil if the surface is not a team variant.
---
--- Two naming schemes are recognized:
---   • "mts-<planet>-<N>"     — Space Age per-team variant
---   • "team-<N>-<planet>"    — base 2.0 cloned surface (no Space Age)
---
--- The captured planet name is returned verbatim and is used as the
--- key into `game.surfaces` to find the source. This works for any
--- planet — vanilla (nauvis, vulcanus, etc.) and modded (lignumis,
--- maraxsis, muluna, etc.). The patterns deliberately accept any
--- non-empty planet name, so a planet mod registered through any
--- path (data:extend, PlanetsLib:extend, etc.) cascades through the
--- variant naming and lands here automatically.
local function source_planet_for(team_surface_name)
    if not team_surface_name then return nil end
    -- Space Age variant: mts-<planet>-<N>
    local planet = team_surface_name:match("^mts%-(.+)%-%d+$")
    if planet then return planet end
    -- Non-Space-Age clone: team-<N>-<planet>
    planet = team_surface_name:match("^team%-%d+%-(.+)$")
    if planet then return planet end
    return nil
end

--- Hook from MTS's on_chunk_generated event. Cheap when the surface
--- isn't a team variant (early return). For team variants, drives the
--- matching planet's chunk to generate and clones the result.
---
--- Generalisation note: this used to be hardcoded to nauvis only. The
--- generalization to all planets means a chunk-decorating mod that
--- targets, say, Vulcanus (filtering by `surface.name == "vulcanus"`)
--- will see its decoration mirrored to every team's Vulcanus variant
--- with no per-mod compat code. dangOreus, VoidBlock, Alien Biomes,
--- and (vanilla) modded resource autoplaces all benefit equally.
function clone_mirror.on_chunk_generated(event)
    local team_surface = event.surface
    if not (team_surface and team_surface.valid) then return end

    local source_planet_name = source_planet_for(team_surface.name)
    if not source_planet_name then return end

    local source = game.surfaces[source_planet_name]
    if not (source and source.valid) then
        -- Source planet hasn't been instantiated yet (Factorio creates
        -- planet surfaces lazily in Space Age). Without the source we
        -- can't clone; skip silently. The next chunk-gen attempt will
        -- retry, and by then the source surface should exist.
        return
    end

    local cx, cy = event.position.x, event.position.y
    -- Drive the source planet to generate the same chunk if it hasn't
    -- already. Every mod that listens to on_chunk_generated for the
    -- source planet runs synchronously inside force_generate_chunk_requests.
    if not source.is_chunk_generated({cx, cy}) then
        source.request_to_generate_chunks(
            {cx * CHUNK_SIZE + CHUNK_SIZE / 2, cy * CHUNK_SIZE + CHUNK_SIZE / 2}, 0)
        source.force_generate_chunk_requests()
    end

    -- Mirror tiles + entities + decoratives. clone_area is synchronous
    -- and overwrites destination contents, so any vanilla worldgen
    -- that happened on the team surface a moment ago is replaced by
    -- the source planet's (post-mod-decoration) state.
    source.clone_area{
        source_area         = event.area,
        destination_area    = event.area,
        destination_surface = team_surface,
        clone_tiles         = true,
        clone_entities      = true,
        clone_decoratives   = true,
        expand_map          = false,
    }
end

return clone_mirror
