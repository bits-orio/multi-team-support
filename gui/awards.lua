-- Multi-Team Support - awards.lua
-- Author: bits-orio
-- License: MIT
--
-- Togglable "Team Awards" window. Shows leaderboards (top 3) for completed
-- achievements, grouped into three sections: Research, Science, Resources.
-- A per-player clock toggle ranks either by server time (elapsed since team
-- birth — the official awards basis) or by team online time (how long the team
-- was actually online when they finished — fairer across play schedules).
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
        s = { category = "research", search = "", clock = "server" }
        storage.awards_gui_state[player.index] = s
    end
    s.search = s.search or ""
    s.clock  = s.clock  or "server"
    return s
end

--- The record-entry field this player's clock mode ranks/displays by.
local function clock_field(state)
    return state.clock == "online" and "online_elapsed" or "elapsed"
end

-- ---------------------------------------------------------------------------
-- Data assembly
-- ---------------------------------------------------------------------------

--- Return an array of row tables for the Research tab.
--- Sorted by first-completion tick (chronological).
local function build_research_rows()
    local rows = {}
    local recs = storage.tech_records or {}
    for tech_name, rec in pairs(recs) do
        if rec.first then
            rows[#rows + 1] = {
                kind     = "tech",
                name     = tech_name,
                prefix   = nil,
                record   = rec,
                sort_key = rec.first.tick,
            }
        end
    end
    table.sort(rows, function(a, b) return a.sort_key < b.sort_key end)
    return rows
end

--- Build a human-readable prefix for a milestone (quantity portion only).
local function milestone_prefix(threshold)
    if threshold == FIRST_THRESHOLD then
        return "First"
    end
    return string.format("%d ×", threshold)
end

--- Return an array of row tables for either Science or Resources.
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
                kind   = "item",
                name   = grp.item_name,
                prefix = milestone_prefix(e.threshold),
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

local ICON_BUTTON_SIZE = 24

--- True when `query` is empty or `name` contains query (case-insensitive).
--- `query` is expected to already be lowercased.
local function row_matches(name, query)
    if not query or query == "" then return true end
    return string.find(string.lower(name), query, 1, true) ~= nil
end

--- Resolve the prototype + sprite path + localised name for a row.
--- Returns nil for the prototype if it no longer exists (modded item removed
--- mid-game); the caller falls back to a text-only cell in that case.
local function resolve_row_proto(row)
    if row.kind == "tech" then
        local proto = prototypes.technology and prototypes.technology[row.name]
        if not proto then return nil end
        return proto, "technology/" .. row.name, proto.localised_name
    else
        local proto = prototypes.item and prototypes.item[row.name]
        if not proto then return nil end
        return proto, "item/" .. row.name, proto.localised_name
    end
end

