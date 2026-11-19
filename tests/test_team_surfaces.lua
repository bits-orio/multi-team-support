-- tests/test_team_surfaces.lua
-- Headless tests for the planet tie in scripts/team_surfaces.lua. A team
-- surface whose planet is held by another surface stands in for the planet
-- (its surface properties and pollutant) and is tied once the planet is free.
-- Nothing in the game shows which of the two a surface is, so every wait,
-- refusal and late tie must reach the log with the surface, the planet, the
-- engine's error and the surface that holds the planet. What the engine does
-- with the values (pressure, gravity, freezing) is checked in the game by
-- dev/mods/mts-test.

local W = require("tests.agent_world")

local report, check, eq = W.new_report()

local HELD = "Planet must not already be associated with a surface."
local BUSY = "Surface is busy."

local SPORES = { name = "spores" }
local POLLUTION = { name = "pollution" }

local GLEBA   = { surface_properties = { pressure = 2000, gravity = 20, ["day-night-cycle"] = 36000 }, pollutant_type = SPORES }
local FULGORA = { surface_properties = { pressure = 800, ["magnetic-field"] = 99 } }
local AQUILO  = { surface_properties = { pressure = 300 }, entities_require_heating = true }

local lines

--- A planet that holds at most one surface, as the engine does: a second
--- associate_surface throws.
local function planet(name, prototype, holder)
    local p = { name = name, valid = true, surface = holder, prototype = prototype }
    function p.associate_surface(surface)
        if p.surface then error(HELD, 0) end
        p.surface = surface
        surface.planet = p
    end
    return p
end

--- A surface with Nauvis values. As in the engine, writing the
--- "day-night-cycle" property sets ticks_per_day and writing ticks_per_day
--- leaves the property alone.
local function surface(name, index)
    local s = { name = name, index = index, valid = true, ticks_per_day = 25200,
        properties = { pressure = 1000, gravity = 10 },
        request_to_generate_chunks = function() end,
        force_generate_chunk_requests = function() end }
    function s.set_property(property, value)
        s.properties[property] = value
        if property == "day-night-cycle" then s.ticks_per_day = value end
    end
    return s
end

