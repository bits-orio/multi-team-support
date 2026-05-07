-- gui/stats.lua
-- Production stats GUI: panel building, click handlers, nav.

local nav        = require("gui.nav")
local helpers    = require("scripts.helpers")
local stats_data = require("gui.stats_data")

local stats_gui = {}

-- Re-export data API so mod-compat callers keep the same require path.
stats_gui.set_intermediates       = stats_data.set_intermediates
stats_gui.set_custom              = stats_data.set_custom
stats_gui.invalidate_categories   = stats_data.invalidate_categories
stats_gui.get_category_item_names = stats_data.get_category_item_names

local MAX_COLS     = stats_data.MAX_COLS
local ALLTIME      = stats_data.ALLTIME
local TIME_PERIODS = stats_data.TIME_PERIODS
local CATEGORIES   = stats_data.CATEGORIES
local CAT_LABELS   = stats_data.CAT_LABELS

-- ─── GUI Construction ──────────────────────────────────────────────────

function stats_gui.build_stats_gui(player, leaving_index)
    local screen = player.gui.screen

    if not storage.stats_gui_location then storage.stats_gui_location = {} end
    local saved_pos
    if screen.sb_stats_frame then
        saved_pos = screen.sb_stats_frame.location
        storage.stats_gui_location[player.index] = saved_pos
        screen.sb_stats_frame.destroy()
    else
        saved_pos = storage.stats_gui_location[player.index]
    end

    local state      = stats_data.get_state(player)
    local item_names = stats_data.get_category_item_names(player.index, state.category)
    local all_pf     = stats_data.player_forces(leaving_index)
    local show_offline = helpers.show_offline(player)
    local my_name    = helpers.display_name(player.force.name)
    local pf = {}
    for _, entry in ipairs(all_pf) do
        if entry.online or entry.player_name == my_name or show_offline then
            pf[#pf + 1] = entry
        end
    end

    local frame = screen.add{type = "frame", name = "sb_stats_frame", direction = "vertical"}
    frame.style.minimal_width = 320
    if saved_pos then frame.location = saved_pos else frame.auto_center = true end

    -- Title bar
    local tbar = frame.add{type = "flow", name = "sb_stats_titlebar", direction = "horizontal"}
    tbar.drag_target = frame
    tbar.style.vertical_align     = "center"
    tbar.style.horizontal_spacing = 8
    local title = tbar.add{type = "label", caption = "Production Stats", style = "frame_title"}
    title.ignored_by_interaction = true
    local spacer = tbar.add{type = "empty-widget", style = "draggable_space_header"}
    spacer.style.horizontally_stretchable = true
    spacer.style.height = 24
    spacer.drag_target  = frame
    tbar.add{type = "sprite-button", name = "sb_stats_close",
        sprite = "utility/close", style = "frame_action_button", tooltip = "Close"}

    -- Category tabs
    local cat_row = frame.add{type = "flow", name = "sb_stats_cats", direction = "horizontal"}
    cat_row.style.horizontal_spacing = 4
    cat_row.style.top_padding        = 4
    for _, cat in ipairs(CATEGORIES) do
        local sel = (cat == state.category)
        cat_row.add{
            type    = "button",
            name    = "sb_stats_cat_" .. cat,
            caption = sel and ("> " .. CAT_LABELS[cat]) or CAT_LABELS[cat],
            style   = sel and "green_button" or "button",
        }
    end

    -- Time period tabs
    local time_row = frame.add{type = "flow", name = "sb_stats_times", direction = "horizontal"}
    time_row.style.horizontal_spacing = 4
    time_row.style.bottom_padding     = 4
    for _, tp in ipairs(TIME_PERIODS) do
        local sel = (tp.precision == state.precision)
        time_row.add{
            type    = "button",
            name    = "sb_stats_time_" .. tp.key,
            caption = sel and ("> " .. tp.label) or tp.label,
            style   = sel and "green_button" or "button",
        }
    end

    helpers.add_show_offline_checkbox(frame, player)

    local scroll = frame.add{
        type = "scroll-pane", name = "sb_stats_scroll", direction = "vertical",
        horizontal_scroll_policy = "auto", vertical_scroll_policy = "auto",
    }
    scroll.style.maximal_height = 500
    scroll.style.maximal_width  = 900

    if #pf == 0 then
        scroll.add{type = "label", caption = "(no players yet)"}
        return
    end

    local tbl = scroll.add{
        type = "table", name = "sb_stats_table",
        column_count = MAX_COLS + 1, draw_horizontal_lines = true,
    }
    tbl.style.horizontal_spacing = 4
    tbl.style.vertical_spacing   = 2

    -- Header row: blank corner + MAX_COLS choose-elem-buttons
    tbl.add{type = "label", caption = ""}
    for col_idx = 1, MAX_COLS do
        local item_name = item_names[col_idx]
        local btn = tbl.add{
            type      = "choose-elem-button",
            name      = "sb_stats_item_" .. col_idx,
            elem_type = "item",
            style     = "slot_button",
            tags      = {sb_stats_col = col_idx, sb_stats_cat = state.category},
            tooltip   = item_name and "Click to change this column"
                                   or "Click to add an item to this column",
        }
        if item_name then btn.elem_value = item_name end
    end

    -- Sort button row
    local sort_col  = state.sort_col
    local sort_dir  = state.sort_dir or "desc"
    local sort_cell = tbl.add{type = "flow", direction = "horizontal"}
    sort_cell.style.horizontally_stretchable = true
    local sc_spacer = sort_cell.add{type = "empty-widget"}
    sc_spacer.style.horizontally_stretchable = true
    local sort_lbl = sort_cell.add{type = "label", caption = "sort →"}
    sort_lbl.style.font       = "default-small"
    sort_lbl.style.font_color = {0.6, 0.6, 0.6}
    for col_idx = 1, MAX_COLS do
        local item_name = item_names[col_idx]
        if item_name then
            local active  = sort_col == col_idx
            local caption = active and (sort_dir == "desc" and "▼" or "▲") or "·"
            local btn = tbl.add{
                type    = "button",
                caption = caption,
                style   = active and "green_button" or "button",
                tags    = {sb_stats_sort = col_idx},
                tooltip = active
                    and (sort_dir == "desc" and "Sorted high→low (click for low→high)"
                                            or "Sorted low→high (click to clear sort)")
                    or  "Sort by this column (high→low)",
            }
            btn.style.width   = 36
            btn.style.height  = 20
            btn.style.padding = 0
        else
            tbl.add{type = "label", caption = ""}
        end
    end

    -- Pre-compute counts, then optionally sort rows
    local row_counts = {}
    for i, entry in ipairs(pf) do
        row_counts[i] = {}
        for col_idx = 1, MAX_COLS do
            local item_name = item_names[col_idx]
            if item_name then
                row_counts[i][col_idx] = stats_data.get_count(entry.force, item_name, state.precision)
            end
        end
    end

    if sort_col then
        local pairs_list = {}
        for i = 1, #pf do pairs_list[i] = {entry = pf[i], cnts = row_counts[i]} end
        table.sort(pairs_list, function(a, b)
            local ca = a.cnts[sort_col] or 0
            local cb = b.cnts[sort_col] or 0
            if ca ~= cb then
                return sort_dir == "desc" and ca > cb or ca < cb
            end
            return a.entry.player_name < b.entry.player_name
        end)
        pf, row_counts = {}, {}
        for i, p in ipairs(pairs_list) do pf[i] = p.entry; row_counts[i] = p.cnts end
    end

    -- Data rows
    for i, entry in ipairs(pf) do
        local name_cell = tbl.add{type = "flow", direction = "horizontal"}
        name_cell.style.vertical_align = "center"
        name_cell.style.minimal_width  = 160
        local name_lbl = name_cell.add{type = "label", caption = entry.caption}
        name_lbl.style.font = "default-bold"
        if not entry.online then
            name_lbl.style.font_color = {0.65, 0.65, 0.65}
            local off_lbl = name_cell.add{type = "label", caption = " (offline)"}
            off_lbl.style.font       = "default-small"
            off_lbl.style.font_color = {0.45, 0.45, 0.45}
        end
        for col_idx = 1, MAX_COLS do
            local count = row_counts[i][col_idx]
            if count then
                local cell = tbl.add{type = "label", caption = stats_data.fmt(count)}
                cell.style.minimal_width    = 38
                cell.style.horizontal_align = "right"
            else
                tbl.add{type = "label", caption = ""}
            end
        end
    end
end

-- ─── Public API ────────────────────────────────────────────────────────

function stats_gui.toggle(player)
    local screen = player.gui.screen
    if screen.sb_stats_frame then
        screen.sb_stats_frame.destroy()
    else
        stats_gui.build_stats_gui(player)
    end
end

function stats_gui.on_gui_click(event)
    local el = event.element
    if not el or not el.valid then return false end
    local name   = el.name
    local player = game.get_player(event.player_index)
    if not player then return false end

    if name == "sb_stats_close" then
        local f = player.gui.screen.sb_stats_frame
        if f then f.destroy() end
        return true
    end

    for _, cat in ipairs(CATEGORIES) do
        if name == "sb_stats_cat_" .. cat then
            stats_data.get_state(player).category = cat
            stats_gui.build_stats_gui(player)
            return true
        end
    end

    for _, tp in ipairs(TIME_PERIODS) do
        if name == "sb_stats_time_" .. tp.key then
            stats_data.get_state(player).precision = tp.precision
            stats_gui.build_stats_gui(player)
            return true
        end
    end

    if el.tags and el.tags.sb_stats_sort then
        local col   = el.tags.sb_stats_sort
        local state = stats_data.get_state(player)
        if state.sort_col == col then
            if state.sort_dir == "desc" then
                state.sort_dir = "asc"
            else
                state.sort_col = nil
                state.sort_dir = "desc"
            end
        else
            state.sort_col = col
            state.sort_dir = "desc"
        end
        stats_gui.build_stats_gui(player)
        return true
    end

    return false
end

function stats_gui.on_gui_elem_changed(event)
    local el = event.element
    if not el or not el.valid then return false end
    if not (el.tags and el.tags.sb_stats_col) then return false end
    local player = game.get_player(event.player_index)
    if not player then return false end

    local new_item = el.elem_value
    local col_idx  = el.tags.sb_stats_col
    local cat      = el.tags.sb_stats_cat

    if not storage.stats_category_items then storage.stats_category_items = {} end
    if not storage.stats_category_items[player.index] then
        storage.stats_category_items[player.index] = {}
    end
    if not storage.stats_category_items[player.index][cat] then
        storage.stats_category_items[player.index][cat] =
            stats_data.get_category_item_names(player.index, cat)
    end
    storage.stats_category_items[player.index][cat][col_idx] = new_item
    stats_gui.build_stats_gui(player)
    return true
end

function stats_gui.on_player_created(player)
    nav.add_top_button(player, {
        name    = "sb_stats_btn",
        sprite  = "item/production-science-pack",
        tooltip = "Production Stats",
    })
end

nav.on_click("sb_stats_btn", function(e) stats_gui.toggle(e.player) end)

return stats_gui
