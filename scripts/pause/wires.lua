-- Multi-Team Support - scripts/pause/wires.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- The VISUAL half of a team pause: record and physically cut the team's
-- pole-to-pole copper wires so a paused base reads as "unplugged" at a glance,
-- then reconnect them in staggered batches on resume so the lights flicker
-- back on instead of snapping.
--
-- THIS LAYER IS COSMETIC. scripts/pause/power.lua is what actually stops the
-- power (by disabling the sources). Cutting trunk wires alone is NOT a freeze —
-- a local substation+generator island keeps its supply area powered no matter
-- which wires are cut. So this module is gated, defensive, and degrades to a
-- no-op on any error without ever affecting the airtight power freeze.
--
-- Space-Age gate: purely a scoping choice — the visual flourish ships with the
-- SA-era pause UX. Pre-SA pauses still get the airtight power freeze; they just
-- skip the wire theatre.
--
-- Storage:
--   storage.pause_wire_cuts[force_name] = {
--       { a_unit, b_unit },   -- recorded pole<->pole copper connections to restore
--       ...
--   }
--   storage.pause_wire_reconnect[force_name] = {
--       pairs    = { {a_unit,b_unit}, ... },  -- remaining to reconnect
--       idx      = integer,                   -- cursor for staggered reconnect
--   }
--
-- ── API grounding note ────────────────────────────────────────────────
-- get_wire_connector / connector.connect_to / connector.disconnect_from are
-- grounded in real usage (factorio-ultracube/scripts/entity_combine.lua,
-- dimension-warp/lib/utils.lua, ComfyFactorio/modules/infinity_power.lua).
-- ENUMERATING a connector's existing connections to RECORD them before cutting
-- (connector.connections) could NOT be grounded against an existing real usage
-- in either repo, so every read of it is pcall-wrapped: if the field/shape is
-- wrong the record simply yields nothing, the cut is skipped, and the airtight
-- power freeze is unaffected. Flagged as unverified in the build summary.

local space_age = require("scripts.space_age")

local wires = {}

-- How many pole pairs to reconnect per driver tick on resume, so a large base
-- powers back up as a visible ripple rather than an instant snap.
local RECONNECT_PER_TICK = 20

-- ─── Storage ──────────────────────────────────────────────────────────

function wires.init_storage()
    storage.pause_wire_cuts      = storage.pause_wire_cuts      or {}
    storage.pause_wire_reconnect = storage.pause_wire_reconnect or {}
end

-- ─── Helpers ──────────────────────────────────────────────────────────

--- Find an electric pole by unit_number across the given surfaces. Poles are
--- the only entities whose wires we record, so the lookup pool is small.
--- Build a unit_number -> pole index across the force's surfaces ONCE per
--- reconnect batch, so reconnecting N pairs is O(poles + N) instead of
--- O(pairs * poles). unit_numbers are globally unique, so a single flat map is
--- safe across surfaces.
local function build_pole_index(force)
    local index = {}
    for _, surface in pairs(game.surfaces) do
        if surface and surface.valid then
            local poles = surface.find_entities_filtered{
                type  = "electric-pole",
                force = force,
            }
            for _, p in ipairs(poles) do
                if p.valid and p.unit_number then index[p.unit_number] = p end
            end
        end
    end
    return index
end

--- Read the pole_copper connector for an entity, or nil. (true = create the
--- connector handle if absent; grounded usage passes true here.)
local function copper_connector(entity)
    if not (entity and entity.valid) then return nil end
    local ok, conn = pcall(function()
        return entity.get_wire_connector(defines.wire_connector_id.pole_copper, true)
    end)
    return ok and conn or nil
end

--- Resolve the far-end electric-pole and its connector handle for one entry in
--- a connector's connection list. ENTIRELY pcall-wrapped because the connection
--- record's shape (connection.target -> LuaWireConnector, .owner -> LuaEntity)
--- is UNVERIFIED against an existing real usage — a wrong field shape must
--- degrade to "skip this connection", never throw. Returns target_connector,
--- far_pole or nil, nil.
local function resolve_far_pole(connection)
    local ok, target_conn, far_pole = pcall(function()
        local tc = connection.target
        local owner = tc and tc.owner
        if owner and owner.valid and owner.type == "electric-pole" then
            return tc, owner
        end
        return nil, nil
    end)
    if not ok then return nil, nil end
    return target_conn, far_pole
end

-- ─── Record + Cut (pause) ─────────────────────────────────────────────

