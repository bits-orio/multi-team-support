-- Spike: LuaGuiElement.zoom_limits (camera) and LuaGuiElement.opacity
-- (sprite, sprite-button), both new in Factorio 2.1.25. See FINDINGS.md.
-- Every result is a log line starting "GZO ".
--
-- Headless, in the game's test mode (run.sh):
--   --test-arg a   the API matrix: defaults, writes, bad values, other element types
--   --test-arg t   what detecting the feature costs (pcall against a version check)
-- In a client (run.sh wheel), through the remote interface "gzo":
--   build     a frame with two cameras (one with zoom_limits) and faded sprites
--   state     logs both cameras' zoom and the player's zoom
--   setzoom   sets one camera's zoom from script
--   matrix    the API matrix, for an engine without test mode
local FEATURE_VERSION = "2.1.25"

log("GZO PARSE has_new=" .. tostring(helpers.compare_versions(script.active_mods.base, FEATURE_VERSION) >= 0)
  .. " base=" .. script.active_mods.base)

-- script.test_arg throws before 2.1.24.
local arg_ok, test_arg = pcall(function() return script.test_arg end)
if not arg_ok then test_arg = nil end

local function say(s) log("GZO " .. s) end

local function show(v)
  if type(v) == "table" then return serpent.line(v, { sortkeys = true, comment = false }) end
  return tostring(v)
end

-- Runs one step and logs "OK <result>" or "ERR <message>".
local function try(label, f)
  local ok, r = pcall(f)
  say(label .. " -> " .. (ok and "OK " or "ERR ") .. show(r))
  return ok, r
end

