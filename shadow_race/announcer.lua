-- Multi-Team Support - shadow_race/announcer.lua
-- Author: bits-orio
-- License: MIT
--
-- Tells a racing team when its shadow reaches a notable mark: "at this
-- point of your clock, the shadow had blue science".
--
-- Two ways a mark comes due:
--   playback  the shadow reached it at elapsed time T, and the team's own
--             clock now passes T. Checked on the one-second pass.
--   live      the shadow is a team playing now, behind the chasing team's
--             clock: its mark is news the moment it happens.
--
-- Storage:
--   storage.shadow_race.told[force_name] = the elapsed time up to which
--       the shadow's marks have been played back to this team. Set to the
--       team's clock whenever its shadow changes, so a new shadow never
--       replays its whole history.

local recorder  = require("shadow_race.recorder")
local rivals    = require("shadow_race.rivals")
local marks     = require("shadow_race.marks")
local standings = require("shadow_race.standings")
local helpers   = require("scripts.helpers")

local M = {}

local function told_table()
    local s = recorder.init_storage()
    s.told = s.told or {}
    return s.told
end

local function tell(force_name, rival, live, key, t)
    rivals.tell(force_name, {"mts-chat.shadow-mark", rivals.label(rival, live),
        marks.label(key), helpers.ls_duration(t)})
end

--- The team's shadow changed: playback starts from the team's clock now.
function M.reset(force_name)
    local run = recorder.run_of(force_name)
    told_table()[force_name] = run and recorder.elapsed(run) or nil
end

--- The race was switched back on: playback resumes from every team's
--- clock now, never from where it stood when the race was switched off.
function M.reset_all()
    local s = storage.shadow_race
    for force_name in pairs(s and s.rival or {}) do M.reset(force_name) end
end

--- Auto-chase: move a team to the nearest run ahead, and say so when it
--- got there by passing its last target.
function M.retarget(force_name)
    local passed, passed_live = standings.retarget(force_name)
    if not passed then return end
    local next_run, next_live = rivals.rival_of(force_name)
    local passed_label = rivals.label(passed, passed_live)
    if next_run then
        rivals.tell(force_name, {"mts-chat.shadow-passed-next", passed_label,
            rivals.label(next_run, next_live)})
    else
        rivals.tell(force_name, {"mts-chat.shadow-passed-all", passed_label,
            helpers.team_tag(force_name)})
    end
end

--- One racing team per pass, in turn. Ranking a team against the whole
--- archive is the one costly step here (1.2 ms against 400 runs on the
--- rig), so the passes share it out instead of doing every team at once.
--- storage.shadow_race.auto_turn is the team whose turn it was last; the
--- turn goes round in name order, which every peer agrees on.
local function retarget_next(s)
    local names = {}
    for force_name in pairs(s.rival) do names[#names + 1] = force_name end
    table.sort(names)
    local turn = names[1]
    for _, force_name in ipairs(names) do
        if s.auto_turn and force_name > s.auto_turn then turn = force_name; break end
    end
    s.auto_turn = turn
    if s.rival[turn].kind == "auto" then M.retarget(turn) end
end

--- The one-second pass: play back every notable mark of the shadow that
--- the team's clock has passed since the last pass. The clock position is
--- kept for every racing team, also while it has no shadow to play back
--- (auto-chase with nothing ahead), so a shadow that appears later starts
--- from now.
function M.tick()
    if not rivals.enabled() then return end
    local s = storage.shadow_race
    if not (s and s.rival and next(s.rival)) then return end
    retarget_next(s)
    local told = told_table()
    for force_name in pairs(s.rival) do
        local mine = recorder.run_of(force_name)
        if mine then
            local now = recorder.elapsed(mine)
            local from = told[force_name] or now
            local rival, live = rivals.rival_of(force_name)
            if rival then
                for _, mark in ipairs(marks.notable_sorted(rival)) do
                    if mark.t > from and mark.t <= now then tell(force_name, rival, live, mark.key, mark.t) end
                end
            end
            told[force_name] = now
        end
    end
end

--- Whether a team's choice, or its auto-chase target, is this live run.
local function chases(choice, run)
    local target = choice.kind == "auto" and choice.target or choice
    return target ~= nil and target.kind == "team"
        and target.force == run.force and target.start == run.start
end

--- A live run just got a mark. Teams chasing that run whose clock is
--- already past the mark's time hear it now; for the others playback will
--- reach it. Telling it here moves the team's playback position past the
--- mark, so the next pass does not tell it again.
function M.on_mark(run, key, t)
    local s = storage.shadow_race
    if not (s and s.rival and next(s.rival) and rivals.enabled()) then return end
    local told = told_table()
    for chaser, choice in pairs(s.rival) do
        local mine = chases(choice, run) and recorder.run_of(chaser)
        if mine and recorder.elapsed(mine) >= t and marks.is_notable(key) then
            tell(chaser, run, true, key, t)
            if (told[chaser] or 0) < t then told[chaser] = t end
        end
    end
end

return M
