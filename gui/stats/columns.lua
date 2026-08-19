-- gui/stats/columns.lua
-- Categories, column caps, curated defaults, per-category item-list
-- resolution, and per-player panel state for the production stats GUI.

local discovery = require("gui.stats.discovery")

local M = {}

-- ─── Constants ─────────────────────────────────────────────────────────

-- MAX_COLS is the floor (minimum slots) for auto-discovered categories so
-- the table is never narrower than a vanilla layout. CURATED_COLS is the
-- cap for curated categories (intermediates, custom) — sized to give a few
-- empty trailing slots beyond the curated defaults for ad-hoc additions.
-- HARD_MAX_COLS is the ceiling for auto categories (overhaul mods can add
-- dozens of science packs / ores / plates).
M.MAX_COLS      = 12
M.CURATED_COLS  = 16
M.HARD_MAX_COLS = 48

-- Categories whose item list comes from prototype scanning and should
-- auto-expand to fit every discovered item. Curated lists stay at CURATED_COLS.
local AUTO_CATEGORIES = { ores = true, plates = true, science = true }

function M.is_auto_category(cat) return AUTO_CATEGORIES[cat] == true end

local function cap_for(cat)
    return AUTO_CATEGORIES[cat] and M.HARD_MAX_COLS or M.CURATED_COLS
end

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

-- ─── Item List Resolution ──────────────────────────────────────────────

local function default_item_names(cat)
    if cat == "intermediates" or cat == "custom" then
        local src = cat == "intermediates" and DEFAULT_INTERMEDIATES or DEFAULT_CUSTOM
        -- Sort curated lists by tech-unlock depth too, so the visual
        -- progression matches the auto-discovered tabs.
        local sorted = discovery.sort_by_unlock_depth(src)
        local out = {}
        for _, item in ipairs(sorted) do out[#out + 1] = item.name end
        return out
    else
        local cache = discovery.proto_lists()
        local items = cache[cat] or {}
        local out = {}
        for _, item in ipairs(items) do out[#out + 1] = item.name end
        return out
    end
end

--- Returns a positional table where nil means "empty slot". For curated
--- categories the array is capped at CURATED_COLS; for auto categories it
--- grows up to HARD_MAX_COLS so overhaul-mod prototypes all get a slot.
--- Respects per-player overrides in storage.stats_category_items.
function M.get_category_item_names(player_index, cat)
    local cap = cap_for(cat)
    local override = storage.stats_category_items
        and storage.stats_category_items[player_index]
        and storage.stats_category_items[player_index][cat]
    if override then
        local out = {}
        for i = 1, cap do
            local name = override[i]
            if name and prototypes.item[name] then out[i] = name end
        end
        return out
    end
    local defaults = default_item_names(cat)
    local out = {}
    for i = 1, math.min(#defaults, cap) do out[i] = defaults[i] end
    return out
end

--- Column count the GUI should render for this category. Curated categories
--- stay at CURATED_COLS. Auto categories grow to fit all filled slots, with
--- one trailing empty slot for the user to add another item.
function M.get_target_cols(player_index, cat)
    if not AUTO_CATEGORIES[cat] then return M.CURATED_COLS end
    local items = M.get_category_item_names(player_index, cat)
    local max_filled = 0
    for i = 1, M.HARD_MAX_COLS do
        if items[i] then max_filled = i end
    end
    local target = max_filled + 1
    if target < M.MAX_COLS      then target = M.MAX_COLS end
    if target > M.HARD_MAX_COLS then target = M.HARD_MAX_COLS end
    return target
end

-- ─── Per-player panel state ────────────────────────────────────────────

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
