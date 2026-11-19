-- Multi-Team Support - shadow_race/gui/picker.lua
-- Author: bits-orio
-- License: MIT
--
-- The Shadow Race window: the standings (every run the team could chase,
-- ranked against the team right now), the team's place among them, its
-- pace against its shadow, and the icon buttons that choose a shadow, pin
-- a run, and open the splits window. Kept small: one line per run, the
-- window's own switches on its title bar. Opened from the button in the team clock
-- chip (shadow_race/gui/chip.lua).
--
-- Every button carries tags.mts_shadow = the action; on_gui_click below is
-- the one handler for this window and the splits window.

local rivals    = require("shadow_race.rivals")
local standings = require("shadow_race.standings")
local compare   = require("shadow_race.compare")
local recorder  = require("shadow_race.recorder")
local announcer = require("shadow_race.announcer")
local splits    = require("shadow_race.gui.splits")
local chip      = require("shadow_race.gui.chip")
local frames    = require("shadow_race.gui.frames")
local nav       = require("gui.nav")
local helpers   = require("scripts.helpers")

local M = {}

local FRAME   = "mts_shadow_picker"
local COLUMNS = 4   -- chase, run, split, pin
local PACE_WINDOWS = { 10 * 3600, 60 * 3600 }   -- ten minutes and an hour

--- "12.4", or a dash for a run with no data over that stretch.
local function pace_number(value)
    if not value then return "-" end
    return string.format("%.1f", value)
end

--- The pace line: science per minute over ten minutes and an hour, the
--- team's and its shadow's. nil when the team is chasing nothing.
local function pace_caption(force_name)
    local mine = recorder.run_of(force_name)
    local rival, live = rivals.rival_of(force_name)
    if not (mine and rival) then return nil end
    local numbers = {}
    for i, window in ipairs(PACE_WINDOWS) do
        local my_pace, their_pace = compare.pace(mine, rival, live, window)
        numbers[i * 2 - 1], numbers[i * 2] = pace_number(my_pace), pace_number(their_pace)
    end
    return {"mts-gui.shadow-pace", numbers[1], numbers[2], numbers[3], numbers[4]}
end

--- The chase button of a row: pressed in for the team's shadow, where a
--- click stops the chase.
local function add_chase_button(tbl, row)
    if row.current then
        return frames.icon(tbl, "utility/play", "stop", {"mts-tip.shadow-stop"}, true)
    end
    return frames.icon(tbl, "utility/play", "chase", {"mts-tip.shadow-chase"}, false, {choice = row.choice})
end

--- One row, one line: the chase button, the run, its split, and the pin
--- button for the player's own recent runs. A recorded run's chase icon is
--- a ghost, a team that is playing now has a solid one.
local function add_row(tbl, row)
    local chase = add_chase_button(tbl, row)
    if row.recorded then frames.ghost(chase) end
    local name = tbl.add{type = "label", caption = row.label}
    name.style.minimal_width = 150
    if row.own then name.style.font = "default-semibold" end
    tbl.add{type = "label", caption = chip.split_caption(row.gap, row.final)}.style.minimal_width = 90

    if row.pinned then
        frames.icon(tbl, "utility/track_button_white", "unpin", {"mts-tip.shadow-unpin"}, true)
    elseif row.pinnable then
        frames.icon(tbl, "utility/track_button_white", "pin", {"mts-tip.shadow-pin"}, false, {run_id = row.run_id})
    else
        tbl.add{type = "empty-widget"}
    end
end

--- The auto-chase row, first in the table.
local function add_auto_row(tbl, auto)
    if auto then
        frames.icon(tbl, "utility/play", "stop", {"mts-tip.shadow-stop"}, true)
    else
        frames.icon(tbl, "utility/play", "chase", {"mts-tip.shadow-auto"}, false, {choice = {kind = "auto"}})
    end
    tbl.add{type = "label", caption = {"mts-gui.shadow-auto"}, tooltip = {"mts-tip.shadow-auto"}}
    tbl.add{type = "empty-widget"}
    tbl.add{type = "empty-widget"}
end

--- The icons on the title bar: the splits window, and the player's own
--- display switch.
local function bar_icons(bar, player)
    frames.icon(bar, "utility/list_view", "splits", {"mts-tip.shadow-splits"},
        rivals.wants_splits(player.index))
    if rivals.individual_hud() then
        frames.icon(bar, "utility/show_tags_in_map_view", "hide", {"mts-tip.shadow-hide"},
            not rivals.is_hidden(player.index))
    end
    frames.finish_bar(bar, "close")
end