--- Drop rows whose internal name doesn't contain the (already lowercased) query.
--- When the query is empty the input array is returned unchanged.
local function filter_rows(rows, lower_query)
    if not lower_query or lower_query == "" then return rows end
    local out = {}
    for _, row in ipairs(rows) do
        if row_matches(row.name, lower_query) then
            out[#out + 1] = row
        end
    end
    return out
end

local function render_rows(parent, rows, query, sort_field)
    local has_query = query and query ~= ""
    local online    = sort_field == "online_elapsed"

    if #rows == 0 then
        if has_query then
            local row = parent.add{type = "flow", direction = "horizontal"}
            row.style.vertical_align = "center"
            row.style.horizontal_spacing = 6
            row.add{
                type    = "label",
                caption = "No achievements match \"" .. query .. "\".",
            }
            row.add{
                type    = "button",
                name    = "sb_awards_clear_search_inline",
                caption = "Clear search",
                style   = "button",
            }
        else
            parent.add{type = "label", caption = "(no records yet)"}
        end
        return
    end

    local tbl = parent.add{
        type                  = "table",
        column_count          = 4,
        draw_horizontal_lines = true,
    }
    tbl.style.horizontal_spacing = 12
    tbl.style.vertical_spacing   = 2

    -- Header row
    local hdr_ach = tbl.add{type = "label", caption = "Achievement"}
    hdr_ach.style.font = "default-bold"
    hdr_ach.style.minimal_width = 100
    for i = 1, 3 do
        local h = tbl.add{type = "label", caption = PLACE_LABELS[i]}
        h.style.font = "default-bold"
        h.style.minimal_width = 200
    end

    for _, row in ipairs(rows) do
        local cell1 = tbl.add{type = "flow", direction = "horizontal"}
        cell1.style.vertical_align = "center"
        cell1.style.horizontal_spacing = 4
        cell1.style.minimal_width = 100

        local proto, sprite, loc_name = resolve_row_proto(row)
        if proto then
            local tags
            if row.kind == "tech" then
                tags = { sb_awards_open_tech = row.name }
            else
                tags = { sb_awards_open_item = row.name }
            end
            local btn = cell1.add{
                type    = "sprite-button",
                sprite  = sprite,
                tooltip = loc_name,
                tags    = tags,
                style   = "slot_button",
            }
            btn.style.size    = ICON_BUTTON_SIZE
            btn.style.padding = 0
        else
            -- Prototype gone (mod removed): show plain text so the record is still listed.
            cell1.add{type = "label", caption = row.name}
        end

        if row.prefix then
            cell1.add{type = "label", caption = row.prefix}
        end

        local top = records.sorted_entries(row.record, sort_field)
        for i = 1, 3 do
            local e = top[i]
            local cell
            if e then
                local value    = online and e.online_elapsed or e.elapsed
                local time_str = value and helpers.format_elapsed(value) or "—"
                cell = tbl.add{
                    type    = "label",
                    caption = helpers.team_tag_with_leader(e.team)
                              .. "  "
                              .. time_str,
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

local function get_rows_for_state(state)
    if state.category == "research" then
        return build_research_rows()
    elseif state.category == "science" then
        return build_milestone_rows(true)
    else
        return build_milestone_rows(false)
    end
end

--- Refresh the parts of the GUI that change as the search query changes:
--- the match-count badge, the clear (×) button visibility, and the filtered
--- scroll content. Preserves the textfield (and its keyboard focus / caret
--- position) during search typing.
local function refresh_content(player)
    local frame = player.gui.screen.sb_awards_frame
    if not frame then return end
    local scroll = frame.sb_awards_scroll
    if not scroll then return end

    local state = get_state(player)
    local query = state.search or ""
    local has_query = query ~= ""
    local lower_query = has_query and string.lower(query) or nil

    local all_rows = get_rows_for_state(state)
    local visible_rows = filter_rows(all_rows, lower_query)

    local cat_row = frame.sb_awards_cat_row
    if cat_row then
        local count_lbl = cat_row.sb_awards_match_count
        if count_lbl then
            if has_query then
                count_lbl.caption = string.format("%d / %d match",
                    #visible_rows, #all_rows)
                count_lbl.visible = true
            else
                count_lbl.visible = false
            end
        end
        local clear_btn = cat_row.sb_awards_clear_search
        if clear_btn then clear_btn.visible = has_query end
    end

    scroll.clear()
    render_rows(scroll, visible_rows, query, clock_field(state))
end

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

    -- Category tab buttons + search field on the same row
    local cat_row = frame.add{
        type      = "flow",
        name      = "sb_awards_cat_row",
        direction = "horizontal",
    }
    cat_row.style.horizontal_spacing = 4
    cat_row.style.top_padding        = 4
    cat_row.style.bottom_padding     = 4
    cat_row.style.vertical_align     = "center"

    for _, cat in ipairs(CATEGORIES) do
        local sel = (cat == state.category)
        cat_row.add{
            type    = "button",
            name    = "sb_awards_cat_" .. cat,
            caption = sel and ("> " .. CAT_LABELS[cat]) or CAT_LABELS[cat],
            style   = sel and "green_button" or "button",
        }
    end

    -- Clock basis as a slider switch (visually distinct from the category buttons,
    -- which it used to blend into when both were "green_button").
    local clock_label = cat_row.add{type = "label", caption = "Rank by:"}
    clock_label.tooltip = "Which clock ranks the finishers. Server time is the official"
        .. " awards basis; Online time is fairer across different play schedules."
    cat_row.add{
        type               = "switch",
        name               = "sb_awards_clock_switch",
        switch_state       = state.clock == "online" and "right" or "left",
        left_label_caption  = "Server",
        right_label_caption = "Online",
        left_label_tooltip  = "Elapsed since each team started, the official awards basis.",
        right_label_tooltip = "How long each team was actually online.",
    }

    local search_spacer = cat_row.add{type = "empty-widget"}
    search_spacer.style.horizontally_stretchable = true

    local query = state.search or ""
    local has_query = query ~= ""
    local all_rows = get_rows_for_state(state)
    local visible_rows = filter_rows(all_rows, has_query and string.lower(query) or nil)

    local count_lbl = cat_row.add{
        type    = "label",
        name    = "sb_awards_match_count",
        caption = has_query
            and string.format("%d / %d match", #visible_rows, #all_rows)
            or  "",
    }
    count_lbl.visible = has_query
    count_lbl.style.font_color = {0.85, 0.85, 0.5}

    cat_row.add{type = "label", caption = "Search:"}
    local search_field = cat_row.add{
        type    = "textfield",
        name    = "sb_awards_search",
        text    = query,
        tooltip = "Filter rows whose internal name contains this text. Case-insensitive (e.g. \"miner\", \"science\").",
    }
    search_field.style.width = 180

    local clear_btn = cat_row.add{
        type    = "sprite-button",
        name    = "sb_awards_clear_search",
        sprite  = "utility/close",
        style   = "tool_button",
        tooltip = "Clear search",
    }
    clear_btn.visible = has_query

    -- Scrollable content pane
    local scroll = frame.add{
        type                     = "scroll-pane",
        name                     = "sb_awards_scroll",
        direction                = "vertical",
        horizontal_scroll_policy = "never",
        vertical_scroll_policy   = "auto",
    }
    scroll.style.maximal_height = 800
    scroll.style.minimal_height = 200
    scroll.style.horizontally_stretchable = true

    render_rows(scroll, visible_rows, query, clock_field(state))
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

local function clear_search(player)
    local state = get_state(player)
    if state.search == "" then return end
    state.search = ""
    local frame = player.gui.screen.sb_awards_frame
    local field = frame and frame.sb_awards_cat_row
        and frame.sb_awards_cat_row.sb_awards_search
    if field then field.text = "" end
    refresh_content(player)
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

    if name == "sb_awards_clear_search" or name == "sb_awards_clear_search_inline" then
        clear_search(player)
        return true
    end

    for _, cat in ipairs(CATEGORIES) do
        if name == "sb_awards_cat_" .. cat then
            get_state(player).category = cat
            awards_gui.build(player)
            return true
        end
    end

    if el.tags and el.tags.sb_awards_open_tech then
        player.open_technology_gui(el.tags.sb_awards_open_tech)
        return true
    end

    if el.tags and el.tags.sb_awards_open_item then
        local proto = prototypes.item and prototypes.item[el.tags.sb_awards_open_item]
        if proto then player.open_factoriopedia_gui(proto) end
        return true
    end

    return false
end

function awards_gui.on_gui_switch_state_changed(event)
    local el = event.element
    if not (el and el.valid) or el.name ~= "sb_awards_clock_switch" then return false end
    local player = game.get_player(event.player_index)
    if not player then return true end
    get_state(player).clock = (el.switch_state == "right") and "online" or "server"
    awards_gui.build(player)
    return true
end

function awards_gui.on_gui_text_changed(event)
    local el = event.element
    if not (el and el.valid) then return false end
    if el.name ~= "sb_awards_search" then return false end
    local player = game.get_player(event.player_index)
    if not player then return true end
    get_state(player).search = el.text or ""
    refresh_content(player)
    return true
end

--- Register the nav bar button for this player. Idempotent.
function awards_gui.on_player_created(player)
    nav.add_top_button(player, {
        name    = "sb_awards_btn",
        sprite  = "sb-legendary",
        tooltip = "Team Awards",
    })
end

nav.on_click("sb_awards_btn", function(e)
    awards_gui.toggle(e.player)
end)

return awards_gui
