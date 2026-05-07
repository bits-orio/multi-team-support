-- gui/stats_data.lua
-- Constants, prototype discovery, item-list resolution, and data helpers
-- for the production stats GUI.

local helpers = require("scripts.helpers")

local M = {}

-- ─── Constants ─────────────────────────────────────────────────────────

M.MAX_COLS = 12

-- Sentinel stored in state.precision to indicate "all time" mode.
M.ALLTIME = "alltime"

M.TIME_PERIODS = {
    {key = "1min",    label = "1m",  precision = defines.flow_precision_index.one_minute},
    {key = "10min",   label = "10m", precision = defines.flow_precision_index.ten_minutes},
    {key = "1hr",     label = "1h",  precision = defines.flow_precision_index.one_hour},
    {key = "10hr",    label = "10h", precision = defines.flow_precision_index.ten_hours},
    {key = "alltime", label = "All", precision = "alltime"},
}

M.CATEGORIES = {"ores", "plates", "intermediates", "science", "custom"}

M.CAT_LABELS = {
    ores          = "Ores",
    plates        = "Plates",
    intermediates = "Intermediates",
    science       = "Science",
    custom        = "Custom",
}

local DEFAULT_INTERMEDIATES = {
    "iron-gear-wheel", "copper-cable", "electronic-circuit", "advanced-circuit",
    "processing-unit", "pipe", "engine-unit", "electric-engine-unit",
    "flying-robot-frame", "battery", "low-density-structure",
    "rocket-fuel", "rocket-control-unit",
}

local DEFAULT_CUSTOM = {"iron-plate", "steel-plate"}

-- ─── Module-level state (rebuilt each script load, never serialised) ───

local proto_cache            = nil
local intermediates_override = nil
local custom_override        = nil

-- ─── Prototype Discovery ───────────────────────────────────────────────

local function build_proto_cache()
    if proto_cache then return proto_cache end

    local ore_set, science_set = {}, {}
    for _, entity in pairs(prototypes.entity) do
        if entity.type == "resource" and entity.mineable_properties then
            for _, product in pairs(entity.mineable_properties.products or {}) do
                if product.type == "item" then ore_set[product.name] = true end
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

function M.invalidate_categories()
    proto_cache = nil
    storage.stats_categories = nil
end

-- ─── Override API ──────────────────────────────────────────────────────

function M.set_intermediates(items) intermediates_override = items end
function M.set_custom(items)        custom_override = items end

-- ─── Item List Resolution ──────────────────────────────────────────────

local function default_item_names(cat)
    if cat == "intermediates" or cat == "custom" then
        local src = (cat == "intermediates" and intermediates_override or custom_override)
            or (cat == "intermediates" and DEFAULT_INTERMEDIATES or DEFAULT_CUSTOM)
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

--- Returns a positional table [1..MAX_COLS] where nil means "empty slot".
--- Respects per-player overrides in storage.stats_category_items.
function M.get_category_item_names(player_index, cat)
    local override = storage.stats_category_items
        and storage.stats_category_items[player_index]
        and storage.stats_category_items[player_index][cat]
    if override then
        local out = {}
        for i = 1, M.MAX_COLS do
            local name = override[i]
            if name and prototypes.item[name] then out[i] = name end
        end
        return out
    end
    local defaults = default_item_names(cat)
    local out = {}
    for i = 1, math.min(#defaults, M.MAX_COLS) do out[i] = defaults[i] end
    return out
end

-- ─── Data Helpers ──────────────────────────────────────────────────────

function M.fmt(n)
    if n == 0 then return "0" end
    if n >= 1000000 then return string.format("%.1fM", n / 1000000) end
    if n >= 1000    then return string.format("%.1fk", n / 1000) end
    return tostring(math.floor(n))
end

function M.get_count(force, item_name, precision)
    local total = 0
    for _, surface in pairs(game.surfaces) do
        local ok, stats = pcall(function()
            return force.get_item_production_statistics(surface)
        end)
        if ok and stats then
            if precision == M.ALLTIME then
                local ok2, val = pcall(function() return stats.get_input_count(item_name) end)
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

--- Returns team forces sorted by display name; includes online status.
--- leaving_index: index of a player who just left (connected may still be true).
function M.player_forces(leaving_index)
    local list = {}
    for name, force in pairs(game.forces) do
        if name:find("^team%-") then
            local slot = tonumber(name:match("^team%-(%d+)$"))
            local occupied = slot and (storage.team_pool or {})[slot] == "occupied"
            if not occupied then goto next_force end

            local online = false
            for _, fp in ipairs(force.players) do
                if fp.connected and fp.index ~= leaving_index then
                    online = true; break
                end
            end
            list[#list + 1] = {
                player_name = helpers.display_name(name),
                caption     = helpers.team_tag_with_leader(name),
                force       = force,
                online      = online,
            }
            ::next_force::
        end
    end
    table.sort(list, function(a, b) return a.player_name < b.player_name end)
    return list
end

function M.get_state(player)
    if not storage.stats_gui_state then storage.stats_gui_state = {} end
    local s = storage.stats_gui_state[player.index]
    if not s then
        s = {
            category  = "ores",
            precision = defines.flow_precision_index.one_minute,
            sort_col  = nil,
            sort_dir  = "desc",
        }
        storage.stats_gui_state[player.index] = s
    end
    return s
end

return M
