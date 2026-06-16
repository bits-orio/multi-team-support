-- Multi-Team Support - scripts/team_surfaces.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- create / retire a team's planet-variant surface for the mts-v1 API.
--
-- These are thin WIRING functions: they own ONLY the bidirectional
-- force<->planet map bookkeeping, then delegate everything else to the existing
-- MTS machinery so there is exactly one implementation of seed pinning,
-- ownership, visibility, labels and the on_team_surface_created event.
--
-- Create path (design note #2): we register the map entries and then ask
-- planet_map to (lazily) create the surface. The engine then fires
-- on_surface_created, whose handler (events/ticks.lua) runs the WHOLE existing
-- flow — normalize_variant_seed -> on_surface_created visibility ->
-- spawn_labels.draw -> raise_team_surface_created — against the now-registered
-- ownership. We deliberately do NOT re-run any of those here.
--
-- Retire path: delegate deletion + player_surfaces cleanup to
-- team_slots.cleanup_force_surfaces (covers cloned + variant + platforms), then
-- unwind only the map entries for the retired variant. No event is raised, so
-- setup/teardown stay a predictable matched pair.

local planet_map = require("scripts.planet_map")
local space_age  = require("scripts.space_age")

local team_surfaces = {}

local function is_team_force(force_name)
    return type(force_name) == "string" and force_name:find("^team%-") ~= nil
end

-- ─── Create ───────────────────────────────────────────────────────────

--- Create (or look up) a team's variant surface for a base planet.
--- @param force_name string
--- @param spec table  { planet = "nauvis", map_gen_settings = ..., name = ... }
--- @return string|nil  the created surface name, or nil on failure
---
--- Only Space Age variant creation is supported here (design note #1); legacy
--- clones are created by the compat layer and cleaned by cleanup_force_surfaces.
function team_surfaces.create_team_surface(force_name, spec)
    if not is_team_force(force_name) then return nil end
    if not space_age.is_active() then return nil end
    spec = spec or {}
    local base = spec.planet or "nauvis"

    local force = game.forces[force_name]
    if not (force and force.valid) then return nil end

    -- Look up the variant this team should own for the base planet. The variant
    -- surfaces were created at the data stage by prototypes/planets.lua; here we
    -- only resolve the NAME.
    local variant = planet_map.get_variant(force_name, base)
    if not variant then return nil end

    -- Register ownership BEFORE the surface exists, so the on_surface_created
    -- handler's surface_utils.get_owner already resolves to this force when the
    -- engine fires the event during creation below.
    storage.map_force_to_planets = storage.map_force_to_planets or {}
    storage.map_force_to_planets[force_name] = storage.map_force_to_planets[force_name] or {}
    storage.map_force_to_planets[force_name][base] = variant
    storage.map_planet_to_force = storage.map_planet_to_force or {}
    storage.map_planet_to_force[variant] = force_name

    -- Create (or fetch) the surface. This triggers on_surface_created, which
    -- runs the full existing setup flow against the ownership we just wrote.
    local surface = planet_map.get_or_create_planet_surface(variant)
    if not (surface and surface.valid) then
        -- Roll back the map write so a failed create leaves no dangling owner.
        storage.map_force_to_planets[force_name][base] = nil
        storage.map_planet_to_force[variant] = nil
        return nil
    end

    return surface.name
end

-- ─── Retire ───────────────────────────────────────────────────────────

--- Retire one surface owned by a team: delete it and unwind its bookkeeping.
--- @param force_name   string
--- @param surface_name string
--- @return boolean  true on success, false if the surface is invalid/not owned
---
--- cleanup_force_surfaces deletes EVERY surface the force owns. To retire a
--- single surface we first validate ownership, then let cleanup run (it is the
--- one grounded deletion path covering clones + variants + platforms + the
--- player_surfaces registry), then strip only the retired variant's map
--- entries. (A future per-surface delete could be narrower; for v1 we reuse the
--- existing whole-force cleanup since retire is paired with team teardown.)
function team_surfaces.retire_team_surface(force_name, surface_name)
    if not is_team_force(force_name) then return false end
    local surface = game.surfaces[surface_name]
    if not (surface and surface.valid) then return false end

    -- Verify ownership via the single grounded owner check.
    local surface_utils = require("scripts.surface_utils")
    if surface_utils.get_owner(surface) ~= force_name then return false end

    -- Delegate deletion + player_surfaces cleanup (covers clones, variants,
    -- platforms). Required circular-safe: team_slots requires remote_api which
    -- requires this module path indirectly, so require lazily inside the fn.
    local team_slots = require("scripts.team_slots")
    team_slots.cleanup_force_surfaces(force_name)

    -- Unwind the map entries for the retired variant specifically.
    local by_planet = storage.map_planet_to_force or {}
    by_planet[surface_name] = nil
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

    return true
end

return team_surfaces
