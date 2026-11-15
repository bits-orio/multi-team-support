-- Multi-Team Support - shadow_race/gui/splits.lua
-- Author: bits-orio
-- License: MIT
--
-- The splits window: every milestone of the team's run beside its
-- shadow's. It is the race report and the "what comes next" panel in one:
--   a decided milestone shows both times and the split,
--   a lost one (the shadow's time has passed, the team lacks it) says so,
--   the next few still open count down on the team's clock.
-- The list shows about five rows and scrolls; whenever the race moves on
-- it scrolls itself to the first milestone still open.
--
-- It is there from the moment the team's clock starts, which is when a
-- team plans what to hit, and it stays until the player closes it
-- (pref.splits_closed); the Shadow Race window brings it back. It never
-- goes away on its own: a team that has passed every run keeps the splits
-- against the last one, and a team chasing nothing sees its own times.
-- Driven by gui/hud_clock.lua's one-second pass. That pass rewrites only
-- the countdowns; the rows are rebuilt when the frame's signature changes:
-- another shadow, a new mark in either run, or a countdown reaching zero.
--
-- Export puts the splits as text in a box with everything selected: the
-- game gives a mod no way to write the clipboard, Ctrl+C does the rest.

local recorder = require("shadow_race.recorder")
local rivals   = require("shadow_race.rivals")
local marks    = require("shadow_race.marks")
local splits   = require("shadow_race.splits")
local chip     = require("shadow_race.gui.chip")
local frames   = require("shadow_race.gui.frames")
local helpers  = require("scripts.helpers")

local M = {}

local FRAME      = "mts_shadow_splits"
local VISIBLE    = 5     -- rows the list shows at once
local ROW_HEIGHT = 24
local COUNTDOWNS = 5     -- open milestones that get a live countdown
local WIDTHS     = { 260, 70, 70, 120 }   -- milestone, you, shadow, split

-- Stands in for the shadow of a team that is chasing nothing.
local NO_RUN = { marks = {} }

local function cell(parent, width, caption, name)
    local label = parent.add{type = "label", caption = caption, name = name}
    label.style.width = width
    return label
end

--- What decides whether the rows on screen are still the right ones.
local function signature(mine, rival)
    if not rival then return "solo:" .. (mine.mark_count or 0) end
    return (rival.id or (rival.force .. "@" .. rival.start))
        .. ":" .. (mine.mark_count or 0) .. ":" .. (rival.mark_count or 0)
end

local function swing_line(frame, caption)
    local line = frame.add{type = "label", caption = caption}
    line.style.font = "default-small"
    line.style.single_line = false
    line.style.maximal_width = 520
end

--- The split cell of one row. Open rows return nothing here: the first
--- few get a countdown, written by the caller.
local function split_caption(row, now)
    if row.mine and row.theirs then return chip.split_caption(row.theirs - row.mine) end
    if row.theirs and row.theirs <= now then return {"mts-gui.shadow-splits-lost"} end
    return ""
end

--- What a run is called in the export, where only plain text will do.
local function plain_name(run, live)
    if not run then return "-" end
    if live then return helpers.display_name(run.force) end
    return (run.leader or run.label or "?") .. " (" .. chip.fmt(run.ended or 0) .. ")"
end

--- The export box: the splits as text. With `grab` it is selected and
--- focused so that Ctrl+C copies it; a rebuild puts it back without
--- taking the keyboard from a player who is walking.
local function add_export(frame, mine, rival, live, grab)
    frame.add{type = "label", name = "export_hint", caption = {"mts-gui.shadow-splits-export-hint"}}
    local box = frame.add{type = "text-box", name = "export",
        text = splits.export(mine, rival or NO_RUN, recorder.elapsed(mine), helpers.display_name(mine.force),
            plain_name(rival, live))}
    box.read_only = true
    box.style.width = 520
    box.style.height = 140
    if grab then
        box.select_all()
        box.focus()
    end
end

--- Build the window for a team and its shadow, in place of an open one.
--- Without a shadow (rival nil) it lists the team's own milestones.
local function build(player, mine, rival, live)
    local old = player.gui.screen[FRAME]
    local location = old and old.location or {x = 5, y = 215}
    local exporting = old ~= nil and old.export ~= nil
    if old then old.destroy() end

    local title = rival and {"mts-gui.shadow-splits-title", rivals.label(rival, live)}
        or {"mts-gui.shadow-splits-title-solo"}
    local frame, bar = frames.titled(player, FRAME, title, location, true)
    frames.icon(bar, "utility/export", "export", {"mts-tip.shadow-splits-export"})
    frames.finish_bar(bar, "splits_close")
    local now = recorder.elapsed(mine)
    local rows = splits.rows(mine, rival or NO_RUN)
    if not rival then swing_line(frame, {"mts-gui.shadow-splits-pick"}) end
    local gained, lost = splits.swings(rows)
    if gained then
        swing_line(frame, {"mts-gui.shadow-splits-gained", marks.label(gained.from),
            marks.label(gained.to), chip.fmt(gained.change)})
    end
    if lost then
        swing_line(frame, {"mts-gui.shadow-splits-lost-most", marks.label(lost.from),
            marks.label(lost.to), chip.fmt(lost.change)})
    end

    local header = frame.add{type = "flow", direction = "horizontal"}
    header.style.horizontal_spacing = 0
    header.style.left_padding = 4
    local headers = { {"mts-gui.shadow-splits-milestone"}, {"mts-gui.shadow-splits-you"},
                      {"mts-gui.shadow-splits-shadow"}, {"mts-gui.shadow-splits-split"} }
    for i, caption in ipairs(headers) do
        cell(header, WIDTHS[i], caption).style.font = "default-semibold"
    end
    local pane = frame.add{type = "scroll-pane", name = "pane", vertical_scroll_policy = "always",
        horizontal_scroll_policy = "never"}
    pane.style.height = VISIBLE * ROW_HEIGHT
    local list = pane.add{type = "table", name = "list", column_count = #WIDTHS}
    list.style.horizontal_spacing = 0
    list.style.vertical_spacing = 0

    -- The countdown labels are found again by name on the one-second pass;
    -- tags keep the shadow's time for each, and when the first one is due.
    local next_index = splits.next_index(rows, now)
    local due, focus = {}, nil
    for i, row in ipairs(rows) do
        local name = cell(list, WIDTHS[1], marks.label(row.key))
        name.style.height = ROW_HEIGHT
        cell(list, WIDTHS[2], row.mine and chip.fmt(row.mine) or "-")
        cell(list, WIDTHS[3], row.theirs and chip.fmt(row.theirs) or "-")
        local counting = #due < COUNTDOWNS and splits.is_open(row, now)
        if counting then due[#due + 1] = row.theirs end
        local split = counting and {"mts-gui.shadow-splits-in", chip.fmt(row.theirs - now)}
            or split_caption(row, now)
        cell(list, WIDTHS[4], split, counting and ("due" .. #due) or nil)
        if i == next_index then
            name.style.font = "default-bold"
            focus = name
        end
        focus = focus or (i == #rows and name) or nil
    end
    if #rows == 0 then
        pane.visible = false
        frame.add{type = "label", caption = {"mts-gui.shadow-splits-empty"}}
    end

    frame.tags = { signature = signature(mine, rival), due = due }
    if exporting then add_export(frame, mine, rival, live, false) end
    if focus then pane.scroll_to_element(focus, "top-third") end
    return frame
end

--- Bring one player's window in line with their team: there while the
--- team's clock runs and the player has not closed it.
function M.update_player(player, force_name)
    local frame = player.gui.screen[FRAME]
    local wanted = force_name and rivals.enabled() and rivals.wants_splits(player.index)
        and not rivals.is_hidden(player.index)
    local mine = wanted and recorder.run_of(force_name)
    if not mine then
        if frame then frame.destroy() end
        return
    end
    local rival, live = rivals.shown_of(force_name)

    local now = recorder.elapsed(mine)
    local tags = frame and frame.tags
    -- due[1] is the nearest countdown: at zero that milestone is lost and
    -- the list moves on.
    if not tags or tags.signature ~= signature(mine, rival) or (tags.due[1] and tags.due[1] <= now) then
        build(player, mine, rival, live)
        return
    end
    local list = frame.pane.list
    for i, t in ipairs(tags.due) do
        list["due" .. i].caption = {"mts-gui.shadow-splits-in", chip.fmt(t - now)}
    end
end

function M.close(player)
    frames.close(player, FRAME)
end

--- Show or hide the export box.
function M.toggle_export(player, force_name)
    local frame = player.gui.screen[FRAME]
    if not frame then return end
    if frame.export then
        frame.export.destroy()
        frame.export_hint.destroy()
        return
    end
    local mine = recorder.run_of(force_name)
    if not mine then return end
    local rival, live = rivals.shown_of(force_name)
    add_export(frame, mine, rival, live, true)
end

return M
