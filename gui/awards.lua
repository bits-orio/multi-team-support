-- Multi-Team Support - awards.lua
-- Author: bits-orio
-- License: MIT
--
-- Togglable "Team Awards" window. Shows leaderboards (top 3 by fastest
-- elapsed-since-team-birth) for completed achievements, grouped into three
-- sections: Research, Science, Resources.
--
-- Data sources:
--   storage.tech_records      — keyed by tech_name
--   storage.milestone_records — keyed by "category:item@threshold"
-- Only achievements that at least one team has completed are listed.

local nav     = require("gui.nav")
local helpers = require("scripts.helpers")
local records = require("scripts.records")

local awards_gui = {}

local FIRST_THRESHOLD = 0   -- matches milestones/engine.lua FIRST_THRESHOLD

local CATEGORIES = {"research", "science", "resources"}

local CAT_LABELS = {
    research  = "Research",
    science   = "Science",
    resources = "Resources",
}

-- Milestone categories that belong in the Science tab. Everything else under
-- milestone_records is treated as a Resources achievement.
local SCIENCE_CATEGORIES = { science = true }

-- ---------------------------------------------------------------------------
-- Per-player state
-- ---------------------------------------------------------------------------

local function get_state(player)
    storage.awards_gui_state = storage.awards_gui_state or {}
    local s = storage.awards_gui_state[player.index]
    if not s then
        s = { category = "research" }
        storage.awards_gui_state[player.index] = s
    end
    return s
end

-- ---------------------------------------------------------------------------
-- Data assembly
-- ---------------------------------------------------------------------------

--- Return an array of {label, record} rows for the Research tab.
--- Sorted by first-completion tick (chronological).
local function build_research_rows()
    local rows = {}
    local recs = storage.tech_records or {}
    for tech_name, rec in pairs(recs) do
        if rec.first then
            rows[#rows + 1] = {
                label = helpers.tech_rich_name(tech_name),
                record = rec,
                sort_key = rec.first.tick,
            }
        end
    end
    table.sort(rows, function(a, b) return a.sort_key < b.sort_key end)
    return rows
end

--- Build a human-readable label for a milestone (item + threshold).
local function milestone_label(item_name, threshold)
    local icon = helpers.item_rich_name(item_name)
    if threshold == FIRST_THRESHOLD then
        return "First " .. icon
    end
    return string.format("%d × %s", threshold, icon)
end

