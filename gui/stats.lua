-- Multi-Team Support - stats_gui.lua
-- Author: bits-orio
-- License: MIT
--
-- Nav bar integration: each player gets a production-science-pack sprite-button
-- in the top-left mod_gui strip that toggles this window.
--
-- Per-player production statistics window.
-- Categories are built from prototypes (overhaul-safe). Intermediates and
-- the Custom category use curated/hardcoded lists overridable via
-- stats_gui.set_intermediates() / stats_gui.set_custom() for mod-compat code.
-- Every column header is a choose-elem-button; always MAX_COLS slots are
-- shown so players can fill blank ones to add items.

local nav = require("gui.nav")
local helpers = require("helpers")

local stats_gui = {}

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

-- Maximum number of item columns shown in every category.
local MAX_COLS = 12

-- Sentinel stored in state.precision to indicate "all time" mode.
local ALLTIME = "alltime"

local TIME_PERIODS = {
    {key = "1min",    label = "1m",  precision = defines.flow_precision_index.one_minute},
    {key = "10min",   label = "10m", precision = defines.flow_precision_index.ten_minutes},
    {key = "1hr",     label = "1h",  precision = defines.flow_precision_index.one_hour},
    {key = "10hr",    label = "10h", precision = defines.flow_precision_index.ten_hours},
    {key = "alltime", label = "All", precision = ALLTIME},
}

local CATEGORIES = {"ores", "plates", "intermediates", "science", "custom"}

local CAT_LABELS = {
    ores          = "Ores",
    plates        = "Plates",
    intermediates = "Intermediates",
    science       = "Science",
    custom        = "Custom",
}

-- Curated intermediates list for vanilla Factorio 2.0 base game.
-- Items absent from the current prototype set are silently skipped.
local DEFAULT_INTERMEDIATES = {
    "iron-gear-wheel",
    "copper-cable",
    "electronic-circuit",
    "advanced-circuit",
    "processing-unit",
    "pipe",
    "engine-unit",
    "electric-engine-unit",
    "flying-robot-frame",
    "battery",
    "low-density-structure",
    "rocket-fuel",
    "rocket-control-unit",
}

-- Default items for the user-configurable Custom category.
local DEFAULT_CUSTOM = {
    "iron-plate",
    "steel-plate",
}

-- ---------------------------------------------------------------------------
-- Module-level state (rebuilt each script load, never serialised)
-- ---------------------------------------------------------------------------

local proto_cache            = nil   -- auto-detected ores / plates / science
local intermediates_override = nil   -- set by mod-compat via stats_gui.set_intermediates
local custom_override        = nil   -- set by mod-compat via stats_gui.set_custom

-- ---------------------------------------------------------------------------
-- Prototype-derived category discovery
-- ---------------------------------------------------------------------------

