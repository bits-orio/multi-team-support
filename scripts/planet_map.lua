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
local pop_text  = require("scripts.pop_text")

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
    -- Cached map of tech_name -> base_planet_name. Rebuilt on
    -- on_configuration_changed via refresh_discovery_techs() so that
    -- adding a planet mod mid-save picks up the new discovery techs
    -- without requiring a fresh save.
    storage.discovery_tech_map   = storage.discovery_tech_map   or {}
end

-- ─── Build Mappings ──────────────────────────────────────────────────

--- Build the force↔planet bidirectional maps based on team_pool slots.
--- Call on_init (after create_team_pool) and on_configuration_changed.
--- Idempotent: rebuilds from scratch each call.
---
--- Iteration uses space_age.list_base_planets_runtime(), which reads
--- game.planets directly. This means:
---   • Vanilla planets (nauvis, vulcanus, gleba, fulgora, aquilo)
---     are picked up.
---   • Modded planets (Lignumis, Maraxsis, Muluna, etc.) registered by
---     any mod path — data:extend, PlanetsLib:extend, etc. — are also
---     picked up.
---   • If a player adds a planet mod to an existing save,
---     on_configuration_changed re-runs build() and the new modded
---     planet appears in the map automatically.
---   • Variants for the new planet have already been created at data
---     stage by prototypes/planets.lua (which uses the parallel
---     list_base_planets_data() iterator), so the runtime lookup
---     always finds them.
function planet_map.build()
    planet_map.init_storage()
    if not space_age.is_active() then return end

    local max = max_teams()
    storage.map_force_to_planets = {}
    storage.map_planet_to_force  = {}

    for slot = 1, max do
        local force_name = "team-" .. slot
        local per_team = {}
        for _, base in ipairs(space_age.list_base_planets_runtime()) do
            local variant = space_age.variant_name(base, slot)
            -- Only include variants that were actually created at data
            -- stage. game.planets is the canonical runtime accessor —
            -- LuaPrototypes has no `planet` key. (Team Starts uses
            -- this same pattern.)
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

    -- Lock and hide every base planet currently registered, including
    -- modded planets. The iterator returns whatever's in game.planets,
    -- so a modded planet added to the save (with a fresh /reload or
    -- on_configuration_changed) will be locked alongside the vanilla
    -- ones automatically.
    --
    -- Use game.planets[base].surface rather than game.surfaces[base]
    -- because in Space Age planet surfaces are created lazily; the
    -- canonical access for a planet's surface goes through LuaPlanet.
    -- (This matches Team Starts.)
    for _, base in ipairs(space_age.list_base_planets_runtime()) do
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

    -- Lock every OTHER team's variants. Without this, nauvis variants inherit
    -- the base nauvis "default starting planet, unlocked" state at create time,
    -- so every team's hub destination list shows all N nauvis variants from
    -- every team. Non-nauvis variants are usually locked-by-default, but lock
    -- them here too as defense-in-depth in case the engine ever unlocks one
    -- (e.g. a modded discovery effect, or a planet prototype change). Foreign
    -- slots count regardless of occupancy — team-12 still gets team-13's
    -- variants locked even if slot 13 is empty.
    local by_variant = storage.map_planet_to_force or {}
    for variant, owner in pairs(by_variant) do
        if owner ~= force.name then
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

--- Re-derive a team's planet-discovery unlocks from the techs it has ACTUALLY
--- researched, and re-apply them. apply_force_locks() clean-slates every
--- non-home variant — correct when research was wiped (fresh world, slot
--- recycle), but WRONG after a technology-effects reset or a configuration
--- change (e.g. a mod update). Those preserve research yet make the engine
--- re-point each discovery tech's unlock at the BASE planet, while the
--- redirect that unlocks the team's VARIANT only ever runs on
--- on_research_finished. So without this, a team that researched and reached
--- (say) Vulcanus loses its variant unlock on the next reset — the planet
--- relocks and goes dark — until manually unlocked.
---
--- Calling this after apply_force_locks restores the variant unlocks from the
--- researched discovery techs (re-running the on_research_finished redirect for
--- every already-completed one). Safe in every context: if research was wiped,
--- no discovery tech is researched and this is a no-op, so it never resurrects
--- a previous slot occupant's planets on recycle.
function planet_map.reapply_discovery_unlocks(force)
    if not space_age.is_active() then return end
    if not is_team_force(force.name) then return end
    for tech_name, base in pairs(storage.discovery_tech_map or {}) do
        local tech = force.technologies[tech_name]
        if tech and tech.researched then
            local variant = planet_map.get_variant(force.name, base)
            if variant then
                pcall(function() force.unlock_space_location(variant) end)
                pcall(function() force.lock_space_location(base) end)
            end
        end
    end
