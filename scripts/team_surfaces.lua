-- Multi-Team Support - scripts/team_surfaces.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- create / retire an EPHEMERAL, caller-seeded surface for a team, for the
-- mts-v1 API (warp-style consumers like MTS Dimension Warp).
--
-- Create path: the caller supplies the full map_gen_settings (including a
-- deterministic per-warp seed) and a NON-VARIANT name (must NOT match
-- mts-<planet>-N or team-N-<planet>, so normalize_variant_seed leaves the
-- caller's seed intact). We register force<->surface ownership, then
-- game.create_surface with the caller's settings. The engine then fires
-- on_surface_created, whose handler (events/ticks.lua) runs the existing flow
-- — normalize (skips it, non-variant) -> visibility -> spawn_labels.draw ->
-- raise_team_surface_created — against the ownership we registered first. Works
-- with or without Space Age (game.create_surface needs no planet).
--
-- Retire path: delete ONLY the named surface and unwind only its bookkeeping
-- (map entries + player_surfaces). It must NOT use cleanup_force_surfaces, which
-- deletes the WHOLE force's surfaces -- during a warp the team also owns the
-- just-created destination surface, which that would wrongly wipe. No event is
-- raised, so setup/teardown stay a predictable matched pair.

-- No cycle now: remote_api injects this module (set_deferred_deps) rather than
-- requiring it, so team_surfaces -> surface_utils is a one-way edge.
local surface_utils = require("scripts.surface_utils")

local team_surfaces = {}

-- Surface names whose on_team_surface_created raise is deferred until
-- create_team_surface finishes planet association + spawn-chunk pre-gen. Set and
-- cleared within a single synchronous create_team_surface call, so a plain
-- upvalue is desync-safe (every peer runs the same code path in the same tick).
local deferred = {}

-- remote_api.raise_team_surface_created, injected at load time (this module must
-- NOT require remote_api -- see header). Doing the re-raise here rather than in
-- the mts-v1 wrapper means BOTH callers of create_team_surface get it (the wrapper
-- and the internal compat/mts_dimension_warp path).
local raise_hook = nil

function team_surfaces.set_raise_hook(fn) raise_hook = fn end

--- True while create_team_surface is mid-build for this surface name. The
--- events/ticks.lua on_surface_created handler checks this to SUPPRESS its inline
--- on_team_surface_created raise, so consumers don't see the surface before it has
--- a planet or any generated chunks; we re-raise once it is fully formed.
function team_surfaces.is_deferring(name)
    return deferred[name] == true
end

local function is_team_force(force_name)
    return type(force_name) == "string" and force_name:find("^team%-") ~= nil
end

-- ─── Create ───────────────────────────────────────────────────────────

--- Create an ephemeral, caller-seeded surface for a team.
--- @param force_name string
--- @param spec table  { name = "mdw-vulcanus-w5", planet = "vulcanus", map_gen_settings = {...} }
---   name              REQUIRED, must be non-variant (not mts-<planet>-N / team-N-<planet>)
---   planet            base planet name; used only for Space Age association
---   map_gen_settings  the surface's settings, including the caller's seed
--- @return string|nil  the created surface name, or nil on failure
function team_surfaces.create_team_surface(force_name, spec)
    if not is_team_force(force_name) then return nil end
    spec = spec or {}
    local name = spec.name
    local base = spec.planet or "nauvis"
    if type(name) ~= "string" or name == "" then return nil end

    local force = game.forces[force_name]
    if not (force and force.valid) then return nil end

    -- Ownership of these ephemeral surfaces lives in a DEDICATED map that
    -- planet_map.build() never rewrites (the variant maps it does rewrite are
    -- regenerated from scratch on every on_configuration_changed, which used to
    -- orphan every surface registered here). See surface_utils.get_owner.
    storage.surface_owner_overrides = storage.surface_owner_overrides or {}

    -- Idempotent: if the surface already exists, RE-ASSERT ownership and return.
    -- Re-asserting is what lets a consumer (e.g. MTS Dimension Warp) HEAL
    -- ownership that an earlier wipe dropped -- the old early-return wrote nothing,
    -- so a re-call could never repair a lost entry.
    if game.surfaces[name] then
        storage.surface_owner_overrides[name] = force_name
        return name
    end

    -- Register ownership BEFORE creation so the engine's on_surface_created
    -- handler resolves get_owner -> this force (driving visibility/labels).
    storage.surface_owner_overrides[name] = force_name

    -- Defer the on_team_surface_created event: game.create_surface raises
    -- on_surface_created synchronously (events/ticks.lua), which would otherwise
    -- fire on_team_surface_created right now -- before the surface has a planet
    -- or any generated chunks. The marker makes the ticks.lua handler skip that
    -- inline raise; we re-raise below once the surface is fully formed.
    deferred[name] = true

    -- Create with the caller's settings (seed included). The non-variant name
    -- means normalize_variant_seed leaves that seed untouched.
    local ok, surface = pcall(function() return game.create_surface(name, spec.map_gen_settings) end)
    if not (ok and surface and surface.valid) then
        deferred[name] = nil
        storage.surface_owner_overrides[name] = nil
        return nil
    end

    -- Associate to the planet (non-nauvis) so Space Age planet mechanics apply.
    local planet = game.planets and game.planets[base]
    if planet and planet.valid and base ~= "nauvis" then
        pcall(function() planet.associate_surface(surface) end)
    end

    -- Pre-generate the spawn area so a later clone/teleport lands on real terrain.
    surface.request_to_generate_chunks({0, 0}, 3)
    surface.force_generate_chunk_requests()

    -- Surface now has its planet + spawn chunks: raise the deferred event so
    -- consumers (e.g. MTS Dimension Warp) see a fully-formed surface.
    deferred[name] = nil
    if raise_hook then raise_hook(surface.name, force_name) end

    return surface.name
end

-- ─── Retire ───────────────────────────────────────────────────────────

--- Retire one surface owned by a team: delete it and unwind its bookkeeping.
--- @param force_name   string
--- @param surface_name string
--- @return boolean  true on success, false if the surface is invalid/not owned
---
--- Validate ownership, unwind ONLY this surface's bookkeeping, then delete just
--- this surface (game.delete_surface, async). Deliberately does NOT call
--- cleanup_force_surfaces, which deletes every surface the force owns --
--- including the destination surface the team just warped to.
function team_surfaces.retire_team_surface(force_name, surface_name)
    if not is_team_force(force_name) then return false end
    local surface = game.surfaces[surface_name]
    if not (surface and surface.valid) then return false end
    if surface_utils.get_owner(surface) ~= force_name then return false end

    -- Unwind ownership for THIS surface only. The override map is where ephemeral
    -- ownership now lives; the legacy variant-map unwinds are kept defensively for
    -- old saves that still have stray entries.
    if storage.surface_owner_overrides then storage.surface_owner_overrides[surface_name] = nil end
    if storage.map_planet_to_force then storage.map_planet_to_force[surface_name] = nil end
    local per_team = (storage.map_force_to_planets or {})[force_name]
    if per_team then
        for base, variant in pairs(per_team) do
            if variant == surface_name then per_team[base] = nil end
        end
    end

    -- Drop any player home references to the retired surface.
    storage.player_surfaces = storage.player_surfaces or {}
    for idx, ps in pairs(storage.player_surfaces) do
        if ps.name == surface_name then storage.player_surfaces[idx] = nil end
    end

    -- Delete ONLY this surface (async; fires on_surface_deleted later).
    game.delete_surface(surface)
    return true
end

return team_surfaces
