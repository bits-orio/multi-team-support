-- Multi-Team Support - scripts/force_pause.lua
-- Author: bits-orio
-- License: MIT
--
-- Auto-pause a team force when all its players go offline: sets
-- LuaEntity.active = false on every entity owned by the force across all
-- of its surfaces. Resumes on reconnect.
--
-- Work is amortized across ticks: instead of iterating thousands of
-- entities in one tick (which would stutter the server), we walk the
-- force's surfaces chunk-by-chunk, processing a capped entity budget per
-- tick. Chunk-based iteration is cheap because Factorio indexes entities
-- by chunk.
--
-- Storage shape:
--   storage.pause_sweep[force_name] = {
--       direction     = "pause" | "resume",  -- desired active state
--       surfaces      = {surface_index, ...}, -- snapshot at sweep start
--       surface_idx   = integer,              -- cursor into `surfaces`
--       chunks        = {{x,y}, ...},         -- materialized on each surface
--       chunk_idx     = integer,              -- cursor into `chunks`
--   }
--   storage.paused_forces[force_name] = true  -- set once pause sweep completes

local surface_utils = require("scripts.surface_utils")
local team_settings = require("gui.team_settings")

local force_pause = {}

-- ─── Constants ────────────────────────────────────────────────────────

-- Per-tick entity budget. Each "touch" is a single active = bool assignment,
-- which is very cheap, so a few hundred per tick is comfortable. Tune here
-- if stutter is ever observed during sweeps.
local BUDGET_PER_TICK = 500

-- Chunk edge length in tiles (Factorio: always 32).
local CHUNK_SIZE = 32

-- ─── Helpers ──────────────────────────────────────────────────────────

--- Return true iff no player on the force is currently connected.
local function force_is_empty(force)
    if not (force and force.valid) then return true end
    return #force.connected_players == 0
end

--- Return true iff this force should participate in auto-pause.
--- Only team forces are affected — never the spectator/enemy/player force.
local function is_team_force(force)
    return force and force.valid and force.name:find("^team%-") ~= nil
end

