-- Multi-Team Support - shadow_race/compare.lua
-- Author: bits-orio
-- License: MIT
--
-- Comparing a team's live run with another run: the gap between them and
-- the pace of each. The arithmetic is shadow_race/timeline.lua's; this file
-- supplies the live numbers (clock and score right now) from the game.

local recorder = require("shadow_race.recorder")
local score    = require("shadow_race.score")
local timeline = require("shadow_race.timeline")

local M = {}

--- A live run's clock and score right now, or nil when its force is gone.
local function live_position(run)
    local force = game.forces[run.force]
    if not force then return nil end
    return recorder.elapsed(run), score.live(run, force)
end

--- How far `mine` (a live run) is ahead of `rival`, in ticks; negative
--- when behind; nil when the two have nothing to compare yet. The second
--- result is true for a final split: the team is past the end of an
--- archived run (see timeline.gap).
function M.gap(mine, rival, rival_live)
    local my_now, my_score = live_position(mine)
    if not my_now then return nil end
    local their_now, their_score
    if rival_live then
        their_now, their_score = live_position(rival)
        if not their_now then return nil end
    end
    local gap, final = timeline.gap(mine.points, my_now, my_score, rival.points, their_now, their_score)
    if gap then return gap, final end
    -- Before either has put science into research: the latest shared mark.
    return (timeline.mark_gap(mine.marks, rival.marks))
end

--- Science per minute over the last `window` ticks of the team's clock:
--- the team's own, and the rival's over the same stretch of its clock. A
--- rival that has not played that far gives nil.
function M.pace(mine, rival, rival_live, window)
    local my_now, my_score = live_position(mine)
    if not my_now then return nil end
    local from = math.max(0, my_now - window)
    local minutes = (my_now - from) / 3600
    if minutes <= 0 then return nil end
    local my_pace = (my_score - timeline.score_at(mine.points, from)) / minutes

    local their_end = rival.ended
    if rival_live then their_end = recorder.elapsed(rival) end
    if not their_end or their_end < my_now then return my_pace, nil end
    local their_pace = (timeline.score_at(rival.points, my_now)
        - timeline.score_at(rival.points, from)) / minutes
    return my_pace, their_pace
end

return M
