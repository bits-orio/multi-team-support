-- Multi-Team Support - space_age.lua
-- Author: bits-orio
-- License: MIT
--
-- Runtime detection for the Space Age DLC and shared helpers for naming
-- and enumerating planets. Used by both the data stage (prototypes/) and
-- runtime (scripts/, compat/) to agree on the same planet set.
--
-- Planet enumeration philosophy
-- ─────────────────────────────
-- Earlier versions hardcoded BASE_PLANETS = {"nauvis", "vulcanus", ...}.
-- That excluded modded planets (Maraxsis, Lignumis, Muluna, etc.) from
-- variant creation, force locks, and discovery-tech routing. We now
-- enumerate dynamically:
--
--   • At data stage: iterate `data.raw.planet`. Any mod-registered planet
--     present by data-final-fixes (MTS's enumeration point) is included.
--     Mods that depend on a planet library (e.g. PlanetsLib) typically
--     register through that library, which ultimately calls data:extend.
--     To guarantee load order, MTS lists popular planet libraries as
--     optional dependencies in info.json so their data stages run first.
--
--   • At runtime: iterate `game.planets`. This is the canonical accessor
--     for planet prototypes in 2.0; it includes every planet Factorio
--     currently considers registered, regardless of how it got there.
--
-- Both iterators skip MTS's own per-team variants (anything matching the
-- "mts-<base>-<slot>" pattern) so we don't recursively treat our variants
-- as base planets and create variants-of-variants.

local space_age = {}

--- Return true if Space Age is loaded. We detect it by checking
--- `game.planets` which is always a valid LuaCustomTable but only non-empty
--- when Space Age registers planet prototypes. Team Starts uses this same
--- pattern (they don't touch `prototypes.planet` at all at runtime).
local cached_active
function space_age.is_active()
    if cached_active ~= nil then return cached_active end

    -- Primary signal: active_mods entry
    local mod_loaded = script.active_mods["space-age"] ~= nil
    -- Secondary signal: game.planets contains entries (only Space Age
    -- registers planet prototypes like "nauvis", "vulcanus", etc.)
    local planets_exist = false
    if game and game.planets then
        for _ in pairs(game.planets) do
            planets_exist = true
            break
        end
    end

    cached_active = mod_loaded and planets_exist
    log("[multi-team-support] Space Age detection: active="
        .. tostring(cached_active)
        .. " (mod_loaded=" .. tostring(mod_loaded)
        .. ", planets_exist=" .. tostring(planets_exist) .. ")")
    -- Also log active_mods dump once to help diagnose detection failures
    if mod_loaded ~= cached_active then
        log("[multi-team-support] active_mods dump:")
        for name, version in pairs(script.active_mods) do
            log("  " .. name .. " = " .. tostring(version))
        end
    end
    return cached_active
end

--- Clear the cached detection result (used on_configuration_changed).
function space_age.invalidate_cache()
    cached_active = nil
end

--- Canonical name for a per-team planet variant.
---   variant_name("nauvis", 1) -> "mts-nauvis-1"
function space_age.variant_name(base, team_slot)
    return string.format("mts-%s-%d", base, team_slot)
end

--- Parse a variant name back into (base, team_slot), or nil if not a variant.
--- The base capture accepts hyphens and underscores so modded planets with
--- names like "muluna-2" or "alien_world" still parse correctly.
function space_age.parse_variant(name)
    local base, slot = name:match("^mts%-(.+)%-(%d+)$")
    if not base then return nil end
    return base, tonumber(slot)
end

--- Return true when `name` is one of MTS's per-team variants. Used by
--- the iteration helpers below to avoid recursively treating our own
--- variants as base planets.
local function is_variant_name(name)
    return name and name:find("^mts%-") ~= nil
end

-- ═══ Planet enumeration ════════════════════════════════════════════════
--
-- These two helpers are the canonical source for "what base planets do we
-- know about?". Use list_base_planets_data() at the data stage (typically
-- data-final-fixes) and list_base_planets_runtime() in control-stage code
-- (on_init, on_configuration_changed, event handlers).
--
-- Both return a sorted-by-name list so iteration order is deterministic
-- across saves — important for desync-sensitive multiplayer code that
-- builds storage tables in this order.

--- Sorted list of base-planet names available at data stage. Excludes
--- MTS's own variants. Safe to call before data-final-fixes runs (any
--- planets registered before MTS's iteration point are picked up).
function space_age.list_base_planets_data()
    local names = {}
    if data and data.raw and data.raw.planet then
        for name in pairs(data.raw.planet) do
            if not is_variant_name(name) then
                names[#names + 1] = name
            end
        end
    end
    table.sort(names)
    return names
end

--- Sorted list of base-planet names available at runtime. Excludes
--- MTS's own variants. Reflects the actual planet prototypes Factorio
--- has loaded — modded planets registered via any path (data:extend,
--- PlanetsLib:extend, etc.) end up here.
function space_age.list_base_planets_runtime()
    local names = {}
    if game and game.planets then
        for name in pairs(game.planets) do
            if not is_variant_name(name) then
                names[#names + 1] = name
            end
        end
    end
    table.sort(names)
    return names
end

return space_age
