-- Multi-Team Support - shadow_race/marks.lua
-- Author: bits-orio
-- License: MIT
--
-- Reading a run's marks: which ones are notable, in what order they came,
-- and how to show one. Marks are written by shadow_race/recorder.lua as
-- { [key] = elapsed }, with keys "tech:<name>", "pack:<item>", "rocket" and
-- "planet:<name>".
--
-- Notable marks are the ones worth an announcement and a countdown: every
-- first science pack, the first rocket, every planet arrival, and the
-- technologies that unlock a science pack, a planet or the rocket silo.
-- Everything is read from prototypes, so it follows the installed mods.

local science_packs = require("scripts.science_packs")

local M = {}

-- Prototypes cannot change within a session, so what is worked out from
-- them is kept in module locals. Every peer works out the same answers.
local notable_tech = {}
local lab_inputs = nil

local function unlocks_something_notable(proto)
    lab_inputs = lab_inputs or science_packs.lab_input_set()
    for _, effect in pairs(proto.effects or {}) do
        if effect.type == "unlock-space-location" then return true end
        local recipe = effect.type == "unlock-recipe" and prototypes.recipe[effect.recipe]
        for _, product in pairs(recipe and recipe.products or {}) do
            if lab_inputs[product.name] or product.name == "rocket-silo" then return true end
        end
    end
    return false
end

function M.is_notable(key)
    local tech = key:match("^tech:(.+)$")
    if not tech then return true end
    local known = notable_tech[tech]
    if known == nil then
        local proto = prototypes.technology[tech]
        known = proto ~= nil and unlocks_something_notable(proto)
        notable_tech[tech] = known
    end
    return known
end

-- The sorted list is asked for every second by every racing team, so it
-- is kept per run until the run gets another mark. Weak keys: a run that
-- is deleted takes its entry with it. Rebuilt from storage alone, so every
-- peer holds the same lists.
local sorted_cache = setmetatable({}, { __mode = "k" })

--- The run's notable marks, earliest first: { { key = , t = }, ... }.
--- The list is shared: read it, never change it.
function M.notable_sorted(run)
    local cached = sorted_cache[run]
    if cached and cached.count == (run.mark_count or 0) then return cached.list end
    local list = {}
    for key, t in pairs(run.marks) do
        if M.is_notable(key) then list[#list + 1] = { key = key, t = t } end
    end
    table.sort(list, function(a, b)
        if a.t ~= b.t then return a.t < b.t end
        return a.key < b.key
    end)
    sorted_cache[run] = { count = run.mark_count or 0, list = list }
    return list
end

--- An icon and the game's own name for a prototype, or the bare name
--- when a mod that had it is gone.
local function named(group, sprite, name)
    local proto = prototypes[group] and prototypes[group][name]
    if not proto then return name end
    return {"", "[img=" .. sprite .. "/" .. name .. "] ", proto.localised_name}
end

--- How a mark reads in chat and in the panels.
function M.label(key)
    local kind, name = key:match("^(%a+):(.+)$")
    if kind == "tech" then return named("technology", "technology", name) end
    -- A pack and the technology that unlocks it share a name: say which.
    if kind == "pack" then return {"mts-gui.shadow-mark-pack", named("item", "item", name)} end
    if kind == "planet" then return named("space_location", "space-location", name) end
    return {"mts-gui.shadow-mark-rocket"}
end

return M
