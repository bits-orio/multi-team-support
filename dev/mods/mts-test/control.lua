-- Dev-only checks for Multi-Team Support in a real game; dev/run-tests.sh
-- reads the MTS_TEST lines. Covers what a mock cannot: that a surface made
-- through mts-v1 create_team_surface really is the planet it was asked for
-- (pressure, gravity, freezing), and what a planet that already holds a
-- surface does to the next one. Without Space Age there are no planets to
-- tie to, so the base set checks that the call still makes a plain surface.

local TEAM = "team-1"
local SPACE_AGE = script.active_mods["space-age"] ~= nil

local failures = 0

local function check(name, ok, detail)
    if not ok then failures = failures + 1 end
    log("MTS_TEST " .. (ok and "PASS " or "FAIL ") .. name .. (ok and "" or (": " .. tostring(detail))))
end

local function eq(name, actual, expected)
    check(name, actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

--- A team surface made the way a consumer (MTS Dimension Warp) makes one.
local function create(name, planet)
    local made = remote.call("mts-v1", "create_team_surface", TEAM, {
        name = name, planet = planet, map_gen_settings = game.surfaces.nauvis.map_gen_settings,
    })
    eq(name .. ": created", made, name)
    return game.surfaces[name]
end

local function planet_name(surface)
    return surface.planet and surface.planet.name or nil
end

--- The surface is `planet`, with that planet's pressure and gravity, and a
--- machine on it freezes or not.
local function check_planet(surface, planet, want)
    local label = surface.name .. ": "
    eq(label .. "planet", planet_name(surface), planet)
    eq(label .. "the planet holds it", game.planets[planet].surface, surface)
    eq(label .. "pressure", surface.get_property("pressure"), want.pressure)
    eq(label .. "gravity", surface.get_property("gravity"), want.gravity)
    local machine = surface.create_entity{name = "assembling-machine-2", position = {0, 0}, force = TEAM}
    check(label .. "machine placed", machine ~= nil)
    if machine then eq(label .. "machine frozen", machine.frozen, want.frozen) end
end

local AQUILO   = { pressure = 300,  gravity = 15, frozen = true }
local VULCANUS = { pressure = 4000, gravity = 40, frozen = false }
local NAUVIS   = { pressure = 1000, gravity = 10 }

--- A surface whose planet is held by another surface: no planet, Nauvis
--- properties, and the holder keeps the planet.
local function check_waiting(surface, planet, holder)
    local label = surface.name .. ": "
    eq(label .. "no planet while it is held", planet_name(surface), nil)
    eq(label .. "the holder keeps the planet", game.planets[planet].surface, holder)
    eq(label .. "Nauvis pressure meanwhile", surface.get_property("pressure"), NAUVIS.pressure)
    eq(label .. "Nauvis gravity meanwhile", surface.get_property("gravity"), NAUVIS.gravity)
end

local SPACE_AGE_STEPS = {
    [2] = function()
        check_planet(create("mts-test-aquilo", "aquilo"), "aquilo", AQUILO)
        check_planet(create("mts-test-vulcanus", "vulcanus"), "vulcanus", VULCANUS)
    end,
    -- A planet that already holds a surface refuses the next one. MTS logs
    -- that (the wording is checked in tests/test_team_surfaces.lua) and ties
    -- the surface once the holder is deleted.
    [4] = function()
        check_waiting(create("mts-test-aquilo-2", "aquilo"), "aquilo", game.surfaces["mts-test-aquilo"])
        local own = game.planets.gleba.create_surface()
        check_waiting(create("mts-test-gleba", "gleba"), "gleba", own)
        game.delete_surface("mts-test-aquilo")
    end,
    [10] = function()
        eq("first Aquilo surface is gone", game.surfaces["mts-test-aquilo"], nil)
        local second = game.surfaces["mts-test-aquilo-2"]
        eq("mts-test-aquilo-2: planet once the holder is deleted", planet_name(second), "aquilo")
        eq("mts-test-aquilo-2: pressure once tied", second.get_property("pressure"), AQUILO.pressure)
        eq("mts-test-aquilo-2: gravity once tied", second.get_property("gravity"), AQUILO.gravity)
    end,
}

local BASE_STEPS = {
    [2] = function()
        local surface = create("mts-test-aquilo", "aquilo")
        eq("mts-test-aquilo: no planet without Space Age", planet_name(surface), nil)
        eq("mts-test-aquilo: owned by the team",
            remote.call("mts-v1", "get_surface_owner", surface.name), TEAM)
    end,
}

local STEPS = SPACE_AGE and SPACE_AGE_STEPS or BASE_STEPS
local LAST_TICK = 12

script.on_event(defines.events.on_tick, function(event)
    local step = STEPS[event.tick]
    if step then step() end
    if event.tick ~= LAST_TICK then return end
    log("MTS_TEST DONE")
    -- Ends the test-mode run at once. A game before 2.1.24 has no test mode
    -- and no such function: there the run goes on to its tick limit.
    pcall(function() script.finish_test(failures == 0) end)
end)
