-- Multi-Team Support - shadow_race/timeline.lua
-- Author: bits-orio
-- License: MIT
--
-- The arithmetic of a run's timeline. Pure: no game, no storage, so the
-- headless tests run it as it is.
--
-- A timeline is a flat array of pairs, { t1, s1, t2, s2, ... }: elapsed
-- ticks on the team's clock and the score then. Both only ever rise. Between
-- two points the score is a straight line; a stall is two points with the
-- same score.

local M = {}

--- Index of the last pair whose value at `offset` (1 = time, 2 = score) is
--- at or below `x`; 0 when every pair is above it.
local function last_at_or_below(points, x, offset)
    local lo, hi = 1, #points / 2
    local found = 0
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        if points[mid * 2 - 2 + offset] <= x then
            found = mid
            lo = mid + 1
        else
            hi = mid - 1
        end
    end
    return found
end

--- The last point: elapsed, score. 0, 0 for an empty timeline.
function M.last(points)
    local n = #points
    if n == 0 then return 0, 0 end
    return points[n - 1], points[n]
end

--- The score at elapsed time `t`. 0 before the first point, the last score
--- after the last one.
function M.score_at(points, t)
    local i = last_at_or_below(points, t, 1)
    if i == 0 then return 0 end
    local t1, s1 = points[i * 2 - 1], points[i * 2]
    local t2, s2 = points[i * 2 + 1], points[i * 2 + 2]
    if not t2 or t2 == t1 then return s1 end
    return s1 + (s2 - s1) * (t - t1) / (t2 - t1)
end

--- The elapsed time at which the run first reached score `s`, or nil when
--- it never did. A score of 0 is reached at the start.
function M.time_at(points, s)
    if s <= 0 then return 0 end
    local n = #points / 2
    if n == 0 or points[n * 2] < s then return nil end
    -- The first pair at or above s is the one after the last pair below it.
    local lo, hi, first = 1, n, n
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        if points[mid * 2] >= s then
            first = mid
            hi = mid - 1
        else
            lo = mid + 1
        end
    end
    local t2, s2 = points[first * 2 - 1], points[first * 2]
    if first == 1 then return t2 end
    local t1, s1 = points[first * 2 - 3], points[first * 2 - 2]
    if s2 == s1 then return t2 end
    return t1 + (t2 - t1) * (s - s1) / (s2 - s1)
end

--- The elapsed time at which the run's score rose above `s`, or nil when
--- it never did. With M.time_at this brackets the stretch the run spent at
--- exactly `s`: a stall, or the wait before its first research.
function M.time_left(points, s)
    local n = #points / 2
    if n == 0 or points[n * 2] <= s then return nil end
    local lo, hi, first = 1, n, n
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        if points[mid * 2] > s then
            first = mid
            hi = mid - 1
        else
            lo = mid + 1
        end
    end
    local t2, s2 = points[first * 2 - 1], points[first * 2]
    if first == 1 then return t2 end
    local t1, s1 = points[first * 2 - 3], points[first * 2 - 2]
    return t1 + (t2 - t1) * (s - s1) / (s2 - s1)
end

--- time_at for a run that is still being played: its position right now
--- (now, score) counts as one more point after the recorded ones, so a
--- score reached since the last sample has a time.
local function time_at_live(points, s, now, score)
    local t = M.time_at(points, s)
    if t or not now or score < s then return t end
    local last_t, last_s = M.last(points)
    return last_t + (now - last_t) * (s - last_s) / (score - last_s)
end

--- time_left with the same extra point.
local function time_left_live(points, s, now, score)
    local t = M.time_left(points, s)
    if t or not now or score <= s then return t end
    local last_t, last_s = M.last(points)
    return last_t + (now - last_t) * (s - last_s) / (score - last_s)
end

--- How far run A is ahead of rival B, in ticks; negative when behind. nil
--- while neither run has a score to compare (see M.mark_gap).
--- A second result, true, marks a final split: B is an archived run and A
--- has reached everything it ever had, so the split is how much sooner or
--- later A got to B's last score, and it will not change again.
---   a_now, a_score  A's clock and score right now
---   b_points        B's timeline
---   b_now, b_score  B's clock and score right now, for a live rival; nil
---                   for an archived run, which stands where it ended
function M.gap(a_points, a_now, a_score, b_points, b_now, b_score)
    local b_last_t, b_last_s = M.last(b_points)
    b_score = b_score or b_last_s
    if a_score <= 0 and b_score <= 0 then return nil end

    -- B has been where A is. B held this score from the moment it reached
    -- it until it moved on: A is ahead before that stretch, level inside
    -- it, and behind by the time since B moved on.
    if a_score <= b_score then
        local reached = time_at_live(b_points, a_score, b_now, b_score)
        if reached then
            if a_now < reached then return reached - a_now end
            local left = time_left_live(b_points, a_score, b_now, b_score)
            if left and a_now > left then return left - a_now end
            -- B stands on this score. A live B is level with A; an archived
            -- B ended here, which makes this A's final split against it.
            if left or b_now then return 0 end
            return reached - (time_at_live(a_points, a_score, a_now, a_score) or a_now), true
        end
    end

    -- A is past everything B has: compare at B's own position instead. A
    -- live B is still on its clock; an archived B got there and stopped.
    local a_time = time_at_live(a_points, b_score, a_now, a_score) or a_now
    local b_time = b_now or M.time_at(b_points, b_score) or b_last_t
    return b_time - a_time, b_now == nil
end

--- The gap from the latest mark both runs have, for the stretch before
--- either has a score. marks are { [key] = elapsed }. Returns ticks ahead
--- (negative behind) and the key, or nil when they share none.
function M.mark_gap(a_marks, b_marks)
    local best_key, best_t
    for key, a_t in pairs(a_marks) do
        -- Marks on the same tick: the key decides, never the table order.
        if b_marks[key] and (not best_t or a_t > best_t or (a_t == best_t and key < best_key)) then
            best_key, best_t = key, a_t
        end
    end
    if not best_key then return nil end
    return b_marks[best_key] - best_t, best_key
end

return M
