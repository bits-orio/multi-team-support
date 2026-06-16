-- Multi-Team Support - scripts/pause/control.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- Orchestrates a full team pause / unpause for the mts-v1 API.
--
-- A team pause is two layers — no active=false entity sweep (see ADR-0001):
--   1. pause/power  — the AIRTIGHT freeze: disable every power SOURCE
--      (generators + accumulators) the team owns, in a single tick. With the
--      grid dead, powered machines simply idle and resume cleanly, and no
--      substation+generator island can keep its area running.
--   2. pause/wires  — the VISUAL layer (Space-Age-gated): record + cut
--      pole-to-pole wires, staggered reconnect on resume. Cosmetic only.
--
-- We deliberately do NOT use the legacy active=false entity sweep
-- (the retired active=false auto-pause feature): killing power is
-- airtight by construction and avoids the mid-operation state bugs active=false
-- causes. Known gap: burner-fuelled machines run on loaded fuel, not the grid,
-- so they keep ticking until that fuel is spent — accepted for now, flagged in
-- pause/power.lua.
--
-- This module is the single entry point both the mts-v1 remote functions and
-- the /mts-pause command path call, so both layers fire in the right order.

local power       = require("scripts.pause.power")
local wires       = require("scripts.pause.wires")
local pause_state = require("scripts.pause.state")

local control = {}

-- ─── Helpers ──────────────────────────────────────────────────────────

local function is_team_force(force)
    return force and force.valid and force.name:find("^team%-") ~= nil
end

--- Collect the LuaSurface objects owned by a force. We reuse the same owner
--- check the rest of MTS uses (surface_utils.get_owner) by delegating to the
--- mts-v1 list_team_surfaces query, which is the design's named enumerator —
--- but to avoid a circular require on remote_api we resolve surfaces directly
--- from the names the caller passes in.
--- @param surface_names string[]
--- @return LuaSurface[]
local function resolve_surfaces(surface_names)
    local out = {}
    for _, name in pairs(surface_names or {}) do
        local s = game.surfaces[name]
        if s and s.valid then out[#out + 1] = s end
    end
    return out
end

-- ─── Pause ────────────────────────────────────────────────────────────

--- Pause a whole team. Returns true if a pause was started.
--- @param force_name    string
--- @param surface_names string[]   surfaces owned by the team (from list_team_surfaces)
function control.pause_team(force_name, surface_names)
    local force = game.forces[force_name]
    if not is_team_force(force) then return false end

    local surfaces = resolve_surfaces(surface_names)

    -- 1. Airtight power cut FIRST, in this tick, so the supply dies immediately
    --    rather than over the amortized sweep's many-tick window.
    power.freeze(force, surfaces)

    -- 2. Visual wire cut (SA-gated, cosmetic, fully defensive).
    wires.cut(force, surfaces)

    -- 3. Stamp the marker. The power freeze above is synchronous, so the team
    --    is paused as of this tick and is_team_paused reflects it immediately.
    pause_state.set_paused(force_name, true)
    return true
end

-- ─── Unpause ──────────────────────────────────────────────────────────

--- Resume a whole team. Returns true if a resume was started.
--- @param force_name string
--- @param surface_names string[]
--- @param opts table  {mode, duration} reserved for v2 (timed pause / sleep-wake)
function control.unpause_team(force_name, surface_names, opts)
    local force = game.forces[force_name]
    if not is_team_force(force) then return false end

    local surfaces = resolve_surfaces(surface_names)

    -- 1. Re-enable power sources immediately.
    power.thaw(force, surfaces)

    -- 2. Kick off the staggered visual wire reconnect (no-op if none recorded).
    wires.begin_reconnect(force)

    -- 3. Clear the marker; the staggered visual reconnect finishes over the
    --    next ticks via control.tick().
    pause_state.set_paused(force_name, false)
    return true
end

-- ─── Tick ─────────────────────────────────────────────────────────────

--- Drive the staggered wire reconnect. Cheap no-op when nothing is pending.
--- Wired from events/ticks.lua on the 10-tick cadence.
function control.tick()
    wires.tick()
end

return control
