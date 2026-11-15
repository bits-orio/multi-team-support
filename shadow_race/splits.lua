-- Multi-Team Support - shadow_race/splits.lua
-- Author: bits-orio
-- License: MIT
--
-- The splits of a team against its shadow: every mark either run has, on
-- one list in the order of the race, and that list as text for a
-- spreadsheet. Pure: it reads two runs and writes nothing.
--
-- A row is { key, mine = t or nil, theirs = t or nil }, times in elapsed
-- ticks. A row is decided once the team has the mark (beaten or not), or
-- once the team's clock is past the shadow's time for it (lost).

local M = {}

--- Every mark of the two runs, ordered by when the shadow reached it; a
--- mark only the team has sits at the team's own time.
function M.rows(mine, rival)
    local rows = {}
    for key, t in pairs(rival.marks) do
        rows[#rows + 1] = { key = key, theirs = t, mine = mine.marks[key] }
    end
    for key, t in pairs(mine.marks) do
        if not rival.marks[key] then rows[#rows + 1] = { key = key, mine = t } end
    end
    table.sort(rows, function(a, b)
        local at, bt = a.theirs or a.mine, b.theirs or b.mine
        if at ~= bt then return at < bt end
        return a.key < b.key
    end)
    return rows
end

--- Whether a row is still to be decided at the team's clock `now`.
function M.is_open(row, now)
    return row.mine == nil and row.theirs ~= nil and row.theirs > now
end

--- The index of the first row still to be decided, or nil when none is.
function M.next_index(rows, now)
    for i, row in ipairs(rows) do
        if M.is_open(row, now) then return i end
    end
    return nil
end

--- Between which two shared marks the team gained the most on its shadow
--- and lost the most: { from, to, change } each, or nil.
function M.swings(rows)
    local gained, lost, previous
    for _, row in ipairs(rows) do
        if row.mine and row.theirs then
            local split = row.theirs - row.mine
            if previous then
                local change = split - previous.split
                local swing = { from = previous.key, to = row.key, change = change }
                if change > 0 and (not gained or change > gained.change) then gained = swing end
                if change < 0 and (not lost or change < lost.change) then lost = swing end
            end
            previous = { key = row.key, split = split }
        end
    end
    return gained, lost
end

-- ─── Export ───────────────────────────────────────────────────────────

--- "0:04:27.50": hours, minutes, seconds and hundredths, from ticks.
local function clock(ticks)
    local hundredths = math.floor(ticks * 100 / 60 + 0.5)
    local s = math.floor(hundredths / 100)
    return string.format("%d:%02d:%02d.%02d", math.floor(s / 3600), math.floor(s / 60) % 60, s % 60,
        hundredths % 100)
end

--- A split the way speedrun timers write it: "-" ahead of the shadow,
--- "+" behind it.
local function signed(ticks)
    return (ticks < 0 and "-" or "+") .. clock(math.abs(ticks))
end

--- The splits as tab-separated text, one mark per line, ready to paste
--- into a spreadsheet. Marks keep their internal names, which do not
--- depend on anyone's language. `my_name` and `their_name` are plain text.
function M.export(mine, rival, now, my_name, their_name)
    local lines = {
        "Shadow Race splits",
        "you\t" .. my_name .. "\t" .. clock(now),
        "shadow\t" .. their_name,
        "split: - ahead of the shadow, + behind it",
        "",
        "milestone\tyou\tshadow\tsplit",
    }
    for _, row in ipairs(M.rows(mine, rival)) do
        lines[#lines + 1] = table.concat({
            row.key,
            row.mine and clock(row.mine) or "",
            row.theirs and clock(row.theirs) or "",
            row.mine and row.theirs and signed(row.mine - row.theirs) or "",
        }, "\t")
    end
    return table.concat(lines, "\n")
end

return M
