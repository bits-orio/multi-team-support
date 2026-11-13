-- tests/test_simple_seablock.lua
-- Headless tests for compat/simple_seablock.lua: a team's planet gets Simple
-- Seablock's starting rock when its origin chunk generates, once, and only
-- where Simple Seablock has a rock for that planet. What the real mod and real
-- chunk generation do is measured in the engine, not here.

local W = require("tests.agent_world")

local report, check, eq = W.new_report()

local ORIGIN_AREA = { left_top = { x = 0, y = 0 }, right_bottom = { x = 32, y = 32 } }
local ALL_ROCKS = {
    ["nauvis-seablock-chest"] = {}, ["vulcanus-seablock-chest"] = {},
    ["fulgora-seablock-chest"] = {}, ["gleba-seablock-chest"] = {},
    ["aquilo-seablock-chest"] = {},
}

--- The module loaded against a mod list and a set of entity prototypes.
local function load(mods, rocks)
    script = { active_mods = mods or { SimpleSeablock = "1.10.1" } }
    prototypes = { entity = rocks or ALL_ROCKS }
    package.loaded["compat.simple_seablock"] = nil
    return require("compat.simple_seablock")
end

--- A surface that records what is created on it. `copied` is how many rocks
--- the copy from the shared planet already brought.
local function surface(name, copied)
    local s = { name = name, created = {} }
    function s.count_entities_filtered(filter)
        s.filter = filter
        return copied or 0
    end
    function s.create_entity(spec) s.created[#s.created + 1] = spec end
    return s
end

local function generate(module, s, cx, cy)
    module.on_chunk_generated{
        surface = s, position = { x = cx or 0, y = cy or 0 }, area = ORIGIN_AREA,
    }
    return s
end

-- ─── a team's planet that generates on its own ────────────────────────

do
    local m = load()
    local s = generate(m, surface("mts-vulcanus-3"))
    eq("origin chunk: one rock", #s.created, 1)
    eq("origin chunk: the planet's own rock", s.created[1].name, "vulcanus-seablock-chest")
    eq("origin chunk: where Simple Seablock puts it, x", s.created[1].position.x, 1)
    eq("origin chunk: where Simple Seablock puts it, y", s.created[1].position.y, 1)
    eq("origin chunk: it looked for that rock first", s.filter.name, "vulcanus-seablock-chest")
    check("origin chunk: only inside the chunk", s.filter.area == ORIGIN_AREA)

    eq("a slot with two digits", generate(m, surface("mts-gleba-12")).created[1].name,
        "gleba-seablock-chest")
    eq("any other chunk: nothing", #generate(m, surface("mts-vulcanus-3"), 1, 0).created, 0)
    eq("any other chunk, negative: nothing", #generate(m, surface("mts-vulcanus-3"), 0, -1).created, 0)
end

-- ─── where a rock must not be added ───────────────────────────────────

do
    local m = load()
    eq("the copy brought a rock: no second one", #generate(m, surface("mts-nauvis-1", 1)).created, 0)
    eq("the shared planet is Simple Seablock's own", #generate(m, surface("vulcanus")).created, 0)
    eq("the landing pen", #generate(m, surface("landing-pen")).created, 0)
    eq("a planet Simple Seablock has no rock for", #generate(m, surface("mts-maraxsis-2")).created, 0)
end

do
    local m = load({})
    check("without Simple Seablock: not active", m.is_active() == false)
    eq("without Simple Seablock: nothing", #generate(m, surface("mts-vulcanus-3")).created, 0)
end

return report
