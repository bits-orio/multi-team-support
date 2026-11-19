-- Multi-Team Support - shadow_race/standings.lua
-- Author: bits-orio
-- License: MIT
--
-- Every run a team could chase, ranked against the team right now. This is
-- both the picker's list and the standings ("You are 4th of 9"), and it is
-- where auto-chase finds the nearest run ahead.
--
-- The candidates are every archived run and every other team playing now.
-- On a busy server the archive can hold hundreds of runs, so the list shown
-- keeps the runs that matter to this team and only the nearest strangers.

local recorder = require("shadow_race.recorder")
local rivals   = require("shadow_race.rivals")
local compare  = require("shadow_race.compare")

-- Runs of teams that have left, beyond the team's own: how many of the
-- nearest ahead and behind the list shows.
local STRANGERS_AHEAD  = 8
local STRANGERS_BEHIND = 4

local M = {}

-- Where a candidate stands against the team.
local AHEAD, BEHIND, PASSED, UNKNOWN = 1, 2, 3, 4

--- Every candidate with its split: { choice, run, live, gap, final, group }.
---   AHEAD    the team is behind it and can still catch it
---   BEHIND   the team is ahead of it, or level
---   PASSED   an archived run the team has gone beyond; its split is final
---   UNKNOWN  nothing to compare yet
local function candidates(mine)
    local s = storage.shadow_race
    local list = {}
    local function add(choice, run, live)
        local gap, final = compare.gap(mine, run, live)
        local group = UNKNOWN
        if final then group = PASSED
        elseif gap then group = gap < 0 and AHEAD or BEHIND end
        list[#list + 1] = { choice = choice, run = run, live = live, gap = gap, final = final, group = group }
    end
    for id, run in pairs(s.runs) do add({ kind = "run", id = id }, run, false) end
    for force_name, run in pairs(s.live) do
        if run ~= mine then add({ kind = "team", force = force_name, start = run.start }, run, true) end
    end
    return list
end

--- Runs ahead of the team first, the furthest ahead at the top; then the
--- ones behind it, the ones it has passed for good, and the ones with
--- nothing to compare. Ties keep a fixed order, so the list is the same on
--- every peer.
local function order_key(c)
    if c.choice.kind == "run" then return "r" .. string.format("%09d", c.choice.id) end
    return "t" .. c.choice.force
end

local function by_gap(a, b)
    if a.group ~= b.group then return a.group < b.group end
    if a.gap ~= b.gap and a.gap ~= nil then return a.gap < b.gap end
    return order_key(a) < order_key(b)
end

--- When a run got its first mark, or nil for a run with none.
local function first_mark(run)
    local first
    for _, t in pairs(run.marks) do
        if not first or t < first then first = t end
    end
    return first
end

--- Auto-chase: point the team at the nearest run ahead of it. Returns the
--- run the team just passed (run, live) when the target moved on because
--- the team got ahead of it, so the caller can say so.
function M.retarget(force_name)
    local choice = rivals.choice_of(force_name)
    local mine = recorder.run_of(force_name)
    if not (mine and choice and choice.kind == "auto") then return nil end

    local list = candidates(mine)
    local nearest
    for _, c in ipairs(list) do
        -- Nearest ahead: behind it by the least. by_gap puts the furthest
        -- ahead first, so the nearest is the one that sorts last.
        if c.group == AHEAD and (not nearest or by_gap(nearest, c)) then nearest = c end
    end
    -- At the very start no run is ahead yet: the team is level with the
    -- ones that had science, and has nothing to compare with the others.
    -- That is when a team plans what to hit, so it chases one of those:
    -- the one whose first mark comes latest, the first it will meet.
    if not nearest then
        local latest
        for _, c in ipairs(list) do
            local open = c.group == UNKNOWN or (c.group == BEHIND and c.gap == 0)
            local first = open and first_mark(c.run)
            if first and (not latest or first > latest
                    or (first == latest and order_key(c) < order_key(nearest))) then
                nearest, latest = c, first
            end
        end
    end

    local old = choice.target
    local passed_run, passed_live
    if old and not (nearest and rivals.same(old, nearest.choice)) then
        local run, live = rivals.run_of_choice(old)
        local gap, final = nil, nil
        if run then gap, final = compare.gap(mine, run, live) end
        -- Level is not passed: a team moves between level runs at the start.
        if final or (gap and gap > 0) then passed_run, passed_live = run, live end
    end
    choice.target = nearest and nearest.choice or nil
    return passed_run, passed_live
end

--- The picker's rows for a player, ranked, with the team's own place:
---   rows = { { choice, label, gap, final, current, own, recorded, run_id, pinned, pinnable }, ... }
---   place, total   the team's rank among every comparable run, and how
---                  many runs that is counting the team itself
--- `own` marks a run of one of the team's members, `recorded` an archived
--- run as against a team that is playing now; run_id, pinned and
--- pinnable speak of the asking player's kept runs.
function M.rows(force_name, player_index)
    local s = storage.shadow_race
    local mine = recorder.run_of(force_name)
    if not (s and mine) then return {}, 1, 1 end

    local list = candidates(mine)
    table.sort(list, by_gap)

    local own_ids = {}
    for _, member in ipairs(rivals.members_of(force_name)) do
        local kept = s.kept[member.index]
        for _, id in ipairs(kept and kept.recent or {}) do own_ids[id] = true end
        if kept and kept.pinned then own_ids[kept.pinned] = true end
    end
    local asker = s.kept[player_index] or { recent = {} }
    local recent = {}
    for _, id in ipairs(asker.recent) do recent[id] = true end

    local current = rivals.choice_of(force_name)
    local target = current
    if current and current.kind == "auto" then target = current.target end

    -- The team's place: one more than the comparable runs ahead of it.
    local ahead, comparable = 0, 0
    for _, c in ipairs(list) do
        if c.group ~= UNKNOWN then comparable = comparable + 1 end
        if c.group == AHEAD then ahead = ahead + 1 end
    end

    -- Strangers are kept only near the team: count outward from its place.
    local keep = {}
    local shown_ahead, shown_behind = 0, 0
    for i = ahead, 1, -1 do
        local c = list[i]
        local stranger = not c.live and not own_ids[c.choice.id]
        if not stranger then keep[i] = true
        elseif shown_ahead < STRANGERS_AHEAD then keep[i] = true; shown_ahead = shown_ahead + 1 end
    end
    for i = ahead + 1, #list do
        local c = list[i]
        local stranger = not c.live and not own_ids[c.choice.id]
        if not stranger then keep[i] = true
        elseif shown_behind < STRANGERS_BEHIND then keep[i] = true; shown_behind = shown_behind + 1 end
    end

    local rows = {}
    for i, c in ipairs(list) do
        if keep[i] or rivals.same(c.choice, target) then
            local id = c.choice.id
            rows[#rows + 1] = {
                choice = c.choice, label = rivals.label(c.run, c.live), gap = c.gap, final = c.final,
                current = rivals.same(c.choice, target), own = id ~= nil and own_ids[id] == true,
                recorded = not c.live,
                run_id = id, pinned = id ~= nil and asker.pinned == id,
                pinnable = id ~= nil and recent[id] == true,
            }
        end
    end
    return rows, ahead + 1, comparable + 1
end

return M