--- Collect all surface indexes owned by this force.
local function collect_force_surfaces(force)
    local list = {}
    for _, surface in pairs(game.surfaces) do
        if surface.valid and surface_utils.get_owner(surface) == force.name then
            list[#list + 1] = surface.index
        end
    end
    return list
end

--- Materialize all chunks on the given surface as an array of {x,y}.
--- Done once when the sweep advances to a new surface so chunk iteration
--- is resumable across ticks (Factorio's chunk iterator is not persistable).
local function materialize_chunks(surface)
    local chunks = {}
    if not (surface and surface.valid) then return chunks end
    for chunk in surface.get_chunks() do
        chunks[#chunks + 1] = {x = chunk.x, y = chunk.y}
    end
    return chunks
end

--- Convert a chunk {x,y} to a bounding-box area usable by find_entities_filtered.
local function chunk_area(chunk)
    local x = chunk.x * CHUNK_SIZE
    local y = chunk.y * CHUNK_SIZE
    return {{x, y}, {x + CHUNK_SIZE, y + CHUNK_SIZE}}
end

-- ─── Sweep Lifecycle ──────────────────────────────────────────────────

--- Begin (or replace) a sweep for `force` in the given direction.
--- Direction flips are handled by overwriting the existing entry: entities
--- already touched in the previous direction will be revisited and flipped
--- back by the new sweep (setting active to its current value is a no-op).
local function start_sweep(force, direction)
    if not is_team_force(force) then return end
    storage.pause_sweep = storage.pause_sweep or {}
    local surfaces = collect_force_surfaces(force)
    if #surfaces == 0 then
        -- Nothing to do; just update the paused_forces marker so state is
        -- still consistent (pause with no surfaces = paused).
        storage.paused_forces = storage.paused_forces or {}
        storage.paused_forces[force.name] = (direction == "pause") or nil
        storage.pause_sweep[force.name]   = nil
        return
    end
    storage.pause_sweep[force.name] = {
        direction   = direction,
        surfaces    = surfaces,
        surface_idx = 1,
        chunks      = nil,    -- lazy-materialize when reaching surface
        chunk_idx   = 1,
    }
    log("[multi-team-support:force_pause] start_sweep: "
        .. force.name .. " direction=" .. direction
        .. " surfaces=" .. #surfaces)
end

--- Advance one step of the sweep for a single force. Returns the number
--- of entities touched so the caller can budget across forces.
local function step_sweep(force_name, state, remaining_budget)
    local force = game.forces[force_name]
    if not (force and force.valid) then
        storage.pause_sweep[force_name] = nil
        return 0
    end

    local desired_active = (state.direction == "resume")
    local touched = 0

    while remaining_budget > 0 do
        -- Advance off a finished surface.
        if state.surface_idx > #state.surfaces then break end

        -- Lazy-materialize chunks when entering a new surface.
        if state.chunks == nil then
            local surface = game.surfaces[state.surfaces[state.surface_idx]]
            state.chunks    = materialize_chunks(surface)
            state.chunk_idx = 1
            -- Empty surface: skip.
            if #state.chunks == 0 then
                state.surface_idx = state.surface_idx + 1
                state.chunks      = nil
            end
            -- Loop back so we either start on the new surface or move past it.
            -- fallthrough
        end

        if state.chunks and state.chunk_idx <= #state.chunks then
            local surface = game.surfaces[state.surfaces[state.surface_idx]]
            if surface and surface.valid then
                local area     = chunk_area(state.chunks[state.chunk_idx])
                local entities = surface.find_entities_filtered{
                    area  = area,
                    force = force,
                }
                for _, ent in ipairs(entities) do
                    if ent.valid and ent.active ~= desired_active then
                        ent.active = desired_active
                        touched = touched + 1
                        remaining_budget = remaining_budget - 1
                        if remaining_budget <= 0 then break end
                    end
                end
            end
            state.chunk_idx = state.chunk_idx + 1
            -- Finished the last chunk on this surface: advance.
            if state.chunks and state.chunk_idx > #state.chunks then
                state.surface_idx = state.surface_idx + 1
                state.chunks      = nil
                state.chunk_idx   = 1
            end
        end
    end

    -- Sweep complete?
    if state.surface_idx > #state.surfaces then
        storage.paused_forces = storage.paused_forces or {}
        storage.paused_forces[force_name] =
            (state.direction == "pause") or nil
        storage.pause_sweep[force_name] = nil
        log("[multi-team-support:force_pause] sweep complete: "
            .. force_name .. " direction=" .. state.direction)
    end

    return touched
end

-- ─── Public API ───────────────────────────────────────────────────────

function force_pause.init_storage()
    storage.pause_sweep    = storage.pause_sweep    or {}
    storage.paused_forces  = storage.paused_forces  or {}
end

--- Called from on_player_left_game. If the player's force has no remaining
--- connected players AND the team has opted in to auto-pause, start a
--- pause sweep. The opt-in is controlled by the Team Settings GUI.
function force_pause.on_player_left(player)
    if not (player and player.valid) then return end
    local force = player.force
    log("[multi-team-support:force_pause] on_player_left: "
        .. player.name .. " force=" .. (force and force.name or "?")
        .. " remaining=" .. (force and #force.connected_players or -1)
        .. " auto_pause=" .. tostring(force and team_settings.get_auto_pause(force.name)))
    if not is_team_force(force) then return end
    if not force_is_empty(force) then return end
    if not team_settings.get_auto_pause(force.name) then return end

    start_sweep(force, "pause")
end

--- Called from on_player_joined_game. If the player's force is paused or
--- mid-pause-sweep, kick off a resume sweep (overwrites any pending pause).
function force_pause.on_player_joined(player)
    if not (player and player.valid) then return end
    local force = player.force
    if not is_team_force(force) then return end

    local is_paused = storage.paused_forces and storage.paused_forces[force.name]
    local mid_sweep = storage.pause_sweep   and storage.pause_sweep[force.name]
    if is_paused or mid_sweep then
        start_sweep(force, "resume")
    end
end

--- Called when a player's effective force changes (e.g. team slot
--- claimed from the landing pen). Makes sure their new force is not
--- stuck in a paused state just because no one else was online.
function force_pause.on_force_changed(player)
    force_pause.on_player_joined(player)
end

--- Tick driver. Called from on_nth_tick; walks each active sweep by a
--- fraction of the per-tick budget so concurrent sweeps can share load.
function force_pause.tick()
    if not storage.pause_sweep or not next(storage.pause_sweep) then return end

    -- Collect active sweeps into a list so we can divide the budget fairly.
    local active = {}
    for name, state in pairs(storage.pause_sweep) do
        active[#active + 1] = {name = name, state = state}
    end

    local per_sweep = math.max(1, math.floor(BUDGET_PER_TICK / #active))
    for _, entry in ipairs(active) do
        step_sweep(entry.name, entry.state, per_sweep)
    end
end

return force_pause