--- Return an array of {label, record} rows for either Science or Resources.
--- `want_science` = true selects milestones in SCIENCE_CATEGORIES; false selects
--- everything else.
--- Within the tab, rows are grouped by item (sorted by first-completion tick
--- of the item's earliest milestone), thresholds ascending within each item.
local function build_milestone_rows(want_science)
    local recs = storage.milestone_records or {}

    -- Group: item_key ("category:item") -> list of {threshold, record}
    local groups = {}
    local item_first_tick = {}
    for key, rec in pairs(recs) do
        if rec.first then
            local category, item_name, threshold_str =
                key:match("^([^:]+):(.+)@(%-?%d+)$")
            if category and item_name and threshold_str then
                local is_science = SCIENCE_CATEGORIES[category] == true
                if is_science == want_science then
                    local group_key = category .. ":" .. item_name
                    groups[group_key] = groups[group_key] or {
                        item_name = item_name,
                        entries   = {},
                    }
                    groups[group_key].entries[#groups[group_key].entries + 1] = {
                        threshold = tonumber(threshold_str),
                        record    = rec,
                    }
                    local t = item_first_tick[group_key]
                    if not t or rec.first.tick < t then
                        item_first_tick[group_key] = rec.first.tick
                    end
                end
            end
        end
    end

    -- Sort groups by earliest first.tick, thresholds ascending within a group.
    local sorted_group_keys = {}
    for k in pairs(groups) do sorted_group_keys[#sorted_group_keys + 1] = k end
    table.sort(sorted_group_keys, function(a, b)
        return (item_first_tick[a] or 0) < (item_first_tick[b] or 0)
    end)

    local rows = {}
    for _, gk in ipairs(sorted_group_keys) do
        local grp = groups[gk]
        table.sort(grp.entries, function(a, b) return a.threshold < b.threshold end)
        for _, e in ipairs(grp.entries) do
            rows[#rows + 1] = {
                label  = milestone_label(grp.item_name, e.threshold),
                record = e.record,
            }
        end
    end
    return rows
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

local PLACE_LABELS  = { "1st", "2nd", "3rd" }
local PLACE_COLOURS = {
    {1.00, 0.82, 0.20},  -- gold
    {0.80, 0.80, 0.85},  -- silver
    {0.80, 0.55, 0.30},  -- bronze
}

--- When `show_offline` is false, drop entries from offline teams. Cached so
--- we hit team_has_online_member at most once per team during a render.
local function filter_top(top, show_offline, online_cache)
    if show_offline then return top end
    local out = {}
    for _, e in ipairs(top) do
        local online = online_cache[e.team]
        if online == nil then
            online = helpers.team_has_online_member(e.team)
            online_cache[e.team] = online
        end
        if online then out[#out + 1] = e end
    end
    return out
end

local function render_rows(parent, rows, show_offline)
    if #rows == 0 then
        parent.add{type = "label", caption = "(no records yet)"}
        return
    end

    local tbl = parent.add{
        type                  = "table",
        column_count          = 4,
        draw_horizontal_lines = true,
    }
    tbl.style.horizontal_spacing = 12
    tbl.style.vertical_spacing   = 4

    -- Header row
    local hdr_ach = tbl.add{type = "label", caption = "Achievement"}
    hdr_ach.style.font = "default-bold"
    hdr_ach.style.minimal_width = 100
    for i = 1, 3 do
        local h = tbl.add{type = "label", caption = PLACE_LABELS[i]}
        h.style.font = "default-bold"
        h.style.minimal_width = 200
    end

    local online_cache = {}

    -- Data rows
    for _, row in ipairs(rows) do
        local name_lbl = tbl.add{type = "label", caption = row.label}
        name_lbl.style.minimal_width = 100
        name_lbl.style.single_line = false

        local top = filter_top(records.sorted_entries(row.record), show_offline, online_cache)
        for i = 1, 3 do
            local e = top[i]
            local cell
            if e then
                cell = tbl.add{
                    type    = "label",
                    caption = helpers.team_tag_with_leader(e.team)
                              .. "  "
                              .. helpers.format_elapsed(e.elapsed),
                }
                cell.style.font_color = PLACE_COLOURS[i]
            else
                cell = tbl.add{type = "label", caption = "—"}
            end
            cell.style.minimal_width = 200
            cell.style.single_line = false
        end
    end
end

-- ---------------------------------------------------------------------------
-- GUI construction
-- ---------------------------------------------------------------------------

function awards_gui.build(player)
    local screen = player.gui.screen

    storage.awards_gui_location = storage.awards_gui_location or {}
    local saved_pos
    if screen.sb_awards_frame then
        saved_pos = screen.sb_awards_frame.location
        storage.awards_gui_location[player.index] = saved_pos
        screen.sb_awards_frame.destroy()
    else
        saved_pos = storage.awards_gui_location[player.index]
    end

    local state = get_state(player)

    local frame = screen.add{
        type      = "frame",
        name      = "sb_awards_frame",
        direction = "vertical",
    }
    frame.style.minimal_width = 720
    if saved_pos then frame.location = saved_pos else frame.auto_center = true end

    -- Title bar (draggable)
    local tbar = frame.add{type = "flow", direction = "horizontal"}
    tbar.drag_target = frame
    tbar.style.vertical_align     = "center"
    tbar.style.horizontal_spacing = 8

    local title = tbar.add{type = "label", caption = "Team Awards", style = "frame_title"}
    title.ignored_by_interaction = true

    local spacer = tbar.add{type = "empty-widget", style = "draggable_space_header"}
    spacer.style.horizontally_stretchable = true
    spacer.style.height = 24
    spacer.drag_target  = frame

    tbar.add{
        type    = "sprite-button",
        name    = "sb_awards_close",
        sprite  = "utility/close",
        style   = "frame_action_button",
        tooltip = "Close",
    }

    -- Category tab buttons
    local cat_row = frame.add{type = "flow", direction = "horizontal"}
    cat_row.style.horizontal_spacing = 4
    cat_row.style.top_padding        = 4
    cat_row.style.bottom_padding     = 4

    for _, cat in ipairs(CATEGORIES) do
        local sel = (cat == state.category)
        cat_row.add{
            type    = "button",
            name    = "sb_awards_cat_" .. cat,
            caption = sel and ("> " .. CAT_LABELS[cat]) or CAT_LABELS[cat],
            style   = sel and "green_button" or "button",
        }
    end

    helpers.add_show_offline_checkbox(frame, player)

    -- Scrollable content pane
    local scroll = frame.add{
        type                     = "scroll-pane",
        direction                = "vertical",
        horizontal_scroll_policy = "never",
        vertical_scroll_policy   = "auto",
    }
    scroll.style.maximal_height = 800
    scroll.style.minimal_height = 200
    scroll.style.horizontally_stretchable = true

    local rows
    if state.category == "research" then
        rows = build_research_rows()
    elseif state.category == "science" then
        rows = build_milestone_rows(true)
    else
        rows = build_milestone_rows(false)
    end
    render_rows(scroll, rows, helpers.show_offline(player))
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function awards_gui.toggle(player)
    local screen = player.gui.screen
    if screen.sb_awards_frame then
        screen.sb_awards_frame.destroy()
    else
        awards_gui.build(player)
    end
end

--- Rebuild any open Awards frames. Called after a record changes.
function awards_gui.update_all()
    for _, player in pairs(game.players) do
        if player.connected and player.gui.screen.sb_awards_frame then
            awards_gui.build(player)
        end
    end
end

function awards_gui.on_gui_click(event)
    local el = event.element
    if not (el and el.valid) then return false end
    local name = el.name
    local player = game.get_player(event.player_index)
    if not player then return false end

    if name == "sb_awards_close" then
        local f = player.gui.screen.sb_awards_frame
        if f then f.destroy() end
        return true
    end

    for _, cat in ipairs(CATEGORIES) do
        if name == "sb_awards_cat_" .. cat then
            get_state(player).category = cat
            awards_gui.build(player)
            return true
        end
    end

    return false
end

--- Register the nav bar button for this player. Idempotent.
function awards_gui.on_player_created(player)
    -- Prefer the Quality DLC's "legendary" starburst icon; fall back to the
    -- rocket-silo if the Quality mod is disabled on this save.
    local sprite = (prototypes.quality and prototypes.quality["legendary"])
        and "quality/legendary"
        or  "item/rocket-silo"
    nav.add_top_button(player, {
        name    = "sb_awards_btn",
        sprite  = sprite,
        tooltip = "Team Awards",
    })
end

nav.on_click("sb_awards_btn", function(e)
    awards_gui.toggle(e.player)
end)

return awards_gui
