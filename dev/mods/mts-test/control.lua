-- Dev-only checks for Multi-Team Support in a real game; dev/run-tests.sh
-- reads the MTS_TEST lines. Covers what a mock cannot: that a surface made
-- through mts-v1 create_team_surface really is the planet it was asked for
-- (pressure, gravity, freezing), and that one whose planet already holds a
-- surface stands in for the planet until it can be tied. Without Space Age
-- there are no planets to tie to, so the base set checks that the call still
-- makes a plain surface.

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

local function pollutant(surface)
    return surface.pollutant_type and surface.pollutant_type.name or nil
end

local function place_machine(surface)
    local machine = surface.create_entity{name = "assembling-machine-2", position = {0, 0}, force = TEAM}
    check(surface.name .. ": machine placed", machine ~= nil)
    return machine
end

--- A biolab may only stand at Nauvis pressure, so this is false wherever a
--- planet's pressure really applies. The site is paved and cleared first, so
--- that terrain is never the reason; Nauvis is the proof (step 2).
local function can_build_biolab(surface)
    local tiles = {}
    for x = 16, 23 do for y = 16, 23 do tiles[#tiles + 1] = {name = "refined-concrete", position = {x, y}} end end
    surface.set_tiles(tiles)
    for _, entity in pairs(surface.find_entities_filtered{area = {{16, 16}, {24, 24}}}) do entity.destroy() end
    return surface.can_place_entity{name = "biolab", position = {20, 20}, force = TEAM,
        build_check_type = defines.build_check_type.manual}
end

--- The surface has the planet's values, whether the engine or MTS set them.
local function check_values(surface, want)
    local label = surface.name .. ": "
    eq(label .. "pressure", surface.get_property("pressure"), want.pressure)
    eq(label .. "gravity", surface.get_property("gravity"), want.gravity)
    eq(label .. "solar power", surface.get_property("solar-power"), want.solar)
    eq(label .. "day length", surface.ticks_per_day, want.day)
    eq(label .. "pollutant", pollutant(surface), want.pollutant)
    eq(label .. "a biolab is refused", can_build_biolab(surface), false)
end

--- The surface is `planet`, with that planet's values, and a machine on it
--- freezes or not.
local function check_planet(surface, planet, want)
    local label = surface.name .. ": "
    eq(label .. "planet", planet_name(surface), planet)
    eq(label .. "the planet holds it", game.planets[planet].surface, surface)
    check_values(surface, want)
    local machine = place_machine(surface)
    if machine then eq(label .. "machine frozen", machine.frozen, want.frozen) end
end

local AQUILO   = { pressure = 300,  gravity = 15, solar = 1,   day = 72000, frozen = true }
local VULCANUS = { pressure = 4000, gravity = 40, solar = 400, day = 5400,  frozen = false }
local GLEBA    = { pressure = 2000, gravity = 20, solar = 50,  day = 36000, pollutant = "spores" }

--- A surface whose planet is held by another surface: no planet, the holder
--- keeps it, and the surface stands in with the planet's values. Freezing
--- needs the tie, so a machine on it runs.
local function check_waiting(surface, planet, holder, want)
    local label = surface.name .. ": "
    eq(label .. "no planet while it is held", planet_name(surface), nil)
    eq(label .. "the holder keeps the planet", game.planets[planet].surface, holder)
    check_values(surface, want)
    local machine = place_machine(surface)
    if machine then eq(label .. "machine not frozen while waiting", machine.frozen, false) end
    return machine
end

--- A surface that waited is the planet now, and still has its values.
local function check_tied(surface, planet, want)
    local label = surface.name .. ": "
    eq(label .. "planet once the holder is deleted", planet_name(surface), planet)
    eq(label .. "pollutant override dropped with the tie", surface.override_pollution_type, nil)
    check_values(surface, want)
end

local waiting_machine

local SPACE_AGE_STEPS = {
    [2] = function()
        eq("nauvis: a biolab can be built", can_build_biolab(game.surfaces.nauvis), true)
        check_planet(create("mts-test-aquilo", "aquilo"), "aquilo", AQUILO)
        check_planet(create("mts-test-vulcanus", "vulcanus"), "vulcanus", VULCANUS)
    end,
    -- A planet that already holds a surface refuses the next one, which then
    -- stands in for the planet. MTS logs that (the wording is checked in
    -- tests/test_team_surfaces.lua) and ties the surface once the holder is
    -- deleted: here a team's earlier surface, and the planet's own surface.
    [4] = function()
        waiting_machine = check_waiting(create("mts-test-aquilo-2", "aquilo"), "aquilo",
            game.surfaces["mts-test-aquilo"], AQUILO)
        local own = game.planets.gleba.create_surface()
        check_waiting(create("mts-test-gleba", "gleba"), "gleba", own, GLEBA)
        game.delete_surface("mts-test-aquilo")
    end,
    [10] = function()
        eq("first Aquilo surface is gone", game.surfaces["mts-test-aquilo"], nil)
        check_tied(game.surfaces["mts-test-aquilo-2"], "aquilo", AQUILO)
        eq("mts-test-aquilo-2: the machine freezes with the tie", waiting_machine.frozen, true)
        eq("mts-test-gleba: still waiting behind the planet's own surface",
            planet_name(game.surfaces["mts-test-gleba"]), nil)
        game.delete_surface("gleba")
    end,
    [16] = function()
        eq("Gleba's own surface is gone", game.surfaces["gleba"], nil)
        check_tied(game.surfaces["mts-test-gleba"], "gleba", GLEBA)
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
local LAST_TICK = 18

script.on_event(defines.events.on_tick, function(event)
    local step = STEPS[event.tick]
    if step then step() end
    if event.tick ~= LAST_TICK then return end
    log("MTS_TEST DONE")
    -- Ends the test-mode run at once. A game before 2.1.24 has no test mode
    -- and no such function: there the run goes on to its tick limit.
    pcall(function() script.finish_test(failures == 0) end)
end)