--- The module loaded against a world with the given planets. Passing false
--- for pollutant_override is a game before 2.1.12, which cannot set one.
local function load(planets, pollutant_override)
    lines = {}
    log = function(text) lines[#lines + 1] = text end
    storage = {}
    game = { surfaces = {}, planets = planets, forces = { ["team-1"] = { valid = true } } }
    local next_index = 10
    function game.create_surface(name)
        next_index = next_index + 1
        local s = surface(name, next_index)
        game.surfaces[name], game.surfaces[next_index] = s, s
        return s
    end
    package.loaded["scripts.surface_utils"] = { get_owner = function() end }
    package.loaded["scripts.helpers"] = { is_team_force = function(n) return n == "team-1" end }
    package.loaded["scripts.chunk_trim"] = { set_exempt = function() end, forget = function() end }
    package.loaded["scripts.pause.control"] = { cover_surface = function() end }
    package.loaded["scripts.engine_features"] = { POLLUTANT_OVERRIDE = pollutant_override ~= false }
    package.loaded["scripts.team_surfaces"] = nil
    return require("scripts.team_surfaces")
end

--- Create a team surface for a planet and return it.
local function create(m, name, planet_name)
    eq(name .. ": created", m.create_team_surface("team-1", { name = name, planet = planet_name }), name)
    return game.surfaces[name]
end

--- The engine deletes a surface: it leaves game.surfaces and frees its planet.
local function delete(s)
    game.surfaces[s.name], game.surfaces[s.index] = nil, nil
    s.valid = false
    if s.planet then s.planet.surface = nil end
end

local function waiting(s) return storage.surfaces_waiting_for_planet[s.index] end

local function logged(...)
    local line = lines[#lines] or ""
    for _, part in ipairs({...}) do
        if not line:find(part, 1, true) then return false end
    end
    return true
end

-- ─── a free planet ────────────────────────────────────────────────────

do
    local aquilo = planet("aquilo", AQUILO)
    local m = load({ aquilo = aquilo })
    local s = create(m, "warp-1", "aquilo")
    check("free planet: tied", aquilo.surface == s)
    eq("free planet: nothing to log", #lines, 0)
    eq("free planet: the engine sets the properties, MTS writes none", s.properties.pressure, 1000)
    eq("free planet: no pollutant override", s.override_pollution_type, nil)
    eq("free planet: not waiting", (storage.surfaces_waiting_for_planet or {})[s.index], nil)
end

-- ─── a planet held by its own surface ─────────────────────────────────

do
    local own = surface("gleba", 3)
    local gleba = planet("gleba", GLEBA, own)
    own.planet = gleba
    local m = load({ gleba = gleba })
    local s = create(m, "warp-2", "gleba")
    check("held planet: the holder keeps it", gleba.surface == own)
    eq("held planet: one log line", #lines, 1)
    check("held planet: the line names surface, planet and holder",
        logged("surface 'warp-2' waits for planet 'gleba'", "held by surface 'gleba'"), lines[1])
    check("held planet: the line says what the surface has", logged("the planet's surface properties and pollutant"), lines[1])
    check("held planet: nothing about freezing on a planet that does not freeze", not logged("freezes"), lines[1])
    eq("held planet: left waiting", waiting(s), "gleba")
    eq("held planet: the planet's pressure", s.properties.pressure, 2000)
    eq("held planet: the planet's gravity", s.properties.gravity, 20)
    eq("held planet: the planet's day length", s.ticks_per_day, 36000)
    eq("held planet: the planet's pollutant", s.override_pollution_type.pollutant, SPORES)

    m.tie_waiting_surfaces()
    eq("holder still there: no second line", #lines, 1)
    eq("holder still there: still waiting", waiting(s), "gleba")

    delete(own)
    m.tie_waiting_surfaces()
    check("holder deleted: tied", gleba.surface == s)
    eq("holder deleted: no longer waiting", waiting(s), nil)
    eq("holder deleted: the tie is logged", #lines, 2)
    check("holder deleted: the line names surface and planet", logged("surface 'warp-2' is tied to planet 'gleba'"), lines[2])
    eq("holder deleted: the pollutant comes from the planet now", s.override_pollution_type, nil)
    eq("holder deleted: the copied pressure is the planet's own", s.properties.pressure, 2000)

    m.tie_waiting_surfaces()
    eq("tied: a later deletion logs nothing", #lines, 2)
end

-- ─── what the log says per planet ─────────────────────────────────────

do
    local aquilo = planet("aquilo", AQUILO, surface("aquilo", 3))
    local fulgora = planet("fulgora", FULGORA, surface("fulgora", 4))
    local m = load({ aquilo = aquilo, fulgora = fulgora })
    create(m, "warp-cold", "aquilo")
    check("planet that freezes: the line says nothing freezes yet", logged("Nothing freezes on it until then."), lines[#lines])
    local s = create(m, "warp-dry", "fulgora")
    check("planet without a pollutant: pollution is switched off",
        s.override_pollution_type ~= nil and s.override_pollution_type.pollutant == nil)
    eq("planet without a pollutant: a property it leaves alone stays", s.properties.gravity, 10)
    check("every waiting surface: the line names what starts with the tie", logged("such as lightning, starts with the tie"), lines[#lines])
end

-- ─── a game that cannot override the pollutant ────────────────────────

do
    local gleba = planet("gleba", GLEBA, surface("gleba", 3))
    local m = load({ gleba = gleba }, false)
    local s = create(m, "warp-old", "gleba")
    eq("old game: the properties are still copied", s.properties.pressure, 2000)
    eq("old game: the pollutant is left alone", s.override_pollution_type, nil)
    check("old game: the line says so", logged("surface properties but Nauvis pollution"), lines[1])
end

-- ─── a pollutant override someone else set ────────────────────────────

do
    local own = surface("gleba", 3)
    local gleba = planet("gleba", GLEBA, own)
    own.planet = gleba
    local m = load({ gleba = gleba })
    local make = game.create_surface
    function game.create_surface(name)
        local s = make(name)
        s.override_pollution_type = { pollutant = POLLUTION }
        return s
    end
    local s = create(m, "warp-own", "gleba")
    eq("foreign override: kept while waiting", s.override_pollution_type.pollutant, POLLUTION)
    delete(own)
    m.tie_waiting_surfaces()
    check("foreign override: tied", gleba.surface == s)
    eq("foreign override: kept after the tie", s.override_pollution_type.pollutant, POLLUTION)
end

-- ─── the engine refuses the tie on create ─────────────────────────────

do
    local taker = surface("taker", 4)
    local fulgora = planet("fulgora", FULGORA)
    local refusal = HELD
    -- Reads free, then refuses: what a planet taken between the check and
    -- the call looks like.
    local accept = fulgora.associate_surface
    function fulgora.associate_surface()
        fulgora.surface = taker
        error(refusal, 0)
    end
    local m = load({ fulgora = fulgora })
    local s = create(m, "warp-3", "fulgora")
    eq("refused on create: one log line", #lines, 1)
    check("refused on create: surface, planet, error text and holder",
        logged("surface 'warp-3' waits for planet 'fulgora'", HELD, "held by surface 'taker'"), lines[1])
    eq("refused on create: left waiting", waiting(s), "fulgora")
    eq("refused on create: the planet's pressure meanwhile", s.properties.pressure, 800)

    fulgora.surface = nil
    m.tie_waiting_surfaces()
    eq("same refusal on a retry: not logged again", #lines, 1)
    eq("same refusal on a retry: still waiting", waiting(s), "fulgora")

    fulgora.surface, refusal = nil, BUSY
    m.tie_waiting_surfaces()
    eq("another refusal: logged", #lines, 2)
    check("another refusal: surface, planet, error text and holder",
        logged("surface 'warp-3' is still not tied to planet 'fulgora'", BUSY, "held by surface 'taker'", "tried again"), lines[2])
    fulgora.surface = nil
    m.tie_waiting_surfaces()
    eq("another refusal: logged once", #lines, 2)

    fulgora.surface, fulgora.associate_surface = nil, accept
    m.tie_waiting_surfaces()
    check("the engine accepts: tied", fulgora.surface == s)
    eq("the engine accepts: no longer waiting", waiting(s), nil)
    eq("the engine accepts: the refusal is forgotten", storage.planet_tie_refusals[s.index], nil)
    check("the engine accepts: the tie is logged", logged("surface 'warp-3' is tied to planet 'fulgora'"), lines[#lines])
end

-- ─── a tie that fails after the holder is deleted is tried again ──────

do
    local own = surface("gleba", 3)
    local gleba = planet("gleba", GLEBA, own)
    own.planet = gleba
    local m = load({ gleba = gleba })
    local s = create(m, "warp-4", "gleba")
    local accept = gleba.associate_surface
    function gleba.associate_surface() error(BUSY, 0) end

    delete(own)
    m.tie_waiting_surfaces()
    eq("failed tie: the entry is kept", waiting(s), "gleba")
    eq("failed tie: logged", #lines, 2)
    check("failed tie: surface, planet, error text and holder",
        logged("surface 'warp-4' is still not tied to planet 'gleba'", BUSY, "held by no surface"), lines[2])
    eq("failed tie: the surface keeps the planet's pressure", s.properties.pressure, 2000)

    m.tie_waiting_surfaces()
    eq("failed again: the entry is kept", waiting(s), "gleba")
    eq("failed again: not logged again", #lines, 2)

    gleba.associate_surface = accept
    m.tie_waiting_surfaces()
    check("next deletion: tied", gleba.surface == s)
    eq("next deletion: no longer waiting", waiting(s), nil)
end

-- ─── a waiting surface that goes away or gets tied elsewhere ──────────

do
    local own = surface("gleba", 3)
    local gleba = planet("gleba", GLEBA, own)
    own.planet = gleba
    local other = planet("fulgora", FULGORA)
    local m = load({ gleba = gleba, fulgora = other })
    local gone = create(m, "warp-5", "gleba")
    local moved = create(m, "warp-6", "gleba")
    delete(gone)
    other.associate_surface(moved)
    local count = #lines
    delete(own)
    m.tie_waiting_surfaces()
    eq("deleted while waiting: forgotten", storage.surfaces_waiting_for_planet[gone.index], nil)
    eq("tied by someone else: forgotten", waiting(moved), nil)
    check("tied by someone else: left on that planet", moved.planet == other and gleba.surface == nil)
    eq("tied by someone else: the copied pollutant goes", moved.override_pollution_type, nil)
    eq("neither is logged", #lines, count)
end

-- ─── a save from before waiting surfaces stood in for the planet ──────

do
    local own = surface("gleba", 3)
    local gleba = planet("gleba", GLEBA, own)
    own.planet = gleba
    local m = load({ gleba = gleba })
    local s = game.create_surface("warp-7")
    s.ticks_per_day = 7777  -- set by the mod that made the surface
    storage.surfaces_waiting_for_planet = { [s.index] = "gleba", [99] = "gleba" }

    m.refresh_waiting_surfaces()
    eq("old save: the planet's pressure", s.properties.pressure, 2000)
    eq("old save: the planet's pollutant", s.override_pollution_type.pollutant, SPORES)
    eq("old save: the day length is left as it was", s.ticks_per_day, 7777)
    eq("old save: the day length property is not written", s.properties["day-night-cycle"], nil)
    eq("old save: still waiting", waiting(s), "gleba")
    eq("old save: one log line", #lines, 1)
    check("old save: the line names surface, planet and holder",
        logged("surface 'warp-7' still waits for planet 'gleba'", "held by surface 'gleba'", "surface properties",
            "day length is left as it was"), lines[1])

    delete(own)
    m.tie_waiting_surfaces()
    check("old save: tied once the holder is deleted", gleba.surface == s)
    eq("old save: the entry of a surface that is gone is dropped", storage.surfaces_waiting_for_planet[99], nil)
end

return report
