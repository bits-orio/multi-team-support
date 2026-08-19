-- gui/stats/discovery.lua
-- Prototype discovery for the production stats GUI: item visibility,
-- tech-unlock depth, and the auto-category (ores / plates / science) lists.

local M = {}

-- ─── Module-level state (rebuilt each script load, never serialised) ───

local proto_cache      = nil
local item_depth_cache = nil

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

-- ─── Unlock depth ──────────────────────────────────────────────────────

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
function M.sort_by_unlock_depth(names)
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

-- ─── Auto-category lists ───────────────────────────────────────────────

--- The ores / plates / science item lists discovered from prototypes,
--- each sorted by unlock depth. Cached per script load.
function M.proto_lists()
    if proto_cache then return proto_cache end

    local ore_set, science_set = {}, {}
    for _, entity in pairs(prototypes.entity) do
        if entity.type == "resource" and entity.mineable_properties then
            for _, product in pairs(entity.mineable_properties.products or {}) do
                if product.type == "item" then ore_set[product.name] = true end
            end
        end
    end
    -- Wood comes from trees, not a mined resource, but players expect to see it next to
    -- ores -- surface it in the Ores category. is_visible_item drops it if it doesn't exist.
    ore_set["wood"] = true
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
        return M.sort_by_unlock_depth(names)
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

return M
