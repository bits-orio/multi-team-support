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
local helpers   = require("scripts.helpers")

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

--- Hide + lock vanilla base planets for a team force. Safe to call at any
--- time — it doesn't touch per-team variant locks, so it can run after
--- every surface-creation event without clobbering planet-discovery
--- research the team has already completed.
---
--- Reasons to call this:
---   - Space Age lazily creates a base planet's surface when something
---     first touches it. We re-hide on on_surface_created so the newly-
---     created surface stays invisible to teams.
---   - Defensive top-up: base planets should always be locked for teams.
function planet_map.hide_base_planets_for(force)
    if not is_team_force(force.name) then return end

    -- Always hide the default nauvis surface from team forces. Teams have
    -- either a cloned surface (base 2.0 / VoidBlock) or a planet variant
    -- (Space Age); they never play on the shared default nauvis.
    --
    -- Note: hiding in Platformer mode used to trigger a Factorio SurfaceList
    -- engine quirk that dumped god-mode players onto the landing-pen after
    -- escaping a remote view. That's now mitigated by the god_pre_remote
    -- save/restore in control.lua's on_player_controller_changed handler,
    -- so hiding is safe in all modes.
    local default_nauvis = game.surfaces["nauvis"]
    if default_nauvis and default_nauvis.valid then
        helpers.set_surface_hidden(force, default_nauvis, true)
    end

    if not space_age.is_active() then return end

    -- Lock and hide all base planets (Space Age only).
    -- Use game.planets[base].surface rather than game.surfaces[base] because
    -- in Space Age planet surfaces are created lazily; the canonical access
    -- for a planet's surface goes through LuaPlanet. (This matches Team Starts.)
    for _, base in ipairs(space_age.BASE_PLANETS) do
        pcall(function() force.lock_space_location(base) end)
        local planet = game.planets and game.planets[base]
        if planet and planet.surface and planet.surface.valid then
            helpers.set_surface_hidden(force, planet.surface, true)
        end
    end
end

--- Hide base planets for every force.
function planet_map.hide_base_planets_for_all()
    for _, force in pairs(game.forces) do
        planet_map.hide_base_planets_for(force)
    end
end

--- Full reset of a team force's space-location locks:
---   - Hide + lock all base planets
---   - LOCK all of this team's non-home variants (clean slate — wipes any
---     planet-discovery research the previous slot occupant completed)
---   - UNLOCK the team's home (nauvis) variant
---
--- ONLY call this in situations where wiping unlocked variants is the
--- intended behavior:
---   - on_init / on_configuration_changed (fresh world)
---   - Slot recycle (new occupant gets a clean map)
---   - on_force_reset / on_technology_effects_reset (engine wiped research)
---
--- Do NOT call from periodic events (on_surface_created, etc.) — it will
--- repeatedly clobber planet-discovery unlocks and make the "space map"
--- button vanish every time a space platform is built.
function planet_map.apply_force_locks(force)
    if not is_team_force(force.name) then return end

    planet_map.hide_base_planets_for(force)
    if not space_age.is_active() then return end

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

--- Apply locks for all team forces. Same caveat as apply_force_locks.
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
