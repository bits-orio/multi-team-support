-- Multi-Team Support - scripts/pause/power.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- The team pause freeze: disable every power SOURCE the team owns.
--
-- Why kill sources instead of machines or wires
-- ─────────────────────────────────────────────
-- Setting active=false on every machine (the retired force_pause approach) is
-- buggy mid-operation and the bugs are endless; an unpowered machine instead
-- keeps its state and simply idles, so resume is clean by construction. Cutting
-- pole-to-pole wires (scripts/pause/wires.lua) is NOT a freeze either: a local
-- substation fed by a local generator stays an island and powers its whole
-- supply area regardless of which trunk wires were cut. The only airtight
-- freeze is to kill the SOURCES themselves, immediately, across every owned
-- surface. That is this module's single job.
--
-- This is event-driven: pause/control.lua calls freeze()/thaw() directly at the
-- moment of the pause/resume decision. No tick polling, no dirty flag.
--
-- ⚠ UNRESOLVED SPIKE — accumulator charge under active=false
-- ──────────────────────────────────────────────────────────
-- It is NOT verified in-game whether setting active=false on an accumulator
-- FREEZES its stored charge (desired) or lets it DRAIN/leak while disabled.
-- See SPIKE_ACCUMULATOR below. Implemented conservatively (we only flip active,
-- we never touch .energy) so we cannot accidentally destroy a team's charge;
-- if the spike resolves to "drains", a follow-up must snapshot+restore .energy.

local power = {}

-- Entity TYPES that GENERATE or STORE electricity. Disabling active on these
-- stops the supply at the root. Verified as real Factorio 2.0 entity-type
-- strings (used as find_entities_filtered{type=...} filters; the array form is
-- grounded in dimension-warp/scripts/misc.lua and IR3 control-terrain.lua).
--
-- ⚠ KNOWN FREEZE LEAK — burner-fuelled machines.
-- A burner-generator with fuel already loaded, and more broadly any burner
-- machine (burner mining drill, stone furnace, boiler+steam-engine chain that
-- is mid-burn) keeps consuming its currently-loaded fuel item for one more
-- "burn" even with active=false in some engine versions, because the fuel
-- inventory is independent of the active flag. We disable burner-generator
-- here, but a fully airtight burner freeze would also need to clear/snapshot
-- the fuel/burner inventories — deliberately out of scope for v1; comment kept
-- so the leak is discoverable.
local POWER_SOURCE_TYPES = {
    "generator",                 -- steam engines / turbines
    "burner-generator",          -- direct burner -> power (see leak note above)
    "solar-panel",               -- daytime supply
    "accumulator",               -- stored charge (see SPIKE below)
    "reactor",                   -- nuclear heat source feeding generators
    "electric-energy-interface", -- modded/scenario infinite or tuned supplies
    "fusion-generator",          -- Space Age fusion (no-op pre-SA; type just won't match)
}

-- SPIKE_ACCUMULATOR: placeholder so the unresolved question is greppable.
-- TODO(spike): confirm in-game whether `accumulator.active = false` freezes or
-- drains `accumulator.energy`. Until then we ONLY toggle active and never read
-- or write .energy, which is the safe (non-destructive) conservative choice.
local SPIKE_ACCUMULATOR = "active=false charge behavior unverified"

--- Flip active on every power source the force owns on one surface.
--- @param surface LuaSurface
--- @param force   LuaForce
--- @param active  boolean   desired active state (false to freeze)
--- @return integer touched  number of entities whose active state changed
local function set_sources_on_surface(surface, force, active)
    if not (surface and surface.valid and force and force.valid) then return 0 end
    local touched = 0
    -- One filtered query per surface (entity-type array filter) instead of a
    -- per-chunk walk: power sources are few relative to belts/inserters, so the
    -- whole-surface query is cheap and lets the freeze land in a single tick
    -- (the airtight requirement — no amortized window where sources stay live).
    local sources = surface.find_entities_filtered{
        type  = POWER_SOURCE_TYPES,
        force = force,
    }
    for _, ent in ipairs(sources) do
        if ent.valid and ent.active ~= active then
            ent.active = active
            touched = touched + 1
        end
    end
    return touched
end

--- Disable (active=false) every power source the force owns across all the
--- given surfaces. Call at pause time.
--- @param force    LuaForce
--- @param surfaces LuaSurface[]   surfaces owned by the force
--- @return integer touched
function power.freeze(force, surfaces)
    return power.set_active(force, surfaces, false)
end

--- Re-enable (active=true) every power source. Call at resume time.
--- @param force    LuaForce
--- @param surfaces LuaSurface[]
--- @return integer touched
function power.thaw(force, surfaces)
    return power.set_active(force, surfaces, true)
end

--- Shared core for freeze/thaw. Runs in every mode (pre-SA teams have power
--- sources too) — this airtight freeze is NOT Space-Age-gated; only the
--- cosmetic wire layer is.
function power.set_active(force, surfaces, active)
    if not (force and force.valid) then return 0 end
    -- SPIKE_ACCUMULATOR (see top): we deliberately only flip `active` below and
    -- never read/write `accumulator.energy`, because whether active=false
    -- freezes or drains stored charge is unverified in-game. Touching .energy
    -- here is the would-be fix IF the spike ever resolves to "drains".
    local _ = SPIKE_ACCUMULATOR  -- keep the marker reachable/greppable
    local touched = 0
    for _, surface in pairs(surfaces or {}) do
        touched = touched + set_sources_on_surface(surface, force, active)
    end
    return touched
end

return power
