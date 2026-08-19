-- gui/stats/handlers.lua
-- Click / elem-changed routing for the production stats GUI.

local columns = require("gui.stats.columns")
local counts  = require("gui.stats.counts")
local panel   = require("gui.stats.panel")

local M = {}

local TIME_PERIODS = counts.TIME_PERIODS
local CATEGORIES   = columns.CATEGORIES

function M.on_gui_click(event)
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
            columns.get_state(player).category = cat
            panel.build_stats_gui(player)
            return true
        end
    end

    for _, tp in ipairs(TIME_PERIODS) do
        if name == "sb_stats_time_" .. tp.key then
            columns.get_state(player).precision = tp.precision
            panel.build_stats_gui(player)
            return true
        end
    end

    -- Quality view buttons. "merged" is checked first, so a quality
    -- prototype literally named "merged" would be shadowed -- acceptable.
    if name == "sb_stats_qual_merged" then
        columns.get_state(player).quality = "merged"
        panel.build_stats_gui(player)
        return true
    end
    local qname = name:match("^sb_stats_qual_(.+)$")
    if qname and prototypes.quality[qname] then
        columns.get_state(player).quality = qname
        panel.build_stats_gui(player)
        return true
    end

    if el.tags and el.tags.sb_stats_sort then
        local col   = el.tags.sb_stats_sort
        local state = columns.get_state(player)
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
        panel.build_stats_gui(player)
        return true
    end

    return false
end

function M.on_gui_elem_changed(event)
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
            columns.get_columns(player.index, cat)
    end
    -- elem_type "item" yields a name string (or nil on clear); store the
    -- column-record shape. Legacy string entries in older saves are
    -- coerced on read by columns.as_column.
    storage.stats_category_items[player.index][cat][col_idx] =
        new_item and {kind = "item", name = new_item} or nil
    panel.build_stats_gui(player)
    return true
end

return M
