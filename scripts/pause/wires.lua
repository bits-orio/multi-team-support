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
-- get_wire_connector / connector.connect_to / connector.disconnect_from and the
-- connector.connections enumeration (-> array of WireConnection{target, origin})
-- are now VERIFIED against runtime-api.json (2.0.76) AND empirically (a headless
-- repro: wire 3 poles, pause -> connections drop to 0, unpause -> restored).
-- Reads stay pcall-wrapped as defence in depth. KEY FIX (was the live bug): a
-- connection must be cut/restored with its OWN origin -- disconnect_from(target,
-- origin) only removes a connection of the MATCHING origin, so the old hardcoded
-- origin=script silently no-op'd on real player/robot wires (they "didn't drop").
-- We now read each WireConnection.origin, cut with it, record it, and reconnect
-- with it. The airtight power freeze (pause/power) is independent of all this.

local space_age     = require("scripts.space_age")
local surface_utils = require("scripts.surface_utils")

local wires = {}

-- How many pole pairs to reconnect per driver tick on resume, so a large base
-- powers back up as a visible ripple rather than an instant snap.
local RECONNECT_PER_TICK = 20

-- Diagnostic logging for the connection-enumeration path. Off by default; flip
-- to true to trace the cut/reconnect in factorio-current.log (lines prefixed
-- [mts:pause/wires:DIAG]). Kept after the origin-bug fix as a debugging aid.
local DIAG = false
local function diag(msg)
    if DIAG then log("[mts:pause/wires:DIAG] " .. msg) end
end

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
    -- Only the force's OWN surfaces can hold its poles (wires.cut records only
    -- from those), so scan them instead of every surface in the game (PF-10).
    -- Still rebuilt per reconnect batch on purpose: re-deriving owned surfaces
    -- each call drops any retired mid-reconnect, avoiding stale LuaEntity handles.
    for _, surface in ipairs(surface_utils.owned_surfaces_by_force(force.name)) do
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
    local ok, target_conn, far_pole, origin = pcall(function()
        local tc = connection.target
        local owner = tc and tc.owner
        if owner and owner.valid and owner.type == "electric-pole" then
            -- The wire's ORIGIN must be used to disconnect/reconnect it:
            -- disconnect_from(target, origin) only removes a connection of the
            -- MATCHING origin, so a real player/robot wire is untouched by
            -- origin=script (the bug). Defaults to player per the WireConnection
            -- concept.
            return tc, owner, connection.origin or defines.wire_origin.player
        end
        return nil, nil, nil
    end)
    if not ok then return nil, nil, nil end
    return target_conn, far_pole, origin
end

-- ─── Record + Cut (pause) ─────────────────────────────────────────────

--- Record every pole<->pole copper connection the force owns, then cut it.
--- Returns the number of connections cut. Fully defensive: any failure to read
--- the connection list yields zero cuts and leaves the base wired.
--- @param force    LuaForce
--- @param surfaces LuaSurface[]
function wires.cut(force, surfaces)
    local sa = space_age.is_active()
    diag("CUT begin force=" .. tostring(force and force.name) .. " SA=" .. tostring(sa)
        .. " #surfaces=" .. tostring(surfaces and #surfaces or 0))
    if not sa then diag("CUT skip: not Space Age"); return 0 end  -- visual layer is SA-gated
    if not (force and force.valid) then return 0 end
    wires.init_storage()

    local recorded = {}
    local seen     = {}   -- dedupe a<->b vs b<->a
    local cut_count = 0
    local total_poles, total_conns, samples = 0, 0, 0

    for _, surface in pairs(surfaces or {}) do
        if surface and surface.valid then
            local poles = surface.find_entities_filtered{
                type  = "electric-pole",
                force = force,
            }
            total_poles = total_poles + #poles
            diag("surface=" .. surface.name .. " poles=" .. #poles)
            for _, pole in ipairs(poles) do
                local conn = copper_connector(pole)
                local a_unit = pole.valid and pole.unit_number or nil
                if conn and a_unit then
                    -- UNVERIFIED API: connector.connections enumeration is not
                    -- grounded in either repo. pcall-guarded so a wrong shape
                    -- degrades to "record nothing", never an error.
                    local ok, list = pcall(function() return conn.connections end)
                    local rok, rlist = pcall(function() return conn.real_connections end)
                    if samples < 10 then
                        samples = samples + 1
                        diag(string.format("pole#%s conn_ok=%s connections_n=%s real_n=%s",
                            tostring(a_unit), tostring(ok),
                            (ok and type(list) == "table") and tostring(#list) or ("?(" .. type(list) .. ")"),
                            (rok and type(rlist) == "table") and tostring(#rlist) or "?"))
                    end
                    if ok and type(list) == "table" then
                        for _, c in pairs(list) do
                            total_conns = total_conns + 1
                            local target_conn, far_pole, origin = resolve_far_pole(c)
                            local b_unit = far_pole and far_pole.unit_number
                            if total_conns <= 10 then
                                diag(string.format("  conn#%d target=%s owner_type=%s far_unit=%s origin=%s",
                                    total_conns, tostring(target_conn ~= nil),
                                    tostring(far_pole and far_pole.type), tostring(b_unit), tostring(origin)))
                            end
                            if target_conn and b_unit then
                                local key = (a_unit < b_unit)
                                    and (a_unit .. ":" .. b_unit)
                                    or  (b_unit .. ":" .. a_unit)
                                if not seen[key] then
                                    seen[key] = true
                                    -- Record the origin too so reconnect restores
                                    -- the SAME wire kind (player/robot/script).
                                    recorded[#recorded + 1] = { a_unit, b_unit, origin }
                                    -- Cut with the wire's ACTUAL origin (using
                                    -- a fixed origin=script silently no-ops on a
                                    -- player/robot wire -- the reported bug).
                                    local cok, cerr = pcall(function()
                                        conn.disconnect_from(target_conn, origin)
                                    end)
                                    if not cok and cut_count == 0 then diag("disconnect_from ERR: " .. tostring(cerr)) end
                                    cut_count = cut_count + 1
                                end
                            end
                        end
                    end
                elseif samples < 10 then
                    samples = samples + 1
                    diag("pole#" .. tostring(a_unit) .. " conn=NIL (copper_connector returned nil)")
                end
            end
        end
    end

    storage.pause_wire_cuts[force.name] = recorded
    diag(string.format("CUT done force=%s total_poles=%d total_conns=%d cut=%d recorded=%d",
        force.name, total_poles, total_conns, cut_count, #recorded))
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
    diag("RECONNECT begin force=" .. force.name .. " recorded_pairs=" .. tostring(recorded and #recorded or 0))
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
                -- Reconnect with the SAME origin we recorded at cut time, so the
                -- restored wire matches the original (player/robot) and a later
                -- pause can cut it again.
                pcall(function()
                    ca.connect_to(cb, false, pair[3] or defines.wire_origin.player)
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
