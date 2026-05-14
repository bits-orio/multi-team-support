-- gui/stats_data.lua
-- Constants, prototype discovery, item-list resolution, and data helpers
-- for the production stats GUI.

local helpers = require("scripts.helpers")

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
local item_depth_cache       = nil
local intermediates_override = nil
local custom_override        = nil

-- ─── Visibility helper ────────────────────────────────────────────────

-- A prototype that exists and the modder has not flagged as hidden anywhere
-- the player-facing UI normally consults. Used to keep cross-mod stub items
-- (e.g. PM hiding vanilla production/utility/military science packs so
-- *other* mods can still wire them up) out of the column picker.
local function is_visible_item(name)
    local proto = prototypes.item[name]
    return proto ~= nil
        and not proto.hidden
        and not proto.hidden_in_factoriopedia
end

-- ─── Prototype Discovery ───────────────────────────────────────────────

--- Computes, for every item, the depth at which it first becomes
--- producible. Recipe depth = (longest prerequisite chain to a root tech)
--- of the earliest tech that unlocks the recipe, or 0 if it's enabled at
--- game start. Item depth = min across *primary* producers (recipes where
--- the item is the main product, single-product recipes, or mining); if
--- the item has no primary producer anywhere, falls back to the min across
--- byproduct recipes. This keeps trace-byproduct paths from yanking items
--- to the front of the sort.
local function compute_item_unlock_depths()
    local tech_depth = {}
    local function depth_of(tech_name, on_stack)
        local cached = tech_depth[tech_name]
        if cached ~= nil then return cached end
        local tech = prototypes.technology[tech_name]
        if not tech then return 0 end
        if on_stack[tech_name] then return 0 end -- cycle guard
        on_stack[tech_name] = true
        local max_d = 0
        for prereq_name in pairs(tech.prerequisites or {}) do
            local d = depth_of(prereq_name, on_stack) + 1
            if d > max_d then max_d = d end
        end
        on_stack[tech_name] = nil
        tech_depth[tech_name] = max_d
        return max_d
    end

    -- Pass 1: derive each recipe's depth. A recipe gets the *minimum* depth
    -- across all techs that unlock it. If a recipe is never unlocked by any
    -- tech but is enabled by default, its depth is 0 (available from game
    -- start). Recipes that are neither enabled-by-default nor tech-unlocked
    -- are unreachable and are skipped entirely.
    local recipe_unlock_depth = {}
    for tech_name, tech in pairs(prototypes.technology) do
        local d = depth_of(tech_name, {})
        for _, effect in pairs(tech.effects or {}) do
            if effect.type == "unlock-recipe" then
                local cur = recipe_unlock_depth[effect.recipe]
                if not cur or d < cur then
                    recipe_unlock_depth[effect.recipe] = d
                end
            end
        end
    end

    -- Pass 2: split producers into "primary" (this recipe is canonically how
    -- the item is made) and "byproduct" (the item just happens to fall out
    -- of a recipe whose main output is something else). A recipe is primary
    -- for an item iff main_product names that item, or the recipe has
    -- exactly one item product (single-output recipes have no ambiguity).
    -- Mining is the canonical "primary" producer for ore-style items, at
    -- depth 0.
    local primary_depth, byproduct_depth = {}, {}

    for _, entity in pairs(prototypes.entity) do
        if entity.type == "resource" and entity.mineable_properties then
            for _, product in pairs(entity.mineable_properties.products or {}) do
                if product.type == "item" then primary_depth[product.name] = 0 end
            end
        end
    end

    for recipe_name, recipe in pairs(prototypes.recipe) do
        local rd = recipe_unlock_depth[recipe_name]
        if rd == nil and recipe.enabled then rd = 0 end
        if rd ~= nil then
            local item_products = {}
            for _, product in pairs(recipe.products or {}) do
                if product.type == "item" then
                    item_products[#item_products + 1] = product.name
                end
            end
            local main_name = recipe.main_product and recipe.main_product.name or nil
            for _, name in ipairs(item_products) do
                local is_primary
                if main_name then
                    is_primary = (name == main_name)
                else
                    is_primary = (#item_products == 1)
                end
                local target = is_primary and primary_depth or byproduct_depth
                local cur = target[name]
                if not cur or rd < cur then target[name] = rd end
            end
        end
    end

    -- Primary always wins. Byproduct depth is only used for items that have
    -- no primary producer anywhere (otherwise a trace byproduct unlocked
    -- early would outrank the item's canonical recipe and yank it to the
    -- front of the sort).
    local item_depth = {}
    for name, d in pairs(primary_depth)   do item_depth[name] = d end
    for name, d in pairs(byproduct_depth) do
        if item_depth[name] == nil then item_depth[name] = d end
    end
    return item_depth
end

local function get_item_depths()
    if item_depth_cache then return item_depth_cache end
    item_depth_cache = compute_item_unlock_depths()
    return item_depth_cache
end

-- Order a list of item names by tech-unlock depth, with the prototype's
-- group/item order as a tiebreaker. Drops items the modder has hidden.
local function sort_by_unlock_depth(names)
    local depths = get_item_depths()
    local list = {}
    for _, name in ipairs(names) do
        if is_visible_item(name) then
            local proto = prototypes.item[name]
            local g = (proto.group and proto.group.order) or ""
            list[#list + 1] = {
                name  = name,
                depth = depths[name] or 0,
                tie   = g .. proto.order,
            }
        end
    end
    table.sort(list, function(a, b)
        if a.depth ~= b.depth then return a.depth < b.depth end
        return a.tie < b.tie
    end)
    return list
end

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
        local names = {}
        for item_name in pairs(set) do names[#names + 1] = item_name end
        return sort_by_unlock_depth(names)
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
    item_depth_cache = nil
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
        -- Sort curated lists by tech-unlock depth too, so the visual
        -- progression matches the auto-discovered tabs.
        local sorted = sort_by_unlock_depth(src)
        local out = {}
        for _, item in ipairs(sorted) do out[#out + 1] = item.name end
        return out
    else
        local cache = build_proto_cache()
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
