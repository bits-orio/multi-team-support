-- Multi-Team Support - shadow_race/recorder.lua
-- Author: bits-orio
-- License: MIT
--
-- Records the run of every team that holds a slot. Always on: the admin
-- flag hides the race from players, it never stops the recording, so no run
-- has a hole in it.
--
-- Storage:
--   storage.shadow_race.live[force_name] = run
--   run = {
--     force   = "team-4",
--     start   = tick the team's clock started,
--     members = { [player_index] = true },   everyone ever on the team
--     base    = score of the finished research,
--     score   = the last recorded score (never falls),
--     points  = { t1, s1, t2, s2, ... }      see shadow_race/timeline.lua
--     marks   = { [key] = elapsed },         "tech:<name>", "pack:<item>",
--                                            "rocket", "planet:<name>"
--     mark_count                             how many marks, so readers can
--                                            tell when the set has grown
--     home    = the planet the run started on (never an arrival)
--     cur_name, cur_cost                     the research in progress
--     flat_t                                 last sample with no change
--   }

local score = require("shadow_race.score")

local M = {}

function M.init_storage()
    storage.shadow_race = storage.shadow_race or {}
    local s = storage.shadow_race
    s.live    = s.live    or {}
    s.runs    = s.runs    or {}
    s.kept    = s.kept    or {}
    s.next_id = s.next_id or 1
    return s
end

--- The live run of a team, or nil.
function M.run_of(force_name)
    local s = storage.shadow_race
    return s and s.live[force_name] or nil
end

function M.elapsed(run)
    return game.tick - run.start
end

--- Append a point. A stretch with no change is kept as one flat segment:
--- the samples inside it are skipped, and its end is written only when the
--- score moves again.
local function add_point(run, t, s)
    local points = run.points
    local n = #points
    if n > 0 and s <= points[n] then
        run.flat_t = t
        return
    end
    if run.flat_t and n > 0 and run.flat_t > points[n - 1] then
        points[n + 1], points[n + 2] = run.flat_t, points[n]
        n = n + 2
    end
    run.flat_t = nil
    points[n + 1], points[n + 2] = t, s
    run.score = s
end

--- The run is ending: write the end of a flat stretch still open, so the
--- timeline reaches the run's last sample instead of its last rise.
function M.end_flat(run)
    local points = run.points
    local n = #points
    if run.flat_t and n > 0 and run.flat_t > points[n - 1] then
        points[n + 1], points[n + 2] = run.flat_t, points[n]
    end
    run.flat_t = nil
end

--- A team's clock started: its run begins. start_tick is the clock's, which
--- is the claim, or Start Playing under Staged Start.
function M.open(force_name, start_tick)
    local s = M.init_storage()
    local run = {
        force = force_name, start = start_tick, members = {},
        base = 0, score = 0, points = {}, marks = {},
    }
    local force = game.forces[force_name]
    if force then
        for _, player in pairs(force.players) do run.members[player.index] = true end
    end
    s.live[force_name] = run
    return run
end

function M.add_member(force_name, player_index)
    local run = M.run_of(force_name)
    if run then run.members[player_index] = true end
end

-- Called with (run, key, elapsed) for every new mark. shadow_race/hooks.lua
-- points it at the announcer at parse time: the announcer needs the rivals,
-- and the rivals need this module.
local on_mark = nil
function M.set_mark_hook(fn) on_mark = fn end

local function add_mark(run, key)
    if run.marks[key] then return end
    local t = M.elapsed(run)
    run.marks[key] = t
    run.mark_count = (run.mark_count or 0) + 1   -- see marks.notable_sorted
    if on_mark then on_mark(run, key, t) end
end

--- A member is on a planet. The first planet a run sees is where it
--- starts, its home; every other planet is an arrival, marked once.
function M.arrive(force_name, planet)
    local run = M.run_of(force_name)
    if not run then return end
    if not run.home then
        run.home = planet
    elseif planet ~= run.home then
        add_mark(run, "planet:" .. planet)
    end
end

--- A milestone on the run's timeline. Only the first time counts.
function M.mark(force_name, key)
    local run = M.run_of(force_name)
    if run then add_mark(run, key) end
end

function M.on_research_started(event)
    local tech = event.research
    local run = M.run_of(tech.force.name)
    if run then score.note_current(run, tech) end
end

--- Research granted by script is not the team's progress, the rule Records
--- use too (scripts/tech_records.lua).
function M.on_research_finished(event)
    if event.by_script then return end
    local tech = event.research
    local run = M.run_of(tech.force.name)
    if not run then return end
    run.base = run.base + score.finished_cost(run, tech)
    add_point(run, M.elapsed(run), math.max(run.base, run.score))
    -- A technology with levels still to go is score only: it has no single
    -- moment to mark.
    if tech.researched then add_mark(run, "tech:" .. tech.name) end
    score.note_current(run, tech.force.current_research)
end

--- One sample of a run: the progress of its current research.
function M.sample_run(run)
    local force = game.forces[run.force]
    if not force then return end
    score.note_current(run, force.current_research)
    add_point(run, M.elapsed(run), score.live(run, force))
end

--- The periodic sample of every live run. One property read per team that
--- is researching.
function M.sample_all()
    local s = storage.shadow_race
    if not s then return end
    for _, run in pairs(s.live) do M.sample_run(run) end
end

M.add_point = add_point

return M