local function matrix()
  local p = game.players[1]
  say("version base=" .. tostring(script.active_mods.base))
  local fr = p.gui.screen.add { type = "frame", name = "gzo_f", caption = "t" }
  local cam = fr.add { type = "camera", name = "cam", position = { 0, 0 }, surface_index = 1 }
  local spr = fr.add { type = "sprite", name = "spr", sprite = "item/iron-plate" }
  local btn = fr.add { type = "sprite-button", name = "btn", sprite = "item/iron-plate" }
  try("cam.zoom default", function() return cam.zoom end)
  try("cam.zoom_limits default", function() return cam.zoom_limits end)
  try("spr.opacity default", function() return spr.opacity end)
  try("btn.opacity default", function() return btn.opacity end)

  -- opacity: writes and bad values
  try("write spr.opacity=0.5", function() spr.opacity = 0.5 end)
  try("read spr.opacity", function() return spr.opacity end)
  try("write btn.opacity=0.25", function() btn.opacity = 0.25 end)
  try("read btn.opacity", function() return btn.opacity end)
  try("opacity=2", function() spr.opacity = 2 return spr.opacity end)
  try("opacity=-1", function() spr.opacity = -1 return spr.opacity end)
  try("opacity=nil", function() spr.opacity = nil return spr.opacity end)
  try("opacity='x'", function() spr.opacity = "x" return spr.opacity end)
  try("opacity=0.3 string-number '0.3'", function() spr.opacity = "0.3" return spr.opacity end)
  try("opacity 0", function() spr.opacity = 0 return spr.opacity end)

  -- opacity given to gui.add
  try("add sprite opacity=0.5", function()
    return fr.add { type = "sprite", sprite = "item/iron-plate", opacity = 0.5 }.opacity
  end)
  try("add sprite-button opacity=0.5", function()
    return fr.add { type = "sprite-button", sprite = "item/iron-plate", opacity = 0.5 }.opacity
  end)
  try("add sprite opacity=3", function()
    return fr.add { type = "sprite", sprite = "item/iron-plate", opacity = 3 }.opacity
  end)

  -- opacity on element types that have none
  for _, t in pairs { "button", "label", "frame", "camera", "empty-widget", "progressbar", "flow" } do
    local spec = t == "camera" and { position = { 0, 0 } } or {}
    spec.type = t
    local e = fr.add(spec)
    try("opacity read on " .. t, function() return e.opacity end)
    try("opacity write on " .. t, function() e.opacity = 0.5 end)
    try("add " .. t .. " with opacity", function() spec.opacity = 0.5 return fr.add(spec).opacity end)
  end

  -- zoom_limits: writes, reads, bad values
  try("zl on sprite read", function() return spr.zoom_limits end)
  try("zl on sprite write", function() spr.zoom_limits = { closest = { zoom = 10 } } end)
  try("zl write closest.zoom=10", function() cam.zoom_limits = { closest = { zoom = 10 } } end)
  try("zl read", function() return cam.zoom_limits end)
  try("zl write furthest.zoom=0.5", function() cam.zoom_limits = { furthest = { zoom = 0.5 } } end)
  try("zl read after furthest only", function() return cam.zoom_limits end)
  try("zl write both", function() cam.zoom_limits = { closest = { zoom = 4 }, furthest = { zoom = 0.5 } } end)
  try("zl read both", function() return cam.zoom_limits end)
  try("zl write {}", function() cam.zoom_limits = {} end)
  try("zl read after {}", function() return cam.zoom_limits end)
  try("zl write both again", function() cam.zoom_limits = { closest = { zoom = 4 }, furthest = { zoom = 0.5 } } end)
  try("zl write nil", function() cam.zoom_limits = nil end)
  try("zl read after nil", function() return cam.zoom_limits end)
  try("zl write bad: number", function() cam.zoom_limits = 5 end)
  try("zl write bad: closest number", function() cam.zoom_limits = { closest = 5 } end)
  try("zl write bad: closest={}", function() cam.zoom_limits = { closest = {} } end)
  try("zl write bad: inverted", function() cam.zoom_limits = { closest = { zoom = 0.2 }, furthest = { zoom = 2 } } end)
  try("zl read after inverted", function() return cam.zoom_limits end)
  try("zl write negative", function() cam.zoom_limits = { closest = { zoom = -1 } } end)
  try("zl write zero", function() cam.zoom_limits = { closest = { zoom = 0 } } end)
  try("zl at add", function()
    return fr.add { type = "camera", position = { 0, 0 }, zoom_limits = { closest = { zoom = 6 } } }.zoom_limits
  end)
  try("zl furthest_game_view", function() cam.zoom_limits = { furthest_game_view = { zoom = 0.3 } } return cam.zoom_limits end)
  try("zl distance spec", function() cam.zoom_limits = { closest = { distance = 50 } } return cam.zoom_limits end)
  try("zl zoom+distance", function() cam.zoom_limits = { closest = { zoom = 2, distance = 50 } } end)
  try("zl read-modify-write partial keeps?", function()
    cam.zoom_limits = { closest = { zoom = 4 } }
    cam.zoom_limits = { furthest = { zoom = 0.5 } }
    return cam.zoom_limits
  end)

  -- does a limit hold back a zoom set from script?
  cam.zoom_limits = { closest = { zoom = 4 }, furthest = { zoom = 0.5 } }
  for _, z in pairs { 1, 3, 4, 5, 10, 0.5, 0.4, 0.1, 100 } do
    try("limits 0.5..4, set zoom=" .. z, function() cam.zoom = z return cam.zoom end)
  end
  cam.zoom_limits = {}
  for _, z in pairs { 1, 3, 4, 5, 10, 0.1, 0.01 } do
    try("no limits, set zoom=" .. z, function() cam.zoom = z return cam.zoom end)
  end
  cam.zoom = 3
  try("limits closest=1 while zoom=3 -> zoom", function() cam.zoom_limits = { closest = { zoom = 1 } } return cam.zoom end)
  cam.zoom = 1
  try("limits furthest=2 while zoom=1 -> zoom", function() cam.zoom_limits = { furthest = { zoom = 2 } } return cam.zoom end)
end

