-- Multi-Team Support - shadow_race/archive.lua
-- Author: bits-orio
-- License: MIT
--
-- What becomes of a run when its slot is released, and which runs are kept.
--
-- MTS reuses slots and wipes them on release, so a finished run belongs to
-- the players who were on the team, never to the force name.
--
-- Storage:
--   storage.shadow_race.runs[id] = run        archived; a recorder run plus
--       id, label (team name at the end), leader (player name), ended
--       (elapsed ticks at the release)
--   storage.shadow_race.kept[player_index] = { recent = { id, ... }, pinned = id }
--       recent: the player's latest runs, newest first, at most KEEP_RECENT
--       pinned: the run the player pinned; it outlives the recent list
--
-- A run stays in storage while any player keeps it.

local recorder = require("shadow_race.recorder")
local score    = require("shadow_race.score")
local helpers  = require("scripts.helpers")

local KEEP_RECENT = 3

-- The whole archive never holds more than this many runs. Each player
-- keeps up to four, so a server that has seen hundreds of players would
-- otherwise carry every one of their runs for ever. Measured on the rig: a
-- 40 hour run is about 14 KB, and ranking a team against 400 runs costs
-- about 1.2 ms.
local MAX_RUNS = 200

local M = {}

local function count(tbl)
    local n = 0
    for _ in pairs(tbl) do n = n + 1 end
    return n
end

M.KEEP_RECENT = KEEP_RECENT
M.MAX_RUNS    = MAX_RUNS

local function kept_of(s, player_index)
    local kept = s.kept[player_index]
    if not kept then
        kept = { recent = {} }
        s.kept[player_index] = kept
    end
    return kept
end

--- Take a run out of every player's kept runs.
local function unkeep(s, id)
    for _, kept in pairs(s.kept) do
        for i = #kept.recent, 1, -1 do
            if kept.recent[i] == id then table.remove(kept.recent, i) end
        end
        if kept.pinned == id then kept.pinned = nil end
    end
end

--- Over the cap, the oldest runs go first: unpinned ones, then pinned.
local function enforce_cap(s)
    local over = count(s.runs) - MAX_RUNS
    if over <= 0 then return end
    local pinned = {}
    for _, kept in pairs(s.kept) do
        if kept.pinned then pinned[kept.pinned] = true end
    end
    local ids = {}
    for id in pairs(s.runs) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b)
        if (pinned[a] or false) ~= (pinned[b] or false) then return not pinned[a] end
        return a < b
    end)
    for i = 1, over do
        unkeep(s, ids[i])
        s.runs[ids[i]] = nil
    end
end

--- Delete every archived run no player keeps any more, and hold the
--- archive to its cap.
local function collect(s)
    local held = {}
    for _, kept in pairs(s.kept) do
        for _, id in ipairs(kept.recent) do held[id] = true end
        if kept.pinned then held[kept.pinned] = true end
    end
    for id in pairs(s.runs) do
        if not held[id] then s.runs[id] = nil end
    end
    enforce_cap(s)
end

--- A run with no research and no milestone is nobody's rival.
local function is_empty(run)
    return run.score <= 0 and next(run.marks) == nil
end

--- The team's leader as the archive remembers them: name and chat colour.
local function leader_of(force_name)
    local index = (storage.team_leader or {})[force_name]
    local player = index and game.get_player(index)
    if not (player and player.valid) then return nil end
    local color = player.chat_color
    return player.name, { r = color.r, g = color.g, b = color.b }
end

--- The team's slot is being released: its run ends here. Call before the
--- slot is wiped, while the team's name and leader are still stored.
--- Returns the archived run's id, or nil for a run not worth keeping.
function M.close(force_name)
    local s = recorder.init_storage()
    local run = s.live[force_name]
    if not run then return nil end
    s.live[force_name] = nil

    recorder.sample_run(run)
    if is_empty(run) then return nil end
    recorder.end_flat(run)

    local id = s.next_id
    s.next_id = id + 1
    run.id     = id
    run.label  = helpers.display_name(force_name)
    run.leader, run.leader_color = leader_of(force_name)
    run.ended  = recorder.elapsed(run)
    run.cur_name, run.cur_cost, run.flat_t = nil, nil, nil
    s.runs[id] = run

    for player_index in pairs(run.members) do
        local recent = kept_of(s, player_index).recent
        table.insert(recent, 1, id)
        recent[KEEP_RECENT + 1] = nil
    end
    collect(s)
    -- A run nobody keeps (its members were all removed from the game) is
    -- gone already; say so, or its chasers would be pointed at nothing.
    return s.runs[id] and id or nil
