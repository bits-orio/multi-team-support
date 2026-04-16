-- Multi-Team Support - space_age.lua
-- Author: bits-orio
-- License: MIT
--
-- Runtime detection for the Space Age DLC. Used to branch behavior between
-- per-team planet variants (Space Age) and the fallback surface-cloning
-- approach (no Space Age).
--
-- Also defines shared naming helpers for per-team planet variants so both
-- the data stage (prototypes/) and runtime (control.lua / compat) agree.

local space_age = {}

-- Base planets that we generate per-team variants for.
-- Anything else in data.raw.planet (e.g. modded planets) is not remapped.
space_age.BASE_PLANETS = {
    "nauvis", "vulcanus", "gleba", "fulgora", "aquilo",
}

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
function space_age.parse_variant(name)
    local base, slot = name:match("^mts%-(%a+)%-(%d+)$")
    if not base then return nil end
    return base, tonumber(slot)
end

return space_age
