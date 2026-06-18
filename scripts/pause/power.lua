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
-- ✓ RESOLVED — accumulator charge under active=false
-- ──────────────────────────────────────────────────────────
-- The spike is resolved: active=false does NOT stop an accumulator from
-- DISCHARGING its stored charge into the network, so a paused base with charged
-- accumulators keeps running off them (reported in-game: a docked base's
-- assembler still had power). active=false also doesn't drain the charge (an
-- earlier headless spike confirmed it persists). So we now SNAPSHOT each
-- accumulator's energy, zero it on freeze (no stored power to discharge), and
-- RESTORE it on thaw -- the snapshot+restore the comment used to call for.

local power = {}

-- Diagnostic logging. Currently ON so the freeze can be traced (per type) in
-- factorio-current.log ([mts:pause/power:DIAG]); set false once confirmed.
local DIAG = true
local function diag(msg)
    if DIAG then log("[mts:pause/power:DIAG] " .. msg) end
end

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

--- Flip active on every power source the force owns on one surface.
--- @param surface LuaSurface
--- @param force   LuaForce
--- @param active  boolean   desired active state (false to freeze)
--- @return integer touched  number of entities whose active state changed
local function set_sources_on_surface(surface, force, active, charge_store, type_counts)
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
        if ent.valid then
            type_counts[ent.type] = (type_counts[ent.type] or 0) + 1
            if ent.active ~= active then
                ent.active = active
                touched = touched + 1
            end
            -- Accumulators: active=false does NOT stop them discharging stored
            -- charge into the network. Zero the buffer on freeze (snapshotting it
            -- first) so a frozen base has no stored power to run on, and restore
            -- it on thaw -- no charge lost, no power leaked.
            if ent.type == "accumulator" and ent.unit_number then
                if not active then
                    charge_store[ent.unit_number] = ent.energy
                    ent.energy = 0
                else
                    local saved = charge_store[ent.unit_number]
                    if saved then
                        ent.energy = saved
                        charge_store[ent.unit_number] = nil
                    end
                end
            end
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
    -- Per-force snapshots: populated on freeze, drained on thaw.
    storage.pause_accumulator_charge = storage.pause_accumulator_charge or {}
    storage.pause_solar_mult        = storage.pause_solar_mult        or {}
    local charge_store = storage.pause_accumulator_charge[force.name] or {}
    local solar_store  = storage.pause_solar_mult[force.name]        or {}
    storage.pause_accumulator_charge[force.name] = charge_store
    storage.pause_solar_mult[force.name]         = solar_store

    local touched = 0
    local type_counts = {}
    for _, surface in pairs(surfaces or {}) do
        touched = touched + set_sources_on_surface(surface, force, active, charge_store, type_counts)
        -- Solar: active=false does NOT stop a solar panel generating, and surface
        -- darkness maxes ~0.85 (night isn't enough). Zero the SURFACE's solar
        -- multiplier on freeze (snapshot first) and restore on thaw -- the only
        -- airtight way to stop solar output on a frozen surface.
        if surface and surface.valid then
            if not active then
                solar_store[surface.index] = surface.solar_power_multiplier
                surface.solar_power_multiplier = 0
            else
                local saved = solar_store[surface.index]
                if saved then
                    surface.solar_power_multiplier = saved
                    solar_store[surface.index] = nil
                end
            end
        end
    end
    -- Thaw restored every snapshot; drop the (now empty) stores.
    if active then
        storage.pause_accumulator_charge[force.name] = nil
        storage.pause_solar_mult[force.name]         = nil
    end

    if DIAG then
        local parts = {}
        for t, n in pairs(type_counts) do parts[#parts + 1] = t .. "=" .. n end
        diag(string.format("%s force=%s touched=%d sources{%s}",
            active and "THAW" or "FREEZE", force.name, touched, table.concat(parts, " ")))
    end
    return touched
end

return power