end

--- Whether the run is one of the player's recent ones, which are the ones
--- they may pin.
local function is_recent(kept, id)
    for _, recent_id in ipairs(kept.recent) do
        if recent_id == id then return true end
    end
    return false
end

--- Pin one of the player's recent runs. It replaces their earlier pin and
--- stays kept after newer runs push it out of the recent list.
function M.pin(player_index, id)
    local s = recorder.init_storage()
    local kept = s.kept[player_index]
    if not (kept and s.runs[id] and is_recent(kept, id)) then return false end
    kept.pinned = id
    collect(s)
    return true
end

function M.unpin(player_index)
    local s = recorder.init_storage()
    local kept = s.kept[player_index]
    if not (kept and kept.pinned) then return end
    kept.pinned = nil
    collect(s)
end

--- The player's kept runs: { recent = { run, ... }, pinned = run or nil }.
function M.runs_of(player_index)
    local s = storage.shadow_race
    local out = { recent = {} }
    local kept = s and s.kept[player_index]
    if not kept then return out end
    for _, id in ipairs(kept.recent) do out.recent[#out.recent + 1] = s.runs[id] end
    out.pinned = kept.pinned and s.runs[kept.pinned] or nil
    return out
end

--- The player is gone from the game. A removed index can be reused, so the
--- next player with it must not inherit these runs.
function M.forget_player(player_index)
    local s = storage.shadow_race
    if not s then return end
    s.kept[player_index] = nil
    for _, run in pairs(s.live) do run.members[player_index] = nil end
    for _, run in pairs(s.runs) do run.members[player_index] = nil end
    collect(s)
end

-- ─── Rebuilding a run MTS did not record ──────────────────────────────

--- Every level of the technology the team has finished, in science packs.
--- A researched technology has all its levels; one still in progress has
--- those below its current level.
local function researched_cost(tech)
    local proto = tech.prototype
    local last = tech.researched and proto.max_level or tech.level - 1
    local total = 0
    for level = proto.level, last do
        total = total + score.prototype_cost(proto, level)
    end
    return total
end

--- Rebuild the run of a team that was playing before the recorder existed,
--- from the research ticks and pack records MTS has always kept. A
--- technology with several finished levels has only its last tick stored,
--- so all of them land on that tick. A script grant later in the run
--- cannot be told from research and is counted.
function M.rebuild(force_name)
    local start = (storage.team_clock_start or {})[force_name]
    local force = game.forces[force_name]
    if not (start and force) then return nil end
    local run = recorder.open(force_name, start)
    run.rebuilt = true

    local finished = {}
    for name, tick in pairs((storage.tech_research_ticks or {})[force_name] or {}) do
        local tech = force.technologies[name]
        -- Research ticks do not say who granted a technology. What a team
        -- has at the tick its clock starts was granted by script (the pool
        -- copy, a mod's pre-grant), which the recorder never counts.
        if tech and tick > start then
            finished[#finished + 1] = { name = name, t = tick - start, tech = tech }
        end
    end
    table.sort(finished, function(a, b)
        if a.t ~= b.t then return a.t < b.t end
        return a.name < b.name
    end)
    for _, entry in ipairs(finished) do
        run.base = run.base + researched_cost(entry.tech)
        recorder.add_point(run, entry.t, run.base)
        if entry.tech.researched then run.marks["tech:" .. entry.name] = entry.t end
    end

    for key, record in pairs(storage.milestone_records or {}) do
        local item = key:match("^science:(.+)@0$")
        local entry = item and record.entries and record.entries[force_name]
        if entry and entry.elapsed then run.marks["pack:" .. item] = entry.elapsed end
    end
    run.mark_count = count(run.marks)

    recorder.sample_run(run)
    return run
end

--- Give every team that holds a slot and has a running clock a run, if it
--- has none. Runs on an update, for saves older than the recorder.
function M.rebuild_missing()
    local s = recorder.init_storage()
    for slot, status in pairs(storage.team_pool or {}) do
        local force_name = "team-" .. slot
        if status == "occupied" and not s.live[force_name] then M.rebuild(force_name) end
    end
end

return M