-- The frame for the client checks: a camera with limits 0.5 to 2 beside one
-- with none, a row of sprites and sprite-buttons at opacity 1, 0.5 and 0.25,
-- and a row of slot buttons at 1 and 0.5.
local function build()
  local p = game.players[1]
  if p.gui.screen.gzo_c then p.gui.screen.gzo_c.destroy() end
  local fr = p.gui.screen.add { type = "frame", name = "gzo_c", caption = "gzo", direction = "vertical" }
  fr.location = { 20, 20 }
  local row = fr.add { type = "flow", direction = "horizontal" }
  local limited = row.add { type = "frame", style = "inside_shallow_frame" }
    .add { type = "camera", name = "cam_lim", position = { 0, 0 }, surface_index = 1, zoom = 1 }
  limited.style.width = 300
  limited.style.height = 300
  limited.zoom_limits = { closest = { zoom = 2 }, furthest = { zoom = 0.5 } }
  local free = row.add { type = "frame", style = "inside_shallow_frame" }
    .add { type = "camera", name = "cam_nolim", position = { 0, 0 }, surface_index = 1, zoom = 1 }
  free.style.width = 300
  free.style.height = 300
  local faded = fr.add { type = "flow", direction = "horizontal" }
  for _, o in pairs { 1, 0.5, 0.25 } do
    faded.add { type = "sprite", sprite = "item/iron-plate", opacity = o }.style.size = 64
    faded.add { type = "sprite-button", sprite = "item/iron-plate", opacity = o, number = 7 }.style.size = 64
  end
  local slots = fr.add { type = "flow", direction = "horizontal" }
  slots.add { type = "sprite-button", sprite = "item/iron-plate", style = "slot_button" }
  slots.add { type = "sprite-button", sprite = "item/iron-plate", style = "slot_button", opacity = 0.5 }
  slots.add { type = "sprite-button", sprite = "item/iron-plate", style = "red_slot_button" }
  slots.add { type = "sprite-button", sprite = "item/iron-plate", style = "red_slot_button", opacity = 0.5 }
  fr.force_auto_center()
end

local function find(element, name)
  if element.name == name then return element end
  for _, child in pairs(element.children) do
    local found = find(child, name)
    if found then return found end
  end
end

local function cameras()
  local frame = game.players[1].gui.screen.gzo_c
  return find(frame, "cam_lim"), find(frame, "cam_nolim")
end

remote.add_interface("gzo", {
  matrix = matrix,
  build = build,
  state = function()
    local limited, free = cameras()
    say(("STATE lim zoom=%s nolim zoom=%s player.zoom=%s"):format(limited.zoom, free.zoom, game.players[1].zoom))
  end,
  setzoom = function(which, zoom)
    local limited, free = cameras()
    local camera = which == "lim" and limited or free
    camera.zoom = zoom
    say("setzoom " .. which .. "=" .. camera.zoom)
  end,
})

-- 100000 rounds each of: a guarded read, a guarded write, the version
-- comparison, and a boolean worked out once. The loops are written out so
-- that nothing but the measured step runs inside them.
local function timing()
  local fr = game.players[1].gui.screen.add { type = "frame" }
  local spr = fr.add { type = "sprite", sprite = "item/iron-plate" }
  local profiler = helpers.create_profiler()
  for _ = 1, 100000 do pcall(function() local _ = spr.opacity end) end
  profiler.stop()
  log({ "", "GZO TIMING pcall-read x100000 ", profiler })
  profiler = helpers.create_profiler()
  for _ = 1, 100000 do pcall(function() spr.opacity = 1 end) end
  profiler.stop()
  log({ "", "GZO TIMING pcall-write x100000 ", profiler })
  profiler = helpers.create_profiler()
  for _ = 1, 100000 do local _ = helpers.compare_versions(script.active_mods.base, FEATURE_VERSION) >= 0 end
  profiler.stop()
  log({ "", "GZO TIMING compare_versions x100000 ", profiler })
  profiler = helpers.create_profiler()
  local has_new = helpers.compare_versions(script.active_mods.base, FEATURE_VERSION) >= 0
  for _ = 1, 100000 do local _ = has_new end
  profiler.stop()
  log({ "", "GZO TIMING cached bool x100000 ", profiler })
end

if test_arg == "a" or test_arg == "t" then
  script.on_event(defines.events.on_tick, function(event)
    if event.tick ~= 30 then return end
    local ok, err = pcall(test_arg == "a" and matrix or timing)
    if not ok then say("FATAL " .. tostring(err)) end
    say("DONE")
    script.finish_test(ok)
  end)
end