--- What the list looks like apart from its numbers: which runs, in what
--- order, and which buttons. While this is unchanged the one-second pass
--- only rewrites captions.
local function signature(rows, force_name, player)
    local parts = { rivals.is_auto(force_name) and "auto" or "pick",
                    rivals.wants_splits(player.index) and "s" or "-",
                    rivals.is_hidden(player.index) and "h" or "-" }
    for _, row in ipairs(rows) do
        parts[#parts + 1] = (row.run_id and ("r" .. row.run_id) or row.choice.force)
            .. (row.current and "c" or "") .. (row.pinned and "p" or "") .. (row.pinnable and "n" or "")
    end
    return table.concat(parts, " ")
end

function M.close(player)
    frames.close(player, FRAME)
end

--- Build the window, replacing an open one in place.
function M.open(player)
    local force_name = frames.team_of(player)
    local old = player.gui.screen[FRAME]
    local location = old and old.location
    if old then old.destroy() end
    if not (force_name and rivals.enabled()) then return end

    local frame, bar = frames.titled(player, FRAME, {"mts-gui.shadow-title"}, location or {x = 5, y = 88})
    local rows, place, total = standings.rows(force_name, player.index)
    frame.tags = { signature = signature(rows, force_name, player) }
    -- The team's place sits on the bar, between the title and the icons.
    bar.add{type = "label", name = "place", caption = {"mts-gui.shadow-place", place, total},
        index = 2}.ignored_by_interaction = true
    bar_icons(bar, player)

    local pace_text = pace_caption(force_name)
    local pace = frame.add{type = "label", name = "pace", caption = pace_text or "",
        tooltip = {"mts-tip.shadow-pace"}}
    pace.style.font = "default-small"
    pace.visible = pace_text ~= nil

    local pane = frame.add{type = "scroll-pane", name = "pane"}
    pane.style.maximal_height = 300
    local tbl = pane.add{type = "table", name = "rows", column_count = COLUMNS}
    tbl.style.horizontal_spacing = 6
    tbl.style.vertical_spacing = 0
    tbl.style.vertical_align = "center"
    add_auto_row(tbl, rivals.is_auto(force_name))
    for _, row in ipairs(rows) do add_row(tbl, row) end
    if #rows == 0 then
        local empty = frame.add{type = "label", caption = {"mts-gui.shadow-empty"}}
        empty.style.single_line = false
        empty.style.maximal_width = 300
    end
end

function M.toggle(player)
    if player.gui.screen[FRAME] then M.close(player) else M.open(player) end
end

--- Rebuild every open window: a teammate's choice changes what "your
--- shadow" is, and a flag changes which buttons exist.
function M.refresh_all()
    for _, player in pairs(game.connected_players) do
        if player.gui.screen[FRAME] then M.open(player) end
    end
end

-- An open window is refreshed every this many seconds. The split to the
-- second is on the team clock chip; ranking against the whole archive for
-- every open window every second is not worth its cost (2.6 ms against 400
-- runs on the rig).
local REFRESH_SECONDS = 5

--- The one-second pass: move the numbers of the open windows whose turn
--- it is, a different fifth of the players each second. Captions are
--- written in place, so a button under the mouse is never rebuilt
--- mid-click; a list whose runs or order changed is rebuilt.
function M.tick()
    local second = math.floor(game.tick / 60)
    for _, player in pairs(game.connected_players) do
        local frame = player.gui.screen[FRAME]
        local force_name = frames.team_of(player)
        local racing = force_name and rivals.enabled()
        if frame and not racing then
            frame.destroy()
        elseif frame and (second + player.index) % REFRESH_SECONDS == 0 then
            local rows, place, total = standings.rows(force_name, player.index)
            if frame.tags.signature ~= signature(rows, force_name, player) then
                M.open(player)
            else
                frame.bar.place.caption = {"mts-gui.shadow-place", place, total}
                local pace_text = pace_caption(force_name)
                frame.pace.caption = pace_text or ""
                frame.pace.visible = pace_text ~= nil
                -- Row 1 of the table is auto-chase; the runs start at row 2.
                local cells = frame.pane.rows.children
                for i, row in ipairs(rows) do
                    cells[i * COLUMNS + 3].caption = chip.split_caption(row.gap, row.final)
                end
            end
        end
    end
end

-- ─── Clicks ───────────────────────────────────────────────────────────

local function name_of(player)
    return helpers.colored_name(player.name, player.chat_color)
end

local ACTIONS = {}

function ACTIONS.close(player) M.close(player) end

function ACTIONS.chase(player, force_name, tags)
    if not rivals.set(force_name, tags.choice) then return end
    local team = helpers.team_tag(force_name)
    if tags.choice.kind == "auto" then
        standings.retarget(force_name)
        rivals.tell(force_name, {"mts-chat.shadow-set-auto", name_of(player), team}, true)
    else
        local run, live = rivals.rival_of(force_name)
        rivals.tell(force_name, {"mts-chat.shadow-set", name_of(player), team, rivals.label(run, live)}, true)
    end
    announcer.reset(force_name)
end

function ACTIONS.stop(player, force_name)
    rivals.clear(force_name)
    rivals.tell(force_name, {"mts-chat.shadow-stopped", name_of(player), helpers.team_tag(force_name)}, true)
end

function ACTIONS.pin(player, _, tags) rivals.pin(player.index, tags.run_id) end
function ACTIONS.unpin(player) rivals.unpin(player.index) end

function ACTIONS.splits(player)
    rivals.set_splits(player.index, not rivals.wants_splits(player.index))
end

function ACTIONS.splits_close(player) rivals.set_splits(player.index, false) end
function ACTIONS.export(player, force_name) splits.toggle_export(player, force_name) end

function ACTIONS.hide(player)
    rivals.set_hidden(player.index, not rivals.is_hidden(player.index))
end

-- Actions that change nothing a top bar or another window shows.
local QUIET = { close = true, export = true }

--- on_gui_click. `refresh` repaints the top bar of everyone the click may
--- have changed. Returns true when the click was one of Shadow Race's.
function M.on_gui_click(event, refresh)
    local tags = event.element.tags
    local name = tags and tags.mts_shadow
    local action = name and ACTIONS[name]
    if not action then return false end
    local player = game.get_player(event.player_index)
    if not player then return true end
    local force_name = frames.team_of(player)
    if not (force_name and rivals.enabled()) then
        M.close(player)
        splits.close(player)
        return true
    end
    action(player, force_name, tags)
    if not QUIET[name] then
        refresh()
        M.refresh_all()
    end
    return true
end

nav.on_click(chip.BUTTON, function(event) M.toggle(event.player) end)

return M