--- Record every pole<->pole copper connection the force owns, then cut it.
--- Returns the number of connections cut. Fully defensive: any failure to read
--- the connection list yields zero cuts and leaves the base wired.
--- @param force    LuaForce
--- @param surfaces LuaSurface[]
function wires.cut(force, surfaces)
    if not space_age.is_active() then return 0 end       -- visual layer is SA-gated
    if not (force and force.valid) then return 0 end
    wires.init_storage()

    local recorded = {}
    local seen     = {}   -- dedupe a<->b vs b<->a
    local cut_count = 0

    for _, surface in pairs(surfaces or {}) do
        if surface and surface.valid then
            local poles = surface.find_entities_filtered{
                type  = "electric-pole",
                force = force,
            }
            for _, pole in ipairs(poles) do
                local conn = copper_connector(pole)
                local a_unit = pole.valid and pole.unit_number or nil
                if conn and a_unit then
                    -- UNVERIFIED API: connector.connections enumeration is not
                    -- grounded in either repo. pcall-guarded so a wrong shape
                    -- degrades to "record nothing", never an error.
                    local ok, list = pcall(function() return conn.connections end)
                    if ok and type(list) == "table" then
                        for _, c in pairs(list) do
                            local target_conn, far_pole = resolve_far_pole(c)
                            local b_unit = far_pole and far_pole.unit_number
                            if target_conn and b_unit then
                                local key = (a_unit < b_unit)
                                    and (a_unit .. ":" .. b_unit)
                                    or  (b_unit .. ":" .. a_unit)
                                if not seen[key] then
                                    seen[key] = true
                                    recorded[#recorded + 1] = { a_unit, b_unit }
                                    -- Cut this specific connection (grounded API).
                                    pcall(function()
                                        conn.disconnect_from(target_conn, defines.wire_origin.script)
                                    end)
                                    cut_count = cut_count + 1
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    storage.pause_wire_cuts[force.name] = recorded
    if cut_count > 0 then
        log("[multi-team-support:pause/wires] cut " .. cut_count
            .. " pole connections for " .. force.name)
    end
    return cut_count
end

-- ─── Staggered Reconnect (resume) ─────────────────────────────────────

--- Begin a staggered reconnect of the wires recorded by cut(). The actual
--- reconnects happen in wires.tick(), a few per tick, so power ripples back.
--- @param force LuaForce
function wires.begin_reconnect(force)
    if not (force and force.valid) then return end
    wires.init_storage()
    local recorded = storage.pause_wire_cuts[force.name]
    storage.pause_wire_cuts[force.name] = nil
    if not recorded or #recorded == 0 then return end
    storage.pause_wire_reconnect[force.name] = {
        pairs = recorded,
        idx   = 1,
    }
end

--- Reconnect a fixed batch of recorded pole pairs for one force. Returns true
--- once that force's reconnect is finished so the caller can drop it.
local function step_reconnect(force_name, state)
    local force = game.forces[force_name]
    if not (force and force.valid) then return true end

    -- Build the pole index ONCE per tick batch (cheap: poles are few), then
    -- reconnect this tick's pairs against it. Rebuilt fresh each tick so it
    -- always reflects the live surface set (surfaces could have been retired
    -- between cut and resume) and never holds stale LuaEntity handles.
    local index = build_pole_index(force)

    local done = 0
    while done < RECONNECT_PER_TICK and state.idx <= #state.pairs do
        local pair   = state.pairs[state.idx]
        local pole_a = index[pair[1]]
        local pole_b = index[pair[2]]
        if pole_a and pole_b then
            local ca = copper_connector(pole_a)
            local cb = copper_connector(pole_b)
            if ca and cb then
                -- Grounded: connect_to(other, false, wire_origin.script).
                pcall(function()
                    ca.connect_to(cb, false, defines.wire_origin.script)
                end)
            end
        end
        state.idx = state.idx + 1
        done = done + 1
    end

    return state.idx > #state.pairs
end

--- Tick driver for staggered reconnect. Returns immediately when nothing is
--- pending, so it is a cheap no-op outside the brief resume window. Event-like:
--- it self-clears each force the instant its reconnect finishes (no lingering
--- flag polled forever).
function wires.tick()
    local pending = storage.pause_wire_reconnect
    if not pending or not next(pending) then return end
    local finished = {}
    for force_name, state in pairs(pending) do
        if step_reconnect(force_name, state) then
            finished[#finished + 1] = force_name
        end
    end
    for _, name in ipairs(finished) do
        pending[name] = nil
        log("[multi-team-support:pause/wires] reconnect complete: " .. name)
    end
end

return wires
