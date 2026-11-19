-- tests/test_team_surfaces.lua
-- Headless tests for the planet tie in scripts/team_surfaces.lua: a team
-- surface that cannot be tied to its planet keeps Nauvis properties, which
-- nothing in the game shows, so every such case must reach the log with the
-- surface, the planet, the engine's error and the surface that holds the
-- planet. What the engine itself does (pressure, gravity, freezing) is
-- checked in the game by dev/mods/mts-test.

local W = require("tests.agent_world")

local report, check, eq = W.new_report()

local HELD = "Planet must not already be associated with a surface."

local lines

--- A planet that holds at most one surface, as the engine does: a second
--- associate_surface throws.
local function planet(name, holder)
    local p = { name = name, valid = true, surface = holder }
    function p.associate_surface(surface)
        if p.surface then error(HELD, 0) end
        p.surface = surface
        surface.planet = p
    end
    return p
end

local function surface(name, index)
    return { name = name, index = index, valid = true,
        request_to_generate_chunks = function() end,
        force_generate_chunk_requests = function() end }
end

--- The module loaded against a world with the given planets.
local function load(planets)
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
    package.loaded["scripts.team_surfaces"] = nil
    return require("scripts.team_surfaces")
end

local function logged(...)
    local line = lines[#lines] or ""
    for _, part in ipairs({...}) do
        if not line:find(part, 1, true) then return false end
    end
    return true
end

-- ─── a free planet ────────────────────────────────────────────────────

do
    local aquilo = planet("aquilo")
    local m = load({ aquilo = aquilo })
    eq("free planet: created", m.create_team_surface("team-1", { name = "warp-1", planet = "aquilo" }), "warp-1")
    check("free planet: tied", aquilo.surface == game.surfaces["warp-1"])
    eq("free planet: nothing to log", #lines, 0)
end

-- ─── a planet that another surface holds ──────────────────────────────

do
    local own = surface("gleba", 3)
    local gleba = planet("gleba", own)
    local m = load({ gleba = gleba })
    eq("held planet: still created", m.create_team_surface("team-1", { name = "warp-2", planet = "gleba" }), "warp-2")
    check("held planet: the holder keeps it", gleba.surface == own)
    eq("held planet: one log line", #lines, 1)
    check("held planet: the line names surface, planet and holder",
        logged("surface 'warp-2'", "planet 'gleba'", "held by surface 'gleba'", "Nauvis properties"), lines[1])
    eq("held planet: left waiting", storage.surfaces_waiting_for_planet[game.surfaces["warp-2"].index], "gleba")

    m.tie_waiting_surfaces()
    eq("holder still there: no second line", #lines, 1)

    gleba.surface = nil
    m.tie_waiting_surfaces()
    check("holder deleted: tied", gleba.surface == game.surfaces["warp-2"])
    eq("holder deleted: nothing more to log", #lines, 1)
end

-- ─── the engine refuses the tie ───────────────────────────────────────

do
    local taker = surface("taker", 4)
    local fulgora = planet("fulgora")
    -- Reads free, then refuses: what a planet taken between the check and
    -- the call looks like.
    function fulgora.associate_surface()
        fulgora.surface = taker
        error(HELD, 0)
    end
    local m = load({ fulgora = fulgora })
    m.create_team_surface("team-1", { name = "warp-3", planet = "fulgora" })
    eq("refused on create: one log line", #lines, 1)
    check("refused on create: surface, planet, error text and holder",
        logged("surface 'warp-3'", "planet 'fulgora'", HELD, "held by surface 'taker'"), lines[1])

    fulgora.surface = nil
    storage.surfaces_waiting_for_planet = { [game.surfaces["warp-3"].index] = "fulgora" }
    m.tie_waiting_surfaces()
    eq("refused on a later tie: logged too", #lines, 2)
    check("refused on a later tie: surface, planet, error text and holder",
        logged("surface 'warp-3'", "planet 'fulgora'", HELD, "held by surface 'taker'"), lines[2])
end

return report