end

--- Re-derive discovery unlocks for every team force.
function planet_map.reapply_all_discovery_unlocks()
    for _, force in pairs(game.forces) do
        planet_map.reapply_discovery_unlocks(force)
    end
end

-- ─── Surface Creation ────────────────────────────────────────────────

--- Get or create the surface for a planet by name. Returns nil on failure.
---
--- Synchronously pre-generates a 3-chunk radius around origin before
--- returning. This is critical for clone_mirror compatibility: when a
--- chunk is generated on a team variant, clone_mirror runs clone_area
--- on that chunk, which overwrites destination contents — including
--- any character entity present in the destination. If chunk
--- generation is deferred (queued via request_to_generate_chunks but
--- not forced), the player teleports onto an ungenerated chunk,
--- Factorio auto-generates it under their feet, clone_mirror
--- destroys their character, and the player drops into god mode.
---
--- force_generate_chunk_requests blocks until all queued chunks
--- generate. By the time we return, clone_mirror has run on every
--- chunk in the spawn area; the player teleports onto already-cloned
--- terrain and their character survives.
---
--- Mirrors the same fix in compat/vanilla.lua's setup_player_surface.
function planet_map.get_or_create_planet_surface(planet_name)
    local planet = game.planets and game.planets[planet_name]
    if not (planet and planet.valid) then return nil end
    local surface = planet.surface
    if not (surface and surface.valid) then
        -- create_surface triggers lazy generation of the planet's surface
        surface = planet.create_surface()
    end
    if surface and surface.valid then
        surface.request_to_generate_chunks({0, 0}, 3)
        surface.force_generate_chunk_requests()
    end
    return surface
end

-- ─── Discovery Tech Hook ─────────────────────────────────────────────
--
-- A "discovery tech" is any technology whose effect list contains an
-- `unlock-space-location` modifier. Researching it normally unlocks
-- the linked space location (e.g. vulcanus). For team forces we
-- redirect that unlock to the team's *variant* of that location so
-- discovery research never reveals the shared base planet — only the
-- team's private copy.
--
-- We detect discovery techs by inspecting the technology prototype's
-- effects rather than matching on name, because:
--   • Vanilla uses "planet-discovery-{vulcanus,gleba,fulgora,aquilo}".
--   • Modded planets often follow the same naming convention but not
--     always (Lignumis uses "planet-discovery-lignumis", Maraxsis
--     might use a different scheme, etc.).
--   • Some modpacks rename existing techs.
--
-- Looking at effects directly is robust against any naming.

--- Build the discovery-tech map at runtime by scanning every technology
--- for an unlock-space-location effect. Cached in storage and rebuilt
--- on configuration changes.
---
--- Returns: { [tech_name] = base_planet_name, ... }
local function build_discovery_techs()
    local map = {}
    if not (prototypes and prototypes.technology) then return map end
    for tech_name, tech in pairs(prototypes.technology) do
        for _, effect in pairs(tech.effects or {}) do
            if effect.type == "unlock-space-location" then
                -- The effect's modifier field changed names across
                -- Factorio versions; check both the modern field
                -- (`space_location`) and any legacy variants. The
                -- pcall covers the case where the field exists but
                -- isn't a string we can read.
                local location = effect.space_location
                if location and game.planets and game.planets[location] then
                    map[tech_name] = location
                end
            end
        end
    end
    return map
end

--- Refresh the cached discovery-tech map. Call from on_init,
--- on_configuration_changed, and any time technology prototypes might
--- have changed (mod added/removed).
function planet_map.refresh_discovery_techs()
    if not space_age.is_active() then
        storage.discovery_tech_map = {}
        return
    end
    storage.discovery_tech_map = build_discovery_techs()
    log("[multi-team-support:planet_map] discovery techs detected: "
        .. (next(storage.discovery_tech_map) and "" or "none"))
    for tech_name, base in pairs(storage.discovery_tech_map) do
        log("  " .. tech_name .. " -> " .. base)
    end
