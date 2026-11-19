-- Spike: what LuaPlanet.associate_surface does to a surface a script made
-- (see ../../FINDINGS.md). One case per run, picked with --test-arg; every
-- result is a log line starting "HP ". run.sh runs all five cases.
--
--   aquilo              tie a new surface to Aquilo, build on it and on an untied surface
--   vulcanus            the same on a planet that needs no heating
--   built-first         entities exist before the surface is tied to Aquilo
--   planet-has-surface  Aquilo already has its own surface (planet.create_surface)
--   two-surfaces        two script surfaces for one planet, then the holder is deleted
local case = script.test_arg or "aquilo"

local function say(s) log("HP " .. s) end

local function props(surface)
  local t = {}
  for name in pairs(prototypes.surface_property) do t[#t + 1] = name .. "=" .. tostring(surface.get_property(name)) end
  table.sort(t)
  return table.concat(t, " ")
end

local function planet_name(planet) return planet and planet.name or "nil" end
local function surface_name(surface) return surface and surface.valid and surface.name or "nil" end

local function info(tag, planet, surface)
  say(("%s planet.surface=%s surface.planet=%s props: %s"):format(tag, surface_name(planet.surface),
    planet_name(surface and surface.planet), surface and props(surface) or "-"))
end

local function associate(planet, surface)
  local ok, err = pcall(function() planet.associate_surface(surface) end)
  say(("associate_surface(%s -> %s) ok=%s err=%s"):format(surface.name, planet.name, tostring(ok), ok and "" or tostring(err)))
  return ok
end

local BUILD = {
  { "assembling-machine-2", { 0, 0 } }, { "inserter", { 4, 0 } }, { "pipe", { 6, 0 } },
  { "wooden-chest", { 8, 0 } }, { "small-electric-pole", { 10, 0 } },
}

local function place(surface, tag)
  surface.request_to_generate_chunks({ 0, 0 }, 2)
  surface.force_generate_chunk_requests()
  local list = {}
  for _, spec in ipairs(BUILD) do
    local entity = surface.create_entity { name = spec[1], position = spec[2], force = "player", raise_built = false }
    list[#list + 1] = entity
    say(("%s placed %s ok=%s"):format(tag, spec[1], tostring(entity ~= nil)))
  end
  return list
end

local function frozen(tag, list)
  local t = {}
  for _, entity in ipairs(list) do
    if entity.valid then
      local ok, value = pcall(function() return entity.frozen end)
      t[#t + 1] = entity.name .. "=" .. (ok and tostring(value) or ("ERR " .. tostring(value)))
    end
  end
  say(("%s frozen: %s"):format(tag, table.concat(t, " ")))
end

-- Entity lists whose frozen state is logged at ticks 6, 100, 300 and 500.
local groups = {}

local cases = {}

local function fresh_planet(name)
  local planet = game.planets[name]
  say(name .. " prototype entities_require_heating=" .. tostring(planet.prototype.entities_require_heating))
  info("before-any", planet, nil)
  local plain = game.create_surface("hp_plain")
  local team = game.create_surface("hp_team")
  info("pre-assoc (surface hp_team)", planet, team)
  say("plain props: " .. props(plain) .. " plain.planet=" .. planet_name(plain.planet))
  associate(planet, team)
  info("post-assoc", planet, team)
  return team, plain
end

cases.aquilo = function()
  local team, plain = fresh_planet("aquilo")
  groups.assoc = place(team, "assoc")
  groups.plain = place(plain, "plain")
end

cases.vulcanus = function()
  local team = fresh_planet("vulcanus")
  groups.assoc = place(team, "assoc")
end

cases["built-first"] = function()
  local team = game.create_surface("hp_team")
  groups.assoc = place(team, "pre")
  frozen("before-assoc", groups.assoc)
  associate(game.planets.aquilo, team)
  frozen("same-tick-after-assoc", groups.assoc)
end

cases["planet-has-surface"] = function()
  local planet = game.planets.aquilo
  local own = planet.create_surface()
  say("own surface created: " .. surface_name(own) .. " idx=" .. own.index)
  local team = game.create_surface("hp_team")
  info("before", planet, team)
  associate(planet, team)
  info("after-failed?", planet, team)
  say("own.planet=" .. planet_name(own.planet) .. " own.valid=" .. tostring(own.valid) .. " team.planet=" .. planet_name(team.planet))
  groups.assoc = place(team, "teamsurf")
  groups.plain = place(own, "own")
end

cases["two-surfaces"] = function()
  local planet = game.planets.aquilo
  local a, b = game.create_surface("hp_a"), game.create_surface("hp_b")
  associate(planet, a)
  info("after A", planet, a)
  associate(planet, b)
  info("after B (second)", planet, b)
  say("a.planet=" .. planet_name(a.planet) .. " b.planet=" .. planet_name(b.planet) .. " planet.surface=" .. surface_name(planet.surface))
  game.delete_surface(a)
  say("deleted a: valid=" .. tostring(a.valid) .. " planet.surface=" .. surface_name(planet.surface) .. " b.planet=" .. planet_name(b.planet))
  associate(planet, b)
  info("after retry B", planet, b)
  -- The surface that was refused goes to another planet.
  associate(game.planets.vulcanus, b)
  say("b.planet=" .. planet_name(b.planet) .. " vulcanus.surface=" .. surface_name(game.planets.vulcanus.surface))
end

local CHECK_TICKS = { [6] = true, [100] = true, [300] = true, [500] = true }

script.on_event(defines.events.on_tick, function(event)
  if event.tick == 5 then
    local run = cases[case]
    local ok, err = pcall(run or function() error("unknown case " .. case) end)
    if not ok then
      say("SETUP ERROR " .. tostring(err))
      script.finish_test(false)
      return
    end
  end
  if CHECK_TICKS[event.tick] then
    for _, name in ipairs { "assoc", "plain" } do
      if groups[name] then frozen("tick " .. event.tick .. " " .. name, groups[name]) end
    end
  end
  if event.tick == 520 then
    say("DONE")
    script.finish_test(true)
  end
end)
