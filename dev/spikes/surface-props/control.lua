-- Spike: what a script can copy from a planet onto a surface that is NOT
-- tied to it, which planet effects follow the copy, and what a later
-- associate_surface does to the written values. See FINDINGS.md. Every
-- result is a log line starting "SP ".
--
-- One case per save, named by case.lua (run.sh writes it into each run's
-- copy of the mod). A case does its setup in on_init, while the save is
-- created, and the rest after the save is loaded, so every case also covers
-- a save and load. The fx cases need a connected player (the game's test
-- mode) for the checks a player's cursor makes.
--
--   props         every planet's values copied onto a plain surface, next to the planet's own surface
--   tie           copied or wrong values, then the planet is freed and the surface is tied to it
--   misc          unsetting a property, one property written before a tie, the pollutant override
--   day           ticks_per_day against the day-night-cycle property, before and after a tie
--   robots        what a construction robot's flight costs on a copy of Aquilo
--   fx-<planet>   a plain surface, a copy and the planet's own surface side by side: recipe and
--                 building conditions, day length, solar power, freezing, lightning
local ARG = require("case")

local TB  -- first tick of this load, minus one
local function L(s)
  log("SP " .. s)
  if s == "DONE" then pcall(function() script.finish_test(true) end) end
end
local PLANETS = { "vulcanus", "gleba", "fulgora", "aquilo" }

local STATUS = {}
for k, v in pairs(defines.entity_status) do STATUS[v] = k end

