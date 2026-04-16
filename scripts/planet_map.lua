-- Multi-Team Support - planet_map.lua
-- Author: bits-orio
-- License: MIT
--
-- Runtime mapping between team forces and their Space Age planet variants.
-- Only meaningful when Space Age is active; otherwise these helpers no-op
-- and the mod falls back to surface cloning.
--
-- Storage layout:
--   storage.map_force_to_planets[force_name][base_planet] = variant_name
--   storage.map_planet_to_force[variant_name] = force_name
--
-- Example (team-1's mapping):
--   storage.map_force_to_planets["team-1"] = {
--     nauvis = "mts-nauvis-1", vulcanus = "mts-vulcanus-1", ...
--   }
--   storage.map_planet_to_force["mts-nauvis-1"]   = "team-1"
--   storage.map_planet_to_force["mts-vulcanus-1"] = "team-1"

local space_age = require("scripts.space_age")

-- NOTE: We deliberately do NOT require("scripts.force_utils") here because
-- force_utils requires this module at load time — a circular require
-- would return a stale (half-loaded) force_utils table. Instead we
-- inline the two tiny helpers we need below.

local planet_map = {}

local function max_teams()
    return settings.startup["mts_max_teams"].value
end

local function is_team_force(force_name)
    return force_name:find("^team%-") ~= nil
end

-- ─── Storage ─────────────────────────────────────────────────────────

function planet_map.init_storage()
    storage.map_force_to_planets = storage.map_force_to_planets or {}
    storage.map_planet_to_force  = storage.map_planet_to_force  or {}
end

-- ─── Build Mappings ──────────────────────────────────────────────────

--- Build the force↔planet bidirectional maps based on team_pool slots.
--- Call on_init (after create_team_pool) and on_configuration_changed.
--- Idempotent: rebuilds from scratch each call.
function planet_map.build()
    planet_map.init_storage()
    if not space_age.is_active() then return end

    local max = max_teams()
    storage.map_force_to_planets = {}
    storage.map_planet_to_force  = {}

    for slot = 1, max do
        local force_name = "team-" .. slot
        local per_team = {}
        for _, base in ipairs(space_age.BASE_PLANETS) do
            local variant = space_age.variant_name(base, slot)
            -- Only include variants that were actually created at data stage.
            -- `game.planets` is the canonical runtime accessor for planets in
            -- Factorio 2.0 (LuaPrototypes has no `planet` key). Team Starts
            -- uses this same pattern.
            if game.planets and game.planets[variant] then
                per_team[base] = variant
                storage.map_planet_to_force[variant] = force_name
            end
        end
        storage.map_force_to_planets[force_name] = per_team
    end
end

-- ─── Lookups ─────────────────────────────────────────────────────────

--- Return the variant name for a team + base planet, or nil.
---   get_variant("team-1", "nauvis") -> "mts-nauvis-1"
function planet_map.get_variant(force_name, base_planet)
    local map = (storage.map_force_to_planets or {})[force_name]
    return map and map[base_planet] or nil
end

--- Return the team force name that owns a variant planet, or nil.
function planet_map.get_force_by_planet(variant_name)
    return (storage.map_planet_to_force or {})[variant_name]
end

--- Return the team's home planet name (their nauvis variant).
function planet_map.get_home_planet(force_name)
    return planet_map.get_variant(force_name, "nauvis")
end

-- ─── Force Setup ─────────────────────────────────────────────────────

--- Apply Space Age space-location locks for a team force:
---   - Lock all base planets so they can't travel there
---   - Hide the base planet surfaces from this force's map
---   - Lock all of this team's non-home variants (clean slate on recycle)
---   - Unlock only the team's nauvis variant as their starting location
--- Call once per team force at on_init, on_configuration_changed, and
--- whenever a team slot is recycled (so a new occupant starts with a
--- clean tech+location state).
function planet_map.apply_force_locks(force)
    if not is_team_force(force.name) then return end

    -- Only hide base planet surfaces when Space Age is active (teams then
    -- use variant planets and should never see the stock bases).
    --
    -- In base 2.0 / Platformer mode, DO NOT hide the default nauvis: doing
    -- so desyncs Factorio's internal surface-list indexing (SurfaceList.cpp
    -- "Surface list picked index N" errors) and the engine falls back to
    -- teleporting the player onto the landing-pen surface. Teams on base 2.0
    -- already have their own team-N-nauvis clone — the stock nauvis remaining
    -- visible just means it's an extra (unused) entry in the surface list.
    if not space_age.is_active() then return end

    -- Lock and hide all base planets (Space Age only).
    -- Use game.planets[base].surface rather than game.surfaces[base] because
    -- in Space Age planet surfaces are created lazily; the canonical access
    -- for a planet's surface goes through LuaPlanet. (This matches Team Starts.)
    -- This loop also covers the base "nauvis" planet.
    for _, base in ipairs(space_age.BASE_PLANETS) do
        pcall(function() force.lock_space_location(base) end)
        local planet = game.planets and game.planets[base]
        if planet and planet.surface and planet.surface.valid then
            force.set_surface_hidden(planet.surface, true)
        end
    end

    local home = planet_map.get_home_planet(force.name)

    -- Lock every variant owned by this team except home (prevents discovery-tech
    -- unlocks from a previous occupant leaking to the new one).
    local per_team = (storage.map_force_to_planets or {})[force.name] or {}
    for _, variant in pairs(per_team) do
        if variant ~= home then
            pcall(function() force.lock_space_location(variant) end)
        end
    end

    -- Unlock the team's home (nauvis variant)
    if home then
        pcall(function() force.unlock_space_location(home) end)
    end
end

--- Apply locks for all team forces.
function planet_map.apply_all_force_locks()
    for _, force in pairs(game.forces) do
        planet_map.apply_force_locks(force)
    end
end

-- ─── Surface Creation ────────────────────────────────────────────────

--- Get or create the surface for a planet by name. Returns nil on failure.
function planet_map.get_or_create_planet_surface(planet_name)
    local planet = game.planets and game.planets[planet_name]
    if not (planet and planet.valid) then return nil end
    local surface = planet.surface
    if not (surface and surface.valid) then
        -- create_surface triggers lazy generation of the planet's surface
        surface = planet.create_surface()
    end
    if surface and surface.valid then
        surface.request_to_generate_chunks({0, 0}, 1)
    end
    return surface
end

-- ─── Discovery Tech Hook ─────────────────────────────────────────────

-- Map of "planet-discovery-X" tech names to their base planet name.
local DISCOVERY_TECHS = {
    ["planet-discovery-vulcanus"] = "vulcanus",
    ["planet-discovery-gleba"]    = "gleba",
    ["planet-discovery-fulgora"]  = "fulgora",
    ["planet-discovery-aquilo"]   = "aquilo",
}

--- If the finished tech is a planet discovery, unlock the team's variant
--- and lock the base. Called from tech_records on_research_finished hook.
--- Returns true if handled, false if unrelated.
function planet_map.on_research_finished(tech)
    if not space_age.is_active() then return false end
    local base = DISCOVERY_TECHS[tech.name]
    if not base then return false end
    local force = tech.force
    if not is_team_force(force.name) then return false end

    local variant = planet_map.get_variant(force.name, base)
    if variant then
        pcall(function() force.unlock_space_location(variant) end)
        -- Defensive: re-lock the base in case some other event unlocked it
        pcall(function() force.lock_space_location(base) end)
    end
    return true
end

return planet_map