end

--- If the finished tech is a planet discovery, unlock the team's
--- variant and lock the base. Called from tech_records on_research_finished.
--- Returns true if handled, false if unrelated.
function planet_map.on_research_finished(tech)
    if not space_age.is_active() then return false end
    local map = storage.discovery_tech_map or {}
    local base = map[tech.name]
    if not base then return false end
    local force = tech.force
    if not is_team_force(force.name) then return false end

    local variant = planet_map.get_variant(force.name, base)
    if variant then
        pcall(function() force.unlock_space_location(variant) end)
        -- Defensive: re-lock the base in case some other event
        -- unlocked it. Without this, discovering the variant would
        -- leak access to the shared base planet too.
        pcall(function() force.lock_space_location(base) end)
    end
    return true
end

-- ─── Logistic Request Rewrite ────────────────────────────────────────
--
-- The hub's "Import from" planet picker can't be filtered per-force in
-- Factorio 2.x: lock_space_location only gates schedule destinations,
-- and SpaceLocationPrototype.hidden is a global prototype flag. So
-- every team's hub still lists every planet variant (and every base
-- planet) in the dropdown. Reactive correction: when a player edits a
-- team-owned space-platform request, rewrite the slot's import_from
-- to the team's own variant of the same base planet.
--
-- import_from is only meaningful for space-platform requests. A ground
-- logistic chest can still carry the field — it rides along when a
-- request section is copied from a hub via blueprint, paste-settings,
-- or a shared logistic group — but on a planet surface it's inert
-- residue. Rewriting it there does nothing except spam the player
-- (and, through logistic-group propagation, once per group member),
-- so we gate on the entity being on a space platform before touching it.
--
-- Event payload (2.0.76):
--   entity (LuaEntity), section (LuaLogisticSection), slot_index (uint),
--   player_index (uint, optional — nil when scripted).
--
-- import_from may arrive as a string, a {name = "..."} table, or a
-- LuaSpaceLocationPrototype userdata — all three reduce to the name.

local function planet_name_to_base(name)
    return name:match("^mts%-(.+)%-%d+$") or name
end

function planet_map.on_logistic_slot_changed(event)
    if not space_age.is_active() then return end
    local entity = event.entity
    if not (entity and entity.valid) then return end
    local force = entity.force
    if not is_team_force(force.name) then return end

    -- Only space-platform requests can ship cargo across planets, so only
    -- they can leak to a foreign team. surface.platform is nil on planet
    -- surfaces, which skips ground chests carrying inert import_from copied
    -- from a hub (blueprint / paste-settings / shared logistic group).
    local surface = entity.surface
    if not (surface and surface.valid and surface.platform) then return end

    local section = event.section
    if not (section and section.valid) then return end
    if not section.is_manual then return end

    local slot = section.get_slot(event.slot_index)
    if not slot or not slot.value or not slot.import_from then return end

    local current = slot.import_from
    if type(current) == "table" or type(current) == "userdata" then
        current = current.name
    end
    if type(current) ~= "string" then return end

    local base = planet_name_to_base(current)
    local own  = planet_map.get_variant(force.name, base)
    if not own or own == current then return end

    local rewritten = {
        value                  = slot.value,
        min                    = slot.min,
        max                    = slot.max,
        minimum_delivery_count = slot.minimum_delivery_count,
        import_from            = own,
    }
    local ok, err = pcall(function() section.set_slot(event.slot_index, rewritten) end)
    if not ok then
        log("[multi-team-support:planet_map] logistic rewrite failed: " .. tostring(err)
            .. " force=" .. force.name .. " " .. current .. " -> " .. own)
        return
    end

    log("[multi-team-support:planet_map] logistic rewrite: force=" .. force.name
        .. " " .. current .. " -> " .. own .. " on " .. entity.name)

    if event.player_index then
        local player = game.get_player(event.player_index)
        if player and player.connected then
            pop_text.notify(player,
                "[color=1,0.55,0.35]" .. current .. "[/color]"
                .. " → "
                .. "[color=0.45,0.9,0.45]" .. own .. "[/color]"
            )
        end
    end
end

return planet_map