local function props(s)
  local t = {}
  for n in pairs(prototypes.surface_property) do t[#t + 1] = n .. "=" .. tostring(s.get_property(n)) end
  table.sort(t)
  return table.concat(t, " ")
end

local ATTRS = { "ticks_per_day", "solar_power_multiplier", "dusk", "dawn", "evening", "morning", "min_brightness",
  "show_clouds", "always_day", "freeze_daytime", "ignore_surface_conditions", "has_global_electric_network",
  "peaceful_mode", "no_enemies_mode" }

local function attrs(s)
  local t = {}
  for _, k in ipairs(ATTRS) do
    local ok, v = pcall(function() return s[k] end)
    t[#t + 1] = k .. "=" .. (ok and tostring(v) or "ERR")
  end
  local ok, v = pcall(function() return s.pollutant_type end)
  t[#t + 1] = "pollutant_type=" .. (ok and (v and v.name or "nil") or "ERR")
  ok, v = pcall(function() return s.override_pollution_type end)
  t[#t + 1] = "override_pollution_type=" .. (ok and (v and (v.pollutant and v.pollutant.name or "disabled") or "unset") or ("ERR " .. tostring(v)))
  ok, v = pcall(function() return s.global_effect end)
  t[#t + 1] = "global_effect=" .. (ok and (v and serpent.line(v) or "nil") or "ERR")
  t[#t + 1] = "planet=" .. (s.planet and s.planet.name or "nil")
  return table.concat(t, " ")
end

local function dump(tag, s)
  L(tag .. " [" .. s.name .. "] props: " .. props(s))
  L(tag .. " [" .. s.name .. "] attrs: " .. attrs(s))
end

--- Write every surface property the game knows: the planet's value where its
--- prototype defines one, the property's default otherwise.
local function copy_props(planet, s)
  local defined = planet.prototype.surface_properties or {}
  for name, proto in pairs(prototypes.surface_property) do
    local value = defined[name]
    if value == nil then value = proto.default_value end
    local ok, err = pcall(function() s.set_property(name, value) end)
    if not ok then L("set_property(" .. name .. ") FAILED: " .. tostring(err)) end
  end
end

local function assoc(planet, s)
  local ok, err = pcall(function() planet.associate_surface(s) end)
  L(("associate_surface(%s -> %s) ok=%s err=%s"):format(s.name, planet.name, tostring(ok), ok and "" or tostring(err)))
  return ok
end

local function prep(s)
  s.request_to_generate_chunks({ 0, 0 }, 2)
  s.force_generate_chunk_requests()
  for _, e in pairs(s.find_entities_filtered { area = { { -44, -44 }, { 44, 44 } } }) do
    if e.valid and e.type ~= "character" then e.destroy() end
  end
  local tiles = {}
  for x = -42, 41 do for y = -42, 41 do tiles[#tiles + 1] = { name = "refined-concrete", position = { x, y } } end end
  s.set_tiles(tiles)
end

local function mk(s, name, pos, extra)
  local spec = { name = name, position = pos, force = "player" }
  for k, v in pairs(extra or {}) do spec[k] = v end
  local e = s.create_entity(spec)
  if not e then L("[" .. s.name .. "] could not create " .. name) return end
  -- Lightning on Fulgora's own surface must not take the test rig apart.
  if e.type ~= "entity-ghost" then e.destructible = false end
  return e
end

local function power(s, at)
  local eei = mk(s, "electric-energy-interface", { at[1] - 4, at[2] - 4 })
  mk(s, "substation", { at[1] - 4, at[2] + 1 })
  return eei
end

local function fz(e)
  if not (e and e.valid) then return "gone" end
  local ok, f = pcall(function() return e.frozen end)
  return ok and tostring(f) or "ERR"
end

-- ─── props ────────────────────────────────────────────────────────────

local function props_init()
  for name, p in pairs(prototypes.surface_property) do
    L(("property %s default=%s is_time=%s unit=%s"):format(name, tostring(p.default_value), tostring(p.is_time), tostring(p.localised_unit_key)))
  end
  for name, planet in pairs(game.planets) do
    local pr = planet.prototype
    L(("planet %s surface_properties=%s entities_require_heating=%s pollutant_type=%s player_effects=%s ticks_between_player_effects=%s solar_power_in_space=%s"):format(
      name, serpent.line(pr.surface_properties), tostring(pr.entities_require_heating),
      pr.pollutant_type and pr.pollutant_type.name or "nil", pr.player_effects and #pr.player_effects or "nil",
      tostring(pr.ticks_between_player_effects), tostring(pr.solar_power_in_space)))
    for _, k in ipairs { "lightning_properties", "surface_render_parameters", "persistent_ambient_sounds" } do
      local ok, v = pcall(function() return pr[k] end)
      L(("planet %s prototype.%s readable=%s"):format(name, k, ok and ("yes type=" .. type(v)) or "no"))
    end
  end
  local plain = game.create_surface("sp-plain")
  dump("plain", plain)
  dump("nauvis", game.surfaces.nauvis)
  local ok, err = pcall(function() plain.set_property("no-such-property", 1) end)
  L("set_property(unknown) ok=" .. tostring(ok) .. " err=" .. tostring(err))
  ok, err = pcall(function() plain.set_property("pressure", -5) end)
  L("set_property(pressure,-5) ok=" .. tostring(ok) .. " reads " .. tostring(plain.get_property("pressure")) .. " err=" .. tostring(err))
  plain.set_property("pressure", 1000)
  for _, name in ipairs(PLANETS) do
    local planet = game.planets[name]
    local real = planet.create_surface()
    local copy = game.create_surface("sp-copy-" .. name)
    copy_props(planet, copy)
    dump("copy " .. name, copy)
    dump("real " .. name, real)
    L(("compare %s props %s"):format(name, props(copy) == props(real) and "MATCH" or "DIFFER"))
    assoc(planet, copy)
  end
end

local function props_tick(tick)
  if tick ~= TB + 2 then return end
  for _, name in ipairs(PLANETS) do
    local copy = game.surfaces["sp-copy-" .. name]
    L(("after load %s props %s"):format(name, props(copy) == props(game.planets[name].surface) and "MATCH" or "DIFFER"))
    dump("after load copy " .. name, copy)
  end
  L("DONE")
end

-- ─── tie ──────────────────────────────────────────────────────────────

local function tie_init()
  -- A: Vulcanus held by its own surface; the copy gets the right values plus
  -- one the planet does not define (robot-energy-usage) set wrong.
  local v = game.planets.vulcanus
  v.create_surface()
  local a = game.create_surface("sp-a")
  copy_props(v, a)
  a.set_property("robot-energy-usage", 7)
  dump("A copied+wrong", a)
  -- B: Gleba held by its own surface; everything on the waiting surface set wrong.
  local g = game.planets.gleba
  g.create_surface()
  local b = game.create_surface("sp-b")
  for name in pairs(prototypes.surface_property) do b.set_property(name, 3) end
  b.ticks_per_day = 12345
  b.solar_power_multiplier = 3
  local ok, err = pcall(function() b.override_pollution_type = { pollutant = "pollution" } end)
  L("B override_pollution_type write ok=" .. tostring(ok) .. " err=" .. tostring(err))
  dump("B all wrong", b)
  -- C: Aquilo copy with machines already on it, tied late.
  local q = game.planets.aquilo
  q.create_surface()
  local c = game.create_surface("sp-c")
  copy_props(q, c)
  prep(c)
  storage.c = { mk(c, "assembling-machine-2", { 0, 0 }), mk(c, "pipe", { 6, 0 }), mk(c, "inserter", { 8, 0 }) }
end

local function tie_events()
  local function holders(tag, e)
    local t = {}
    for _, name in ipairs(PLANETS) do
      local s = game.planets[name].surface
      t[#t + 1] = name .. "=" .. (s and s.valid and s.name or "nil")
    end
    L(tag .. " index=" .. e.surface_index .. " planet holders: " .. table.concat(t, " "))
  end
  script.on_event(defines.events.on_pre_surface_deleted, function(e)
    local s = game.surfaces[e.surface_index]
    holders("on_pre_surface_deleted (" .. s.name .. " planet=" .. (s.planet and s.planet.name or "nil") .. ")", e)
  end)
  script.on_event(defines.events.on_surface_deleted, function(e)
    holders("on_surface_deleted", e)
    for _, pair in ipairs { { "vulcanus", "sp-a" }, { "gleba", "sp-b" }, { "aquilo", "sp-c" } } do
      local planet, s = game.planets[pair[1]], game.surfaces[pair[2]]
      if not planet.surface and not s.planet then
        assoc(planet, s)
        dump("tied in on_surface_deleted", s)
      end
    end
  end)
end

local function tie_tick(tick)
  local t = tick - TB
  if t == 2 then
    dump("A after load", game.surfaces["sp-a"])
    dump("B after load", game.surfaces["sp-b"])
    local c = storage.c
    L("C before tie frozen: machine=" .. fz(c[1]) .. " pipe=" .. fz(c[2]) .. " inserter=" .. fz(c[3]))
    for _, name in ipairs { "vulcanus", "gleba", "aquilo" } do
      local own = game.planets[name].surface
      L("deleting " .. own.name .. " deletable=" .. tostring(own.deletable))
      game.delete_surface(own)
      L("same tick after delete_surface: valid=" .. tostring(own.valid) .. " planet.surface=" .. (game.planets[name].surface and game.planets[name].surface.name or "nil"))
    end
  elseif t == 6 then
    local a, b, c = game.surfaces["sp-a"], game.surfaces["sp-b"], storage.c
    dump("A 4 ticks after tie", a)
    dump("B 4 ticks after tie", b)
    L("C after tie frozen: machine=" .. fz(c[1]) .. " pipe=" .. fz(c[2]) .. " inserter=" .. fz(c[3]))
    -- Clearing what a script wrote before the tie.
    b.ticks_per_day = 25000
    b.solar_power_multiplier = 1
    local ok, err = pcall(function() b.override_pollution_type = nil end)
    L("B override_pollution_type = nil ok=" .. tostring(ok) .. " err=" .. tostring(err))
    dump("B after clearing script writes", b)
    -- Does a write on a tied surface stick?
    a.set_property("pressure", 555)
    L("A tied, set_property(pressure,555) reads " .. tostring(a.get_property("pressure")))
  elseif t == 12 then
    dump("A 6 ticks after the write on a tied surface", game.surfaces["sp-a"])
    L("DONE")
  end
end

-- ─── fx-<planet> ──────────────────────────────────────────────────────

local RECIPE = { vulcanus = "foundry", gleba = "biochamber", fulgora = "lightning-rod", aquilo = "cryogenic-plant" }
local fx

local function fx_surface(tag, s, recipe)
  prep(s)
  local g = { tag = tag, s = s }
  power(s, { 0, 0 })
  g.machine = mk(s, "assembling-machine-3", { 4, 0 })
  local ok, ret = pcall(function() return g.machine.set_recipe(recipe) end)
  local r = g.machine.get_recipe()
  L(("%s set_recipe(%s) ok=%s err=%s get_recipe=%s"):format(tag, recipe, tostring(ok), ok and "" or tostring(ret), r and r.name or "nil"))
  for _, ing in pairs(prototypes.recipe[recipe].ingredients) do
    if ing.type == "item" then
      local n = g.machine.insert { name = ing.name, count = ing.amount }
      if n ~= ing.amount then L(tag .. " inserted only " .. n .. " of " .. ing.amount .. " " .. ing.name) end
    else
      g.machine.insert_fluid { name = ing.name, amount = ing.amount }
    end
  end
  g.panel = mk(s, "solar-panel", { 0.5, 20.5 })
  g.acc = mk(s, "accumulator", { 4, 21 })
  mk(s, "medium-electric-pole", { 2.5, 23.5 })
  g.pipe = mk(s, "pipe", { 0.5, -20.5 })
  g.inserter = mk(s, "inserter", { 2.5, -20.5 })
  L(("%s can_place_entity(biolab, manual)=%s"):format(tag, tostring(s.can_place_entity {
    name = "biolab", position = { -20.5, 0.5 }, force = "player", build_check_type = defines.build_check_type.manual })))
  local p = game.players[1]
  if p then
    if p.controller_type == defines.controllers.cutscene then p.exit_cutscene() end
    if p.controller_type ~= defines.controllers.god then p.set_controller { type = defines.controllers.god } end
    p.teleport({ -20, 6 }, s)
    p.cursor_stack.set_stack { name = "biolab", count = 1 }
    local can = p.can_build_from_cursor { position = { -20.5, 0.5 } }
    p.build_from_cursor { position = { -20.5, 0.5 } }
    L(("%s player on %s: can_build_from_cursor(biolab)=%s built=%d ghosts=%d"):format(tag, p.surface.name, tostring(can),
      s.count_entities_filtered { name = "biolab" }, s.count_entities_filtered { ghost_name = "biolab" }))
    p.cursor_stack.clear()
    -- A recipe reaching a machine the way a player's tools deliver it:
    -- pasted settings, and a blueprint ghost that gets revived.
    local target = mk(s, "assembling-machine-3", { 10.5, 10.5 })
    local ok, err = pcall(function() return target.copy_settings(g.machine, p) end)
    L(("%s copy_settings(by player) ok=%s err=%s target recipe=%s"):format(tag, tostring(ok), ok and "" or tostring(err),
      target.get_recipe() and target.get_recipe().name or "nil"))
    p.cursor_stack.set_stack { name = "blueprint", count = 1 }
    p.cursor_stack.set_blueprint_entities { { entity_number = 1, name = "assembling-machine-3", position = { 0, 0 }, recipe = recipe } }
    p.build_from_cursor { position = { -30.5, -20.5 } }
    p.cursor_stack.clear()
    local ghost = s.find_entities_filtered { ghost_name = "assembling-machine-3" }[1]
    if ghost then
      local gr = ghost.get_recipe()
      local _, revived = ghost.revive()
      L(("%s blueprint ghost recipe=%s, revived machine recipe=%s"):format(tag, gr and gr.name or "nil",
        revived and revived.get_recipe() and revived.get_recipe().name or "nil"))
    else
      local built = s.find_entities_filtered { name = "assembling-machine-3", area = { { -36, -26 }, { -24, -14 } } }[1]
      L(("%s blueprint built directly: machine=%s recipe=%s"):format(tag, tostring(built ~= nil),
        built and built.get_recipe() and built.get_recipe().name or "nil"))
    end
  else
    L(tag .. " no player in this run")
  end
  return g
end

local function fx_setup(name)
  local planet = game.planets[name]
  local recipe = RECIPE[name]
  game.forces.player.recipes[recipe].enabled = true
  local rp = prototypes.recipe[recipe]
  L(("recipe %s conditions=%s"):format(recipe, serpent.line(rp.surface_conditions)))
  L("biolab conditions=" .. serpent.line(prototypes.entity.biolab.surface_conditions))
  local real = planet.create_surface()
  local plain = game.create_surface("sp-plain")
  local copy = game.create_surface("sp-copy")
  copy_props(planet, copy)
  dump("plain", plain); dump("copy", copy); dump("real", real)
  fx = { name = name, t0 = game.tick, lightning = {}, groups = {
    fx_surface("plain", plain, recipe), fx_surface("copy", copy, recipe), fx_surface("real", real, recipe) } }
end

local function fx_tick(tick)
  local t = tick - TB
  if t == 2 then fx_setup(ARG:sub(4)) end
  if not fx then return end
  for _, g in ipairs(fx.groups) do
    local s, tag = g.s, g.tag
    if t == 3 then g.day0 = s.daytime end
    if t == 103 then
      local d = (s.daytime - g.day0) % 1
      L(("%s daytime moved %.6f in 100 ticks: %.0f ticks per day (ticks_per_day=%d day-night-cycle=%s)"):format(
        tag, d, d > 0 and 100 / d or -1, s.ticks_per_day, tostring(s.get_property("day-night-cycle"))))
      s.daytime = 0
      s.freeze_daytime = true
    end
    if t == 110 then g.e0 = g.acc.energy end
    if t == 170 then
      L(("%s solar at noon: accumulator gained %.0f J in 60 ticks = %.2f kW (solar-power=%s solar_power_multiplier=%s panel frozen=%s acc frozen=%s)"):format(
        tag, g.acc.energy - g.e0, (g.acc.energy - g.e0) / 1000, tostring(s.get_property("solar-power")),
        tostring(s.solar_power_multiplier), fz(g.panel), fz(g.acc)))
      s.daytime = 0.5
    end
    if t == 60 or t == 1300 then
      local m = g.machine
      local out = m.get_output_inventory()
      L(("%s t=%d machine status=%s recipe=%s crafting_progress=%.3f products_finished=%d output=%d frozen=%s | pipe frozen=%s inserter frozen=%s"):format(
        tag, t, tostring(STATUS[m.status]), m.get_recipe() and m.get_recipe().name or "nil", m.crafting_progress,
        m.products_finished, out and out.get_item_count() or -1, fz(m), fz(g.pipe), fz(g.inserter)))
    end
    if t > 170 and t <= 1300 then
      fx.lightning[tag] = (fx.lightning[tag] or 0) + s.count_entities_filtered { type = "lightning" }
    end
    if t == 1300 then
      L(("%s lightning entity-ticks seen in 1130 night ticks: %d (daytime=%.2f)"):format(tag, fx.lightning[tag], s.daytime))
      local before = s.count_entities_filtered { type = "lightning" }
      local ok, err = pcall(function() s.execute_lightning { name = "lightning", position = { 30, 30 } } end)
      L(("%s execute_lightning ok=%s err=%s lightning entities %d -> %d"):format(tag, tostring(ok), ok and "" or tostring(err),
        before, s.count_entities_filtered { type = "lightning" }))
    end
  end
  if t == 1302 then L("DONE") end
end

-- ─── robots ───────────────────────────────────────────────────────────

local rb

local function robots_surface(tag, s, heat)
  prep(s)
  local g = { tag = tag, s = s, pipes = {} }
  power(s, { 0, 0 })
  g.port = mk(s, "roboport", { 0, 0 })
  g.chest = mk(s, "passive-provider-chest", { 2.5, 1.5 })
  g.chest.insert { name = "stone-wall", count = 10 }
  g.port.insert { name = "construction-robot", count = 1 }
  if heat then
    for x = -7, 6 do g.pipes[#g.pipes + 1] = mk(s, "heat-pipe", { x + 0.5, 2.5 }) end
    for y = -6, 1 do g.pipes[#g.pipes + 1] = mk(s, "heat-pipe", { -6.5, y + 0.5 }) end
  end
  g.ghost = mk(s, "entity-ghost", { 38.5, 0.5 }, { inner_name = "stone-wall" })
  return g
end

local function robots_tick(tick)
  local t = tick - TB
  if t == 2 then
    local planet = game.planets.aquilo
    local real = planet.create_surface()
    local plain = game.create_surface("sp-plain")
    local copy = game.create_surface("sp-copy")
    copy_props(planet, copy)
    rb = { robots_surface("plain", plain), robots_surface("copy", copy), robots_surface("real", real, true) }
  end
  if not rb then return end
  for _, g in ipairs(rb) do
    for _, pipe in ipairs(g.pipes) do pipe.temperature = 500 end
    if not g.done then
      local robot = g.robot
      if not (robot and robot.valid) then
        robot = g.s.find_entities_filtered { type = "construction-robot" }[1]
        if robot and not g.e0 then
          g.robot, g.e0, g.p0, g.t0 = robot, robot.energy, robot.position, t
          L(("%s robot left the roboport at t=%d energy=%.0f (robot-energy-usage=%s port frozen=%s)"):format(
            g.tag, t, robot.energy, tostring(g.s.get_property("robot-energy-usage")), fz(g.port)))
        end
      end
      if g.e0 and not g.ghost.valid then
        g.done = true
        local r = g.robot
        if r and r.valid then
          L(("%s wall built at t=%d: robot used %.0f J in %d ticks (energy now %.0f)"):format(g.tag, t, g.e0 - r.energy, t - g.t0, r.energy))
        else
          L(g.tag .. " wall built but the robot is gone")
        end
      end
    end
    if t == 1500 and not g.done then
      L(("%s NOT built by t=1500: port frozen=%s chest frozen=%s port status=%s robot seen=%s"):format(
        g.tag, fz(g.port), fz(g.chest), tostring(STATUS[g.port.status]), tostring(g.e0 ~= nil)))
    end
  end
  if t == 1500 then L("DONE") end
end


-- ─── misc ─────────────────────────────────────────────────────────────

local function misc_init()
  -- Can a written property be unset again?
  local d = game.create_surface("sp-d")
  local ok, err = pcall(function() d.set_property("pressure", nil) end)
  L("set_property(pressure, nil) ok=" .. tostring(ok) .. " err=" .. tostring(err) .. " reads " .. tostring(d.get_property("pressure")))
  -- Only ONE property written, then a real tie: do the others follow the planet?
  d.set_property("pressure", 1234)
  assoc(game.planets.fulgora, d)
  dump("D one property written, then tied to fulgora", d)
  -- Pollutant override on an untied surface.
  local e = game.create_surface("sp-e")
  e.request_to_generate_chunks({ 0, 0 }, 1); e.force_generate_chunk_requests()
  local function pol(tag)
    local ok, err = pcall(function() e.pollute({ 0, 0 }, 100) end)
    L(("E %s: pollutant_type=%s override=%s | pollute ok=%s err=%s get_pollution=%s"):format(tag,
      e.pollutant_type and e.pollutant_type.name or "nil", attrs(e):match("override_pollution_type=(%S+)"),
      tostring(ok), ok and "" or tostring(err), tostring(e.get_pollution({ 0, 0 }))))
    e.clear_pollution()
  end
  pol("untouched")
  local function try(tag, value)
    local ok, err = pcall(function() e.override_pollution_type = value end)
    L("E write " .. tag .. " ok=" .. tostring(ok) .. " err=" .. tostring(err))
    pol(tag)
  end
  try("{} (disabled)", {})
  try("{pollutant='spores'}", { pollutant = "spores" })
  try("{pollutant=<gleba prototype's LuaAirbornePollutantPrototype>}", { pollutant = game.planets.gleba.prototype.pollutant_type })
  try("{pollutant=<vulcanus prototype's nil>}", { pollutant = game.planets.vulcanus.prototype.pollutant_type })
  try("nil (unset)", nil)
  L("DONE-INIT")
end


-- ─── day ──────────────────────────────────────────────────────────────

local function day_init()
  local function d(tag, s) L(("%s [%s]: ticks_per_day=%d day-night-cycle=%s planet=%s"):format(tag, s.name, s.ticks_per_day, tostring(s.get_property("day-night-cycle")), s.planet and s.planet.name or "nil")) end
  local f = game.create_surface("sp-f")
  d("F fresh", f)
  f.ticks_per_day = 7777
  d("F after ticks_per_day=7777", f)
  assoc(game.planets.fulgora, f)
  d("F after a tie to fulgora", f)
  local g = game.create_surface("sp-g")
  assoc(game.planets.gleba, g)
  d("G tied to gleba", g)
  g.ticks_per_day = 7777
  d("G after ticks_per_day=7777", g)
  local h = game.create_surface("sp-h")
  h.set_property("day-night-cycle", 5400)
  d("H after set_property(day-night-cycle,5400)", h)
  h.ticks_per_day = 7777
  d("H after ticks_per_day=7777", h)
  assoc(game.planets.vulcanus, h)
  d("H after a tie to vulcanus", h)
  local i = game.create_surface("sp-i")
  i.solar_power_multiplier = 0
  L("I solar_power_multiplier=0 leaves solar-power=" .. tostring(i.get_property("solar-power")))
  i.set_property("solar-power", 400)
  L("I set_property(solar-power,400) leaves solar_power_multiplier=" .. tostring(i.solar_power_multiplier))
end

-- ─── wiring ───────────────────────────────────────────────────────────

script.on_init(function()
  if remote.interfaces.freeplay then
    pcall(remote.call, "freeplay", "set_disable_crashsite", true)
    pcall(remote.call, "freeplay", "set_skip_intro", true)
  end
  L("on_init ARG=" .. ARG)
  local ok, err = true, nil
  if ARG == "props" then ok, err = pcall(props_init) end
  if ARG == "tie" then ok, err = pcall(tie_init) end
  if ARG == "misc" then ok, err = pcall(misc_init) end
  if ARG == "day" then ok, err = pcall(day_init) end
  if not ok then L("INIT ERROR " .. tostring(err)) end
end)

if ARG == "tie" then tie_events() end

script.on_event(defines.events.on_tick, function(e)
  -- The save is created at tick 0 and loaded for the run; count from the
  -- first tick this load sees so --benchmark and --test-save behave alike.
  TB = TB or (e.tick - 1)
  local ok, err = pcall(function()
    if ARG == "misc" or ARG == "day" then if e.tick == TB + 2 then L("DONE") end
    elseif ARG == "props" then props_tick(e.tick)
    elseif ARG == "tie" then tie_tick(e.tick)
    elseif ARG == "robots" then robots_tick(e.tick)
    elseif ARG:sub(1, 3) == "fx-" then fx_tick(e.tick) end
  end)
  if not ok then L("TICK ERROR t=" .. e.tick .. " " .. tostring(err)) end
end)
