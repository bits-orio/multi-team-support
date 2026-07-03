-- Multi-Team Support - scripts/chunk_trim.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- Admin tool: trim unused chunks on team surfaces (every planet a team owns,
-- not just nauvis). For each surface, preserves a buffer of chunks around team
-- entities, connected players, and spawner corpses; deletes everything else and
-- uncharts the deleted chunks. Space platforms are skipped -- their foundation
-- is tiles, not entities, so chunk deletion could destroy parts of the platform.
--
-- For multi-surface runs, surfaces are processed one per tick interval so
-- the server can catch up between large trims.
--
-- Storage shape:
--   storage.chunk_trim_queue = {
--       surfaces      = {surface_index, ...},
--       idx           = integer,
--       entity_buffer = integer,
--       player_buffer = integer,
--       caller_idx    = integer | nil,
--   }

local helpers       = require("scripts.helpers")
local surface_utils = require("scripts.surface_utils")

local chunk_trim = {}

-- ─── Constants ────────────────────────────────────────────────────────

local DEFAULT_ENTITY_BUFFER = 12
local DEFAULT_PLAYER_BUFFER = 8
local CHUNK_SIZE            = 32

-- ─── Helpers ──────────────────────────────────────────────────────────

--- The team force that owns a surface, on any planet, or nil. Space platforms
--- are treated as un-trimmable (their foundation is tiles, not entities).
local function trimmable_owner(surface)
    if not (surface and surface.valid) or surface.platform then return nil end
    return surface_utils.get_owner(surface)
end

--- Send a message to the caller if connected, else broadcast.
local function notify(caller_idx, msg)
    local p = caller_idx and game.get_player(caller_idx)
    if p and p.connected then p.print(msg) else game.print(msg) end
end

--- Trim one surface synchronously. Returns deleted, total.
local function trim_surface(surface, entity_buffer, player_buffer, caller_idx)
    if not (surface and surface.valid) then return 0, 0 end

    local team_force = trimmable_owner(surface)
    local label      = team_force and helpers.team_tag(team_force) or surface.name
    local force      = team_force and game.forces[team_force]
    if not (force and force.valid) then
        notify(caller_idx, label .. " (" .. surface.name .. "): no team force; skipped")
        return 0, 0
    end

    local keep = {}
    local function mark(cx, cy)
        keep[cx] = keep[cx] or {}
        keep[cx][cy] = true
    end
    local function mark_buffer(cx, cy, r)
        for dx = -r, r do
            for dy = -r, r do mark(cx + dx, cy + dy) end
        end
    end

    -- Dilate by entity_buffer PER DISTINCT OCCUPIED CHUNK, not per entity. Many
    -- entities share a chunk, so collecting the distinct occupied chunks first
    -- (O(entities)) then dilating each once (O(occupied_chunks * (2r+1)^2)) gives
    -- the identical keep-set as dilating every entity would, without the
    -- O(entities * (2r+1)^2) blowup on a dense base (PF-6).
    local occupied = {}
    for _, e in pairs(surface.find_entities_filtered{force = force}) do
        local cx = math.floor(e.position.x / CHUNK_SIZE)
        local cy = math.floor(e.position.y / CHUNK_SIZE)
        occupied[cx] = occupied[cx] or {}
        occupied[cx][cy] = true
    end
    for cx, col in pairs(occupied) do
        for cy in pairs(col) do mark_buffer(cx, cy, entity_buffer) end
    end
    for _, p in pairs(game.connected_players) do
        if p.physical_surface == surface then
            local pp = p.physical_position
            mark_buffer(
                math.floor(pp.x / CHUNK_SIZE),
                math.floor(pp.y / CHUNK_SIZE),
                player_buffer)
        end
    end
    -- Preserve spawner death markers so biter expansion history isn't lost.
    for _, c in pairs(surface.find_entities_filtered{type = "corpse"}) do
        if c.name:find("spawner") then
            mark(math.floor(c.position.x / CHUNK_SIZE),
                 math.floor(c.position.y / CHUNK_SIZE))
        end
    end

    -- Collect the doomed chunk coords in a first pass, THEN delete in a second
    -- pass, rather than deleting mid-get_chunks(). delete_chunk's own events are
    -- deferred so mutating during iteration is probably safe, but get_chunks()
    -- makes no concurrent-mutation guarantee -- separating the passes removes the
    -- doubt for free (deletion still lands end-of-tick either way) (ST-4).
    local total = 0
    local doomed = {}
    for c in surface.get_chunks() do
        total = total + 1
        if not (keep[c.x] and keep[c.x][c.y]) then
            doomed[#doomed + 1] = {c.x, c.y}
        end
    end
    for _, pos in ipairs(doomed) do
        surface.delete_chunk(pos)
        for _, f in pairs(game.forces) do f.unchart_chunk(pos, surface) end
    end
    local deleted = #doomed

    notify(caller_idx, string.format("%s (%s): deleted %d / %d chunks (kept %d)",
        label, surface.name, deleted, total, total - deleted))
    return deleted, total
end

-- ─── Public API ───────────────────────────────────────────────────────

function chunk_trim.init_storage()
    -- storage.chunk_trim_queue is created lazily by the trim command; nothing to
    -- initialize here. Kept as a no-op because control.lua calls it.
end

--- Returns true if a trim is currently in progress.
function chunk_trim.is_running()
    return storage.chunk_trim_queue ~= nil
end

--- Queue trim work. opts:
---   team_force    - "team-N" to limit to one team, or nil for all teams
---   entity_buffer - chunk radius around team entities (default 12)
---   player_buffer - chunk radius around connected players (default 8)
---   caller_idx    - player index to print results to (optional)
--- Returns: ok (bool), surface_count (integer), error_msg (string | nil)
function chunk_trim.start(opts)
    opts = opts or {}
    if storage.chunk_trim_queue then
        return false, 0, "Trim already in progress."
    end

    local surfaces = {}
    for _, s in pairs(game.surfaces) do
        local fn = trimmable_owner(s)
        if fn and (not opts.team_force or fn == opts.team_force) then
            surfaces[#surfaces + 1] = s.index
        end
    end
    if #surfaces == 0 then
        return false, 0, opts.team_force
            and ("No team surfaces found for " .. opts.team_force .. ".")
            or "No team surfaces found."
    end

    storage.chunk_trim_queue = {
        surfaces      = surfaces,
        idx           = 1,
        entity_buffer = opts.entity_buffer or DEFAULT_ENTITY_BUFFER,
        player_buffer = opts.player_buffer or DEFAULT_PLAYER_BUFFER,
        caller_idx    = opts.caller_idx,
    }
    return true, #surfaces, nil
end

--- Tick driver. Processes one queued surface per call.
function chunk_trim.tick()
    local q = storage.chunk_trim_queue
    if not q then return end

    if q.idx > #q.surfaces then
        notify(q.caller_idx, ("Chunk trim complete across %d surface(s)."):format(#q.surfaces))
        storage.chunk_trim_queue = nil
        return
    end

    local surface = game.surfaces[q.surfaces[q.idx]]
    trim_surface(surface, q.entity_buffer, q.player_buffer, q.caller_idx)
    q.idx = q.idx + 1
end

return chunk_trim