local function build_proto_cache()
    if proto_cache then return proto_cache end

    local ore_set     = {}
    local science_set = {}

    for _, entity in pairs(prototypes.entity) do
        if entity.type == "resource" and entity.mineable_properties then
            for _, product in pairs(entity.mineable_properties.products or {}) do
                if product.type == "item" then
                    ore_set[product.name] = true
                end
            end
        end
    end

    for _, entity in pairs(prototypes.entity) do
        if entity.type == "lab" then
            for _, input in pairs(entity.lab_inputs or {}) do
                science_set[input] = true
            end
        end
    end

    local plate_set = {}
    for _, recipe in pairs(prototypes.recipe) do
        if recipe.category == "smelting" then
            for _, product in pairs(recipe.products or {}) do
                if product.type == "item" and not ore_set[product.name] then
                    plate_set[product.name] = true
                end
            end
        end
    end

    local function sorted(set)
        local list = {}
        for item_name in pairs(set) do
            local proto = prototypes.item[item_name]
            if proto then
                local g = (proto.group and proto.group.order) or ""
                list[#list + 1] = {name = item_name, order = g .. proto.order}
            end
        end
        table.sort(list, function(a, b) return a.order < b.order end)
        return list
    end

    proto_cache = {
        ores    = sorted(ore_set),
        plates  = sorted(plate_set),
        science = sorted(science_set),
    }
    return proto_cache
end

function stats_gui.invalidate_categories()
    proto_cache = nil
    storage.stats_categories = nil   -- clean up any old storage key
end

-- ---------------------------------------------------------------------------
-- Override API (call from mod-compat modules at startup)
-- ---------------------------------------------------------------------------

function stats_gui.set_intermediates(items)
    intermediates_override = items
end

function stats_gui.set_custom(items)
    custom_override = items
end

-- ---------------------------------------------------------------------------
-- Item list resolution
-- ---------------------------------------------------------------------------

-- Returns the default dense item-name array for a category (no storage override).
local function default_item_names(cat)
    if cat == "intermediates" then
        local src = intermediates_override or DEFAULT_INTERMEDIATES
        local out = {}
        for _, name in ipairs(src) do
            if prototypes.item[name] then out[#out + 1] = name end
        end
        return out
    elseif cat == "custom" then
        local src = custom_override or DEFAULT_CUSTOM
        local out = {}
        for _, name in ipairs(src) do
            if prototypes.item[name] then out[#out + 1] = name end
        end
        return out
    else
        local cache = build_proto_cache()
        local items = cache[cat] or {}
        local out = {}
        for _, item in ipairs(items) do out[#out + 1] = item.name end
        return out
    end
end

-- Returns a positional table [1..MAX_COLS] where nil means "empty slot".
-- Respects any user override stored in storage.stats_category_items[cat].
function stats_gui.get_category_item_names(cat)
    local override = storage.stats_category_items and storage.stats_category_items[cat]
    if override then
        local out = {}
        for i = 1, MAX_COLS do
            local name = override[i]
            if name and prototypes.item[name] then
                out[i] = name
            end
        end
        return out
    end
    -- No override: use defaults, placed sequentially, capped at MAX_COLS
    local defaults = default_item_names(cat)
    local out = {}
    for i = 1, math.min(#defaults, MAX_COLS) do
        out[i] = defaults[i]
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function fmt(n)
    if n == 0 then return "0" end
    if n >= 1000000 then return string.format("%.1fM", n / 1000000) end
    if n >= 1000    then return string.format("%.1fk", n / 1000) end
    return tostring(math.floor(n))
end

local function get_count(force, item_name, precision)
    local total = 0
    for _, surface in pairs(game.surfaces) do
        local ok, stats = pcall(function()
            return force.get_item_production_statistics(surface)
        end)
        if ok and stats then
            if precision == ALLTIME then
                local ok2, val = pcall(function()
                    return stats.get_input_count(item_name)
                end)
                if ok2 and val then total = total + val end
            else
                local ok2, val = pcall(function()
                    return stats.get_flow_count{
                        name            = item_name,
                        category        = "input",
                        precision_index = precision,
                        count           = true,
                    }
                end)
                if ok2 and val then total = total + val end
            end
        end
    end
    return total
end

-- Returns force list sorted by player name; includes online status.
-- leaving_index: player_index of the player currently leaving (may be nil).
-- We check fp.connected on every member of force.players (all players, connected
-- or not) rather than force.connected_players, because connected_players may not
-- have been updated yet when on_player_left_game fires.  The leaving_index
-- override handles the remaining race window where connected is still true.
local function player_forces(leaving_index)
    local list = {}
    for name, force in pairs(game.forces) do
        if name:find("^player%-") and name ~= "spectator" then
            local pname = helpers.display_name(name)
            -- Skip players who haven't spawned yet (still in landing pen)
            local player_obj = game.get_player(pname)
            if player_obj and not (storage.spawned_players or {})[player_obj.index] then
                goto next_force
            end
            local online = false
            for _, fp in ipairs(force.players) do
                if fp.connected and fp.index ~= leaving_index then
                    online = true
                    break
                end
            end
            list[#list + 1] = {
                player_name = pname,
                force       = force,
                online      = online,
            }
            ::next_force::
        end
    end
    table.sort(list, function(a, b) return a.player_name < b.player_name end)
    return list
end

local function get_state(player)
    if not storage.stats_gui_state then storage.stats_gui_state = {} end
    local s = storage.stats_gui_state[player.index]
    if not s then
        s = {
            category  = "ores",
            precision = defines.flow_precision_index.one_minute,
        }
        storage.stats_gui_state[player.index] = s
    end
    return s
end

-- ---------------------------------------------------------------------------
-- GUI construction
-- ---------------------------------------------------------------------------

function stats_gui.build_stats_gui(player, leaving_index)
    local screen = player.gui.screen

    -- Save current position before destroying so rebuilds don't re-centre
    if not storage.stats_gui_location then storage.stats_gui_location = {} end
    local saved_pos = nil
    if screen.sb_stats_frame then
        saved_pos = screen.sb_stats_frame.location
        storage.stats_gui_location[player.index] = saved_pos
        screen.sb_stats_frame.destroy()
    else
        saved_pos = storage.stats_gui_location[player.index]
    end

    local state      = get_state(player)
    local item_names = stats_gui.get_category_item_names(state.category)   -- [1..MAX_COLS], sparse
    local all_pf     = player_forces(leaving_index)
    local show_offline = helpers.show_offline(player)
    local my_name    = helpers.display_name(player.force.name)
    local pf         = {}
    for _, entry in ipairs(all_pf) do
        if entry.online or entry.player_name == my_name or show_offline then
            pf[#pf + 1] = entry
        end
    end

    -- ── Outer frame ──────────────────────────────────────────────────────────
    local frame = screen.add{
        type      = "frame",
        name      = "sb_stats_frame",
        direction = "vertical",
    }
    frame.style.minimal_width = 320

    if saved_pos then
        frame.location = saved_pos
    else
        frame.auto_center = true
    end

    -- ── Title bar (draggable) ─────────────────────────────────────────────────
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

    tbar.add{
        type    = "sprite-button",
        name    = "sb_stats_close",
        sprite  = "utility/close",
        style   = "frame_action_button",
        tooltip = "Close",
    }

    -- ── Category tab buttons ──────────────────────────────────────────────────
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

    -- ── Time-period tab buttons ───────────────────────────────────────────────
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

    -- ── Scroll pane + table ───────────────────────────────────────────────────
    local scroll = frame.add{
        type                     = "scroll-pane",
        name                     = "sb_stats_scroll",
        direction                = "vertical",
        horizontal_scroll_policy = "auto",
        vertical_scroll_policy   = "auto",
    }
    scroll.style.maximal_height = 500
    scroll.style.maximal_width  = 900

    if #pf == 0 then
        scroll.add{type = "label", caption = "(no players yet)"}
        return
    end

    -- Always MAX_COLS item columns + 1 player-name column
    local tbl = scroll.add{
        type                  = "table",
        name                  = "sb_stats_table",
        column_count          = MAX_COLS + 1,
        draw_horizontal_lines = true,
    }
    tbl.style.horizontal_spacing = 4
    tbl.style.vertical_spacing   = 2

    -- ── Header row ───────────────────────────────────────────────────────────
    -- Blank corner cell, then MAX_COLS choose-elem-buttons (some may be empty).
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
        if item_name then
            btn.elem_value = item_name
        end
    end

    -- ── Data rows ────────────────────────────────────────────────────────────
    for _, entry in ipairs(pf) do
        -- Player name cell: flow so we can append "(offline)" with a different style
        local name_cell = tbl.add{type = "flow", direction = "horizontal"}
        name_cell.style.vertical_align = "center"
        name_cell.style.minimal_width  = 160

        local name_lbl = name_cell.add{type = "label", caption = entry.player_name}
        name_lbl.style.font = "default-bold"
        if not entry.online then
            name_lbl.style.font_color = {0.65, 0.65, 0.65}
            -- Factorio 2.0 ships no italic font; "default-small" is the
            -- smallest available weight.  Grey colour provides visual separation.
            local off_lbl = name_cell.add{type = "label", caption = " (offline)"}
            off_lbl.style.font       = "default-small"
            off_lbl.style.font_color = {0.45, 0.45, 0.45}
        end

        -- One count cell per column; empty columns get a blank label
        for col_idx = 1, MAX_COLS do
            local item_name = item_names[col_idx]
            if item_name then
                local count = get_count(entry.force, item_name, state.precision)
                local cell  = tbl.add{type = "label", caption = fmt(count)}
                cell.style.minimal_width    = 38
                cell.style.horizontal_align = "right"
            else
                tbl.add{type = "label", caption = ""}
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

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
            get_state(player).category = cat
            stats_gui.build_stats_gui(player)
            return true
        end
    end

    for _, tp in ipairs(TIME_PERIODS) do
        if name == "sb_stats_time_" .. tp.key then
            get_state(player).precision = tp.precision
            stats_gui.build_stats_gui(player)
            return true
        end
    end

    return false
end

-- Handle item-chooser selections (on_gui_elem_changed).
-- Setting a slot: persists the new item globally and rebuilds.
-- Clearing a slot (elem_value = nil): clears that position in storage and rebuilds.
function stats_gui.on_gui_elem_changed(event)
    local el = event.element
    if not el or not el.valid then return false end
    if not (el.tags and el.tags.sb_stats_col) then return false end

    local player = game.get_player(event.player_index)
    if not player then return false end

    local new_item = el.elem_value     -- nil when user clears the slot
    local col_idx  = el.tags.sb_stats_col
    local cat      = el.tags.sb_stats_cat

    -- Lazily initialise the category's storage entry from current defaults
    if not storage.stats_category_items then storage.stats_category_items = {} end
    if not storage.stats_category_items[cat] then
        local current = stats_gui.get_category_item_names(cat)
        storage.stats_category_items[cat] = current
    end

    -- nil clears the slot; a name fills it
    storage.stats_category_items[cat][col_idx] = new_item

    stats_gui.build_stats_gui(player)
    return true
end

--- Register the nav bar button for this player.
--- Idempotent — safe to call on reconnect.
function stats_gui.on_player_created(player)
    nav.add_top_button(player, {
        name    = "sb_stats_btn",
        sprite  = "item/production-science-pack",
        tooltip = "Production Stats",
    })
    nav.on_click("sb_stats_btn", function(e)
        stats_gui.toggle(e.player)
    end)
end

return stats_gui
