-- Multi-Team Support - milestones/config.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- Milestone tracker configuration. Edit this file to add or modify
-- tracked categories, thresholds, and item discovery logic.
--
-- Each tracker has:
--   category       - unique key for this tracker (e.g. "science", "landfill")
--   announce_first - whether to announce "first to produce" at count >= 1
--   thresholds     - array of count milestones (e.g. {100, 500, 1000})
--   discover_items - function returning a set of item names to track
--   get_count      - function(force, item_name) returning total produced
--
-- To add a new tracker, append a new table to config.trackers.

local config = {}

-- Helper to aggregate item production across all surfaces.
-- In Factorio 2.0, get_item_production_statistics is per-surface.
local function total_produced(force, item_name)
    local total = 0
    for _, surface in pairs(game.surfaces) do
        local stats = force.get_item_production_statistics(surface)
        if stats then
            -- get_input_count returns total produced (items flowing into the stats)
            total = total + (stats.get_input_count(item_name) or 0)
        end
    end
    return total
end

-- Same, for fluids (e.g. crude oil), which use a separate statistics object in 2.0.
local function total_produced_fluid(force, fluid_name)
    local total = 0
    for _, surface in pairs(game.surfaces) do
        local stats = force.get_fluid_production_statistics(surface)
        if stats then
            total = total + (stats.get_input_count(fluid_name) or 0)
        end
    end
    return total
end

config.trackers = {
    -- ═══ Science Packs ═══════════════════════════════════════════════════
    -- Auto-detects all "tool" type items at runtime (works with any mod combo).
    -- announce_first = true means we announce first team to produce any science.
    {
        category       = "science",
        announce_first = true,
        thresholds     = { 100, 200, 500, 1000, 2000, 5000, 10000, 20000, 50000, 100000, 500000, 1000000, 5000000  },
        discover_items = function()
            local items = {}
            for name, proto in pairs(prototypes.item) do
                if proto.type == "tool" then items[name] = true end
            end
            return items
        end,
        get_count = total_produced,
    },

    -- ═══ Landfill ═══════════════════════════════════════════════════════
    -- Tracks only the basic "landfill" item; too trivial to announce first-ever.
    {
        category       = "landfill",
        announce_first = false,
        thresholds     = { 100, 200, 500, 1000, 2000, 5000, 10000, 20000, 50000, 100000, 500000, 1000000, 5000000  },
        discover_items = function() return { ["landfill"] = true } end,
        get_count      = total_produced,
    },

    -- ═══ Space Platform Foundation ══════════════════════════════════════
    -- Only relevant with Space Age. Skipped at runtime if prototype missing.
    {
        category       = "space_platform",
        announce_first = false,
        thresholds     = { 100, 200, 500, 1000, 2000, 5000, 10000, 20000, 50000, 100000 },
        discover_items = function()
            if prototypes.item["space-platform-foundation"] then
                return { ["space-platform-foundation"] = true }
            end
            return {}
        end,
        get_count = total_produced,
    },

    -- ═══ Raw resources ══════════════════════════════════════════════════
    -- Mined ores and pumped crude oil, like landfill. Crude oil is a fluid, so it
    -- reads from the fluid production statistics instead of the item statistics.
    {
        category       = "iron-ore",
        announce_first = false,
        thresholds     = { 1000, 5000, 10000, 20000, 50000, 100000, 500000, 1000000, 5000000 },
        discover_items = function() return { ["iron-ore"] = true } end,
        get_count      = total_produced,
    },
    {
        category       = "copper-ore",
        announce_first = false,
        thresholds     = { 1000, 5000, 10000, 20000, 50000, 100000, 500000, 1000000, 5000000 },
        discover_items = function() return { ["copper-ore"] = true } end,
        get_count      = total_produced,
    },
    {
        category       = "uranium-ore",
        announce_first = false,
        thresholds     = { 100, 500, 1000, 2000, 5000, 10000, 20000, 50000 },
        discover_items = function() return { ["uranium-ore"] = true } end,
        get_count      = total_produced,
    },
    {
        category       = "crude-oil",
        announce_first = false,
        thresholds     = { 1000, 10000, 50000, 100000, 500000, 1000000, 5000000, 10000000, 50000000 },
        discover_items = function() return { ["crude-oil"] = true } end,
        get_count      = total_produced_fluid,
    },
}

return config
