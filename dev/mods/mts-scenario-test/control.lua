-- mts-scenario-test: the dev-only driver behind dev/run-scenarios.sh.
--
-- Steps arrive as "/mtst <step> [arg]" on the server console. Admin commands
-- (/mts-pause, /mts-resume) are typed by the joined client, so they go through
-- MTS's real command path. Every check logs one line,
--   MTS_TEST PASS <name>: <detail>    or    MTS_TEST FAIL <name>: <detail>
-- and every step ends with "MTS_TEST STEP <name>", which the runner waits for.
-- Typed commands are echoed as "MTS_TEST CMD <command> <params>".
--
-- Handlers are registered unconditionally at parse time, and MTS's events from
-- their ids on every session, so a joining client always matches the server.

local TAG = "MTS_TEST "
local ACC_CHARGE = 3000000     -- 3 MJ in a 5 MJ accumulator
local EXTRA_CHARGE = 2000000   -- the accumulator on the registered surface

local function say(kind, name, detail)
    log(TAG .. kind .. " " .. name .. (detail ~= nil and (": " .. tostring(detail)) or ""))
end
local function check(name, ok, detail)
    say(ok and "PASS" or "FAIL", name, detail)
    return ok
end
local function step(name, detail) say("STEP", name, detail) end
local function mts(fn, ...) return remote.call("mts-v1", fn, ...) end

local STEPS = {}

local function init_storage()
    storage.queue  = storage.queue or {}
    storage.events = storage.events or {}
    storage.mark   = storage.mark or 0
end

local function later(ticks, name, args)
    storage.queue[#storage.queue + 1] = { at = game.tick + ticks, name = name, args = args or {} }
end

local function run(name, args)
    local fn = STEPS[name]
    if not fn then say("FAIL", "unknown-step", name); step(name); return end
    local ok, err = pcall(fn, args or {})
    if not ok then say("FAIL", name, "test step error: " .. tostring(err)); step(name) end
end

-- ─── MTS events ─────────────────────────────────────────────────────────

local function push(kind, e)
    storage.events[#storage.events + 1] = { kind = kind, force = e.force_name, source = e.source, tick = game.tick }
end

--- Events of one kind since the last mark: count and their sources.
local function since(kind)
    local n, sources = 0, {}
    for i = storage.mark + 1, #storage.events do
        local ev = storage.events[i]
        if ev.kind == kind then n = n + 1; sources[#sources + 1] = tostring(ev.source) end
    end
    return n, table.concat(sources, ",")
end

local function mark() storage.mark = #storage.events end

local HANDLERS = {
    on_team_created = function(e)
        push("created", e)
        storage.team, storage.leader = e.force_name, e.player_index
        step("team-created", e.force_name)
        later(30, "setup", { force = e.force_name })
    end,
    on_team_paused   = function(e) push("paused", e);   step("ev-paused", e.force_name .. " source=" .. tostring(e.source)) end,
    on_team_resumed  = function(e) push("resumed", e);  step("ev-resumed", e.force_name .. " source=" .. tostring(e.source)) end,
    on_team_released = function(e) push("released", e); step("ev-released", e.force_name) end,
}

local function subscribe()
    if not (remote.interfaces["mts-v1"] and remote.interfaces["mts-v1"].get_event_id) then return end
    for name, handler in pairs(HANDLERS) do
        local id = remote.call("mts-v1", "get_event_id", name)
        if id then script.on_event(id, handler) end
    end
end

-- ─── Fixtures ───────────────────────────────────────────────────────────

local function offset(dx, dy)
    local o = storage.fx.origin
    return { x = o.x + dx, y = o.y + dy }
end

local function place(name, dx, dy, extra)
    local spec = { name = name, position = offset(dx, dy), force = storage.team }
    for k, v in pairs(extra or {}) do spec[k] = v end
    return storage.fx.surface.create_entity(spec)
end

local function describe(ent)
    if not (ent and ent.valid) then return "invalid" end
    return string.format("%s at %.1f,%.1f disabled_by_script=%s is_updatable=%s%s", ent.name, ent.position.x, ent.position.y,
        tostring(ent.disabled_by_script), tostring(ent.is_updatable),
        ent.type == "accumulator" and (" energy=" .. ent.energy) or "")
end

--- Clear trees, rocks and water from a square, so fixtures and hand builds fit.
local function clear_square(surface, o, r)
    local area = { { o.x - r, o.y - r }, { o.x + r, o.y + r } }
    for _, e in pairs(surface.find_entities_filtered{ area = area, type = { "tree", "simple-entity", "cliff", "fish" } }) do
        e.destroy()
    end
    local tiles = {}
    for x = o.x - r, o.x + r - 1 do
        for y = o.y - r, o.y + r - 1 do
            if surface.get_tile(x, y).collides_with("water_tile") then
                tiles[#tiles + 1] = { name = "grass-1", position = { x, y } }
            end
        end
    end
    if #tiles > 0 then surface.set_tiles(tiles) end
end

-- Waits until the leader stands on a surface the new team owns (MTS spawns
-- them a few ticks after the claim), then builds the fixtures around them: an
-- isolated accumulator holding 3 MJ, a solar panel and a steam engine. A solar
-- panel is not an updatable entity (writes to disabled_by_script are ignored),
-- so MTS stops solar through the surface's solar_power_multiplier; the steam
-- engine carries the disabled_by_script check.
STEPS["setup"] = function(args)
    local p = game.get_player(storage.leader)
    local tries = (args.tries or 0) + 1
    local surface = p and p.valid and p.physical_surface
    local owner = surface and mts("get_surface_owner", surface.name)
    if owner ~= args.force then
        if tries > 60 then
            check("setup", false, "leader never reached a surface of " .. args.force .. " (on " .. tostring(surface and surface.name) .. ")")
            step("fixtures", "none")
            return
        end
        later(30, "setup", { force = args.force, tries = tries })
        return
    end
    local pos = p.physical_position
    local o = { x = math.floor(pos.x), y = math.floor(pos.y) }
    clear_square(surface, o, 14)
    storage.fx = { surface = surface, origin = o, base_solar = surface.solar_power_multiplier, built = {} }
    local acc = place("accumulator", -8, -8)
    local solar = place("solar-panel", 8.5, -8.5)
    local gen = place("steam-engine", -10.5, -1.5)
    if not check("setup-fixtures", acc ~= nil and solar ~= nil and gen ~= nil, "accumulator=" .. tostring(acc ~= nil)
        .. " solar=" .. tostring(solar ~= nil) .. " steam-engine=" .. tostring(gen ~= nil)) then
        step("fixtures", "none")
        return
    end
    acc.energy = ACC_CHARGE
    storage.fx.acc, storage.fx.solar, storage.fx.gen = acc, solar, gen
    say("INFO", "is_updatable", "accumulator=" .. tostring(acc.is_updatable) .. " solar-panel=" .. tostring(solar.is_updatable)
        .. " steam-engine=" .. tostring(gen.is_updatable))
    p.zoom = 1
    step("fixtures", string.format("team=%s surface=%s origin=%d,%d solar_mult=%s", args.force, surface.name, o.x, o.y,
        tostring(surface.solar_power_multiplier)))
end

-- ─── Shared checks ──────────────────────────────────────────────────────

local function expect_frozen(prefix)
    local f = storage.fx
    local paused = mts("is_team_paused", storage.team)
    check(prefix .. "-paused", paused == true, "is_team_paused=" .. tostring(paused))
    check(prefix .. "-solar-mult-zero", f.surface.solar_power_multiplier == 0,
        f.surface.name .. ".solar_power_multiplier=" .. tostring(f.surface.solar_power_multiplier))
    check(prefix .. "-accumulator-zeroed", f.acc.valid and f.acc.energy == 0, "energy=" .. tostring(f.acc.valid and f.acc.energy))
    check(prefix .. "-steam-engine-disabled", f.gen.valid and f.gen.disabled_by_script == true, describe(f.gen))
end

local function expect_live(prefix)
    local f = storage.fx
    local paused = mts("is_team_paused", storage.team)
    check(prefix .. "-not-paused", paused == false, "is_team_paused=" .. tostring(paused))
    check(prefix .. "-solar-mult-restored", f.surface.solar_power_multiplier == f.base_solar,
        f.surface.name .. ".solar_power_multiplier=" .. tostring(f.surface.solar_power_multiplier) .. " (was " .. tostring(f.base_solar) .. ")")
    check(prefix .. "-accumulator-restored", f.acc.valid and math.abs(f.acc.energy - ACC_CHARGE) < 1,
        "energy=" .. tostring(f.acc.valid and f.acc.energy) .. " (was " .. ACC_CHARGE .. ")")
    check(prefix .. "-steam-engine-enabled", f.gen.valid and f.gen.disabled_by_script == false, describe(f.gen))
end

local function expect_events(name, kind, want_n, want_source)
    local n, sources = since(kind)
    check(name, n == want_n and (want_source == nil or sources == want_source),
        "on_team_" .. kind .. " x" .. n .. (n > 0 and (" source=" .. sources) or "") ..
        " (want x" .. want_n .. (want_source and (" " .. want_source) or "") .. ")")
end

STEPS["mark"] = function() mark(); step("mark") end
STEPS["done"] = function() log(TAG .. "DONE") end

-- ─── Scenario 1: /mts-pause and /mts-resume typed by an admin ───────────

-- A power source another script disabled, on a team that is not paused.
STEPS["s1-notpaused"] = function()
    local g = place("steam-engine", 0.5, -10.5)
    check("s1-other-script-source-placed", g ~= nil)
    g.disabled_by_script = true
    storage.fx.other = g
    mark()
    step("s1-notpaused")
end

-- After a typed /mts-resume on that team; then mts-v1 unpause_team on it too.
STEPS["s1-notpaused-check"] = function()
    local g = storage.fx.other
    check("s1-resume-unpaused-still-unpaused", mts("is_team_paused", storage.team) == false)
    check("s1-resume-unpaused-keeps-other-disabled", g.valid and g.disabled_by_script == true, describe(g))
    expect_events("s1-resume-unpaused-no-event", "resumed", 0)
    local r = mts("unpause_team", storage.team)
    check("s2-unpause-unpaused-keeps-other-disabled", g.valid and g.disabled_by_script == true
        and mts("is_team_paused", storage.team) == false, "returned " .. tostring(r) .. ", " .. describe(g))
    expect_events("s2-unpause-unpaused-no-event", "resumed", 0)
    g.destroy()
    storage.fx.other = nil
    step("s1-notpaused-check")
end

STEPS["s1-paused-check"] = function()
    expect_frozen("s1-admin-pause")
    expect_events("s1-admin-pause-event", "paused", 1, "admin")
    step("s1-paused-check")
end

STEPS["s1-resumed-check"] = function()
    expect_live("s1-admin-resume")
    expect_events("s1-admin-resume-event", "resumed", 1, "admin")
    step("s1-resumed-check")
end

-- A source another script disabled BEFORE a pause stays off after the resume:
-- the pause turns on only what it switched off.
STEPS["obs-predisabled"] = function()
    local g = place("steam-engine", 0.5, -10.5)
    g.disabled_by_script = true
    storage.fx.predisabled = g
    step("obs-predisabled")
end
STEPS["obs-predisabled-check"] = function()
    local g = storage.fx.predisabled
    check("s1-predisabled-source-stays-off", g ~= nil and g.valid and g.disabled_by_script == true,
        describe(g) .. " (it was disabled by another script before the pause)")
    if g and g.valid then g.destroy() end
    storage.fx.predisabled = nil
    step("obs-predisabled-check")
end

-- ─── Scenario 2: holders ────────────────────────────────────────────────

STEPS["s2a-script-pause"] = function()
    mark()
    local r = mts("pause_team", storage.team)
    check("s2a-script-pause-returns-true", r == true, tostring(r))
    expect_frozen("s2a-script-pause")
    expect_events("s2a-script-pause-event", "paused", 1, "script")
    step("s2a-script-pause")
end

-- After a typed /mts-pause on the script-paused team: the script lets go.
STEPS["s2a-script-release"] = function()
    expect_events("s2a-admin-pause-on-paused-no-new-event", "paused", 1, "script")
    local r = mts("unpause_team", storage.team)
    check("s2a-script-release-returns-true", r == true, tostring(r))
    expect_frozen("s2a-after-script-release")
    expect_events("s2a-after-script-release-no-resume-event", "resumed", 0)
    step("s2a-script-release")
end

STEPS["s2a-check"] = function()
    expect_live("s2a-admin-resume")
    expect_events("s2a-resumed-once-at-thaw", "resumed", 1, "admin")
    step("s2a-check")
end

-- Reverse order: a typed /mts-pause first, then the script lets go of a pause
-- it never held, then pauses too; a typed /mts-resume releases both.
STEPS["s2b-script-release"] = function()
    expect_frozen("s2b-admin-pause")
    expect_events("s2b-admin-pause-event", "paused", 1, "admin")
    mts("unpause_team", storage.team)
    expect_frozen("s2b-after-script-release")
    expect_events("s2b-after-script-release-no-resume-event", "resumed", 0)
    mts("pause_team", storage.team)
    expect_events("s2b-script-pause-on-paused-no-new-event", "paused", 1, "admin")
    step("s2b-script-release")
end

STEPS["s2b-check"] = function()
    expect_live("s2b-admin-resume")
    expect_events("s2b-resumed-once-at-thaw", "resumed", 1, "admin")
    step("s2b-check")
end

-- Named holders, all by script.
STEPS["s2c-holders"] = function()
    mark()
    mts("pause_team", storage.team, { holder = "tst-a" })
    mts("pause_team", storage.team)
    mts("unpause_team", storage.team, { holder = "tst-a" })
    expect_frozen("s2c-after-one-of-two-released")
    expect_events("s2c-no-resume-event-yet", "resumed", 0)
    mts("unpause_team", storage.team)
    expect_live("s2c-after-last-released")
    expect_events("s2c-paused-once", "paused", 1, "script")
    expect_events("s2c-resumed-once", "resumed", 1, "script")
    step("s2c-holders")
end

-- ─── Scenario 3: built while paused ─────────────────────────────────────

local function record_build(key, ent)
    storage.fx.built[key] = ent
    later(2, "check-built", { key = key })
end

STEPS["check-built"] = function(args)
    local ent = storage.fx.built[args.key]
    check("s3-" .. args.key .. "-built-frozen", ent and ent.valid and ent.disabled_by_script == true, describe(ent))
    step("built-" .. args.key)
end

-- A steam engine in the leader's cursor; the runner clicks to place it.
STEPS["s3-arm-hand"] = function()
    local p = game.get_player(storage.leader)
    p.clear_cursor()
    p.cursor_stack.set_stack{ name = "steam-engine", count = 1 }
    p.zoom = 1
    storage.expect = "hand"
    step("s3-arm-hand", string.format("player at %.2f,%.2f", p.physical_position.x, p.physical_position.y))
end

-- Power armour with a personal roboport, robots and a steam engine; a ghost
-- for the robots to build.
STEPS["s3-robot"] = function()
    local ch = game.get_player(storage.leader).character
    local armor = ch.get_inventory(defines.inventory.character_armor)
    armor.clear()
    armor.insert{ name = "power-armor" }
    local grid = armor[1].grid
    grid.put{ name = "fission-reactor-equipment" }
    grid.put{ name = "personal-roboport-equipment" }
    ch.insert{ name = "construction-robot", count = 10 }
    ch.insert{ name = "steam-engine", count = 1 }
    local ghost = storage.fx.surface.create_entity{ name = "entity-ghost", inner_name = "steam-engine",
        position = offset(-6.5, 6.5), force = storage.team }
    check("s3-robot-ghost-placed", ghost ~= nil)
    storage.expect_robot = true
    later(60 * 40, "robot-timeout")
    step("s3-robot-armed")
end

STEPS["robot-timeout"] = function()
    if not storage.expect_robot then return end
    storage.expect_robot = nil
    check("s3-robot-built-frozen", false, "no robot built the ghost within 40 s (test setup)")
    step("built-robot")
end

-- Built by script (raise_built) and revived from a ghost (raise_revive).
STEPS["s3-script"] = function()
    local e = place("steam-engine", 0.5, 10.5, { raise_built = true })
    storage.fx.built.script = e
    check("s3-script-built-frozen", e and e.valid and e.disabled_by_script == true, describe(e))
    local ghost = place("entity-ghost", 8.5, 9.5, { inner_name = "steam-engine" })
    local _, revived = ghost.revive{ raise_revive = true }
    storage.fx.built.revive = revived
    check("s3-revive-built-frozen", revived and revived.valid and revived.disabled_by_script == true, describe(revived))
    step("s3-script")
end

-- Commit 4326f48: an existing surface registered to a paused team is frozen.
STEPS["x-register-paused"] = function()
    local s = game.surfaces["tst-extra"] or game.create_surface("tst-extra")
    s.request_to_generate_chunks({ 0, 0 }, 1)
    s.force_generate_chunk_requests()
    clear_square(s, { x = 0, y = 0 }, 8)
    local acc = s.create_entity{ name = "accumulator", position = { 0, 0 }, force = storage.team }
    local sp = s.create_entity{ name = "steam-engine", position = { 4.5, 0.5 }, force = storage.team }
    acc.energy = EXTRA_CHARGE
    local base = s.solar_power_multiplier
    local r = mts("create_team_surface", storage.team, { name = "tst-extra" })
    check("x-register-on-paused-returns-name", r == "tst-extra", tostring(r))
    check("x-register-on-paused-solar-mult-zero", s.solar_power_multiplier == 0, "solar_power_multiplier=" .. s.solar_power_multiplier)
    check("x-register-on-paused-accumulator-zeroed", acc.energy == 0, "energy=" .. acc.energy)
    check("x-register-on-paused-steam-engine-disabled", sp.disabled_by_script == true, describe(sp))
    storage.extra = { surface = s, acc = acc, solar = sp, base = base }
    step("x-register-paused")
end

STEPS["s3-paused-check"] = function()
    expect_frozen("s3-paused")
    step("s3-paused-check")
end

STEPS["s3-resumed-check"] = function()
    expect_live("s3-admin-resume")
    for _, key in ipairs({ "hand", "robot", "script", "revive", "platform" }) do
        local ent = storage.fx.built[key]
        if ent ~= nil then check("s3-" .. key .. "-thawed", ent.valid and ent.disabled_by_script == false, describe(ent)) end
    end
    local plat = storage.plat
    if plat and plat.valid then
        local s = plat.surface
        check("s3sa-platform-solar-mult-restored", s.solar_power_multiplier == storage.plat_base_solar,
            "solar_power_multiplier=" .. s.solar_power_multiplier .. " (was " .. tostring(storage.plat_base_solar) .. ")")
    end
    local x = storage.extra
    if x then
        check("x-register-thawed-solar-mult", x.surface.solar_power_multiplier == x.base, "solar_power_multiplier=" .. x.surface.solar_power_multiplier)
        check("x-register-thawed-accumulator", x.acc.valid and math.abs(x.acc.energy - EXTRA_CHARGE) < 1, "energy=" .. tostring(x.acc.energy))
        check("x-register-thawed-steam-engine", x.solar.valid and x.solar.disabled_by_script == false, describe(x.solar))
        check("x-owner-before-delete", mts("get_surface_owner", "tst-extra") == storage.team)
        game.delete_surface(x.surface)
        storage.extra = nil
        later(20, "x-owner-after-delete")
        return
    end
    step("s3-resumed-check")
end

STEPS["x-owner-after-delete"] = function()
    local owner = mts("get_surface_owner", "tst-extra")
    check("x-ownership-ends-with-surface", game.surfaces["tst-extra"] == nil and owner == nil,
        "surface exists=" .. tostring(game.surfaces["tst-extra"] ~= nil) .. " owner=" .. tostring(owner))
    step("s3-resumed-check")
end

-- Space Age: a platform the team owns, and a ghost its hub builds mid-pause:
-- a steam engine (updatable, so its disabled_by_script shows the freeze), or
-- an accumulator if a steam engine does not fit.
STEPS["s3-platform-setup"] = function()
    local force = game.forces[storage.team]
    local planet = storage.fx.surface.planet and storage.fx.surface.planet.name or "nauvis"
    local plat = force.create_space_platform{ name = "tst-platform", planet = planet, starter_pack = "space-platform-starter-pack" }
    check("s3sa-platform-created", plat ~= nil, "planet=" .. planet)
    plat.apply_starter_pack()
    storage.plat = plat
    later(60, "s3-platform-ready")
end

STEPS["s3-platform-ready"] = function()
    local plat = storage.plat
    local hub = plat.hub
    check("s3sa-platform-hub", hub ~= nil and hub.valid, "state=" .. tostring(plat.state))
    local owner = mts("get_surface_owner", plat.surface.name)
    check("s3sa-platform-owned-by-team", owner == storage.team, plat.surface.name .. " owner=" .. tostring(owner))
    storage.plat_base_solar = plat.surface.solar_power_multiplier
    step("s3-platform-ready", plat.surface.name .. " solar_mult=" .. plat.surface.solar_power_multiplier)
end

STEPS["s3-platform-build"] = function()
    local plat = storage.plat
    local s = plat.surface
    check("s3sa-platform-solar-mult-zero", s.solar_power_multiplier == 0, "solar_power_multiplier=" .. s.solar_power_multiplier)
    -- The starter pack lays a 10 x 10 foundation around the 8 x 8 hub; lay a
    -- strip beside it, as a player would, so the ghost has room.
    local tiles = {}
    for x = 5, 12 do
        for y = -5, 4 do tiles[#tiles + 1] = { name = "space-platform-foundation", position = { x, y } } end
    end
    s.set_tiles(tiles)
    local pos, what
    for _, name in ipairs({ "steam-engine", "accumulator" }) do
        for r = 4, 14 do
            for _, d in ipairs({ { r, 0 }, { -r, 0 }, { 0, r }, { 0, -r }, { r, r }, { -r, -r } }) do
                local p = name == "steam-engine" and { x = d[1] + 0.5, y = d[2] + 0.5 } or { x = d[1], y = d[2] }
                if not pos and s.can_place_entity{ name = name, position = p, force = storage.team } then pos, what = p, name end
            end
        end
    end
    if not check("s3sa-platform-free-spot", pos ~= nil) then step("s3-platform-build"); return end
    plat.hub.get_inventory(defines.inventory.hub_main).insert{ name = what, count = 1 }
    local ghost = s.create_entity{ name = "entity-ghost", inner_name = what, position = pos, force = storage.team }
    check("s3sa-platform-ghost-placed", ghost ~= nil, string.format("%s at %.1f,%.1f", what, pos.x, pos.y))
    storage.expect_platform = true
    later(60 * 40, "platform-timeout")
    step("s3-platform-build")
end

STEPS["platform-timeout"] = function()
    if not storage.expect_platform then return end
    storage.expect_platform = nil
    check("s3-platform-built-frozen", false, "the hub did not build the ghost within 40 s (test setup)")
    step("built-platform")
end

-- ─── Scenario 4: a pause survives a mod update ──────────────────────────

STEPS["s4-pause"] = function()
    mark()
    storage.s4 = { team = storage.team }
    local r = mts("pause_team", storage.team)
    check("s4-old-mts-pause", r == true, tostring(r))
    expect_frozen("s4-before-update")
    step("s4-pause")
end

local function s4_on_config_changed(changes)
    local mc = changes.mod_changes and changes.mod_changes["multi-team-support"]
    if not (storage.s4 and mc and mc.old_version and mc.new_version) then return end
    mark()
    local paused = mts("is_team_paused", storage.team)
    check("s4-paused-in-config-changed", paused == true, "multi-team-support " .. mc.old_version .. " -> " .. mc.new_version
        .. ", is_team_paused=" .. tostring(paused))
    later(30, "s4-after-update")
end

STEPS["s4-after-update"] = function()
    expect_frozen("s4-after-update")
    expect_events("s4-no-resume-on-update", "resumed", 0)
    local r = mts("unpause_team", storage.team)
    check("s4-script-unpause-returns-true", r == true, tostring(r))
    expect_live("s4-after-script-unpause")
    expect_events("s4-resumed-once", "resumed", 1, "script")
    step("s4-after-update")
    log(TAG .. "DONE")
end

-- ─── Scenario 5: disband with and without quiet ─────────────────────────

local function disband(quiet)
    local tag = quiet and "s5-quiet" or "s5-plain"
    mark()
    storage.s5 = { team = storage.team, tag = tag }
    local p = game.get_player(storage.leader)
    check(tag .. "-member-before", p.force.name == storage.team, "force=" .. p.force.name)
    if quiet then mts("disband_team", storage.team, { quiet = true }) else mts("disband_team", storage.team) end
    later(90, "s5-check")
    step(tag .. "-called")
end
STEPS["s5-quiet"] = function() disband(true) end
STEPS["s5-plain"] = function() disband(false) end

STEPS["s5-check"] = function()
    local s5 = storage.s5
    local p = game.get_player(storage.leader)
    check(s5.tag .. "-player-in-pen", p.physical_surface.name == "landing-pen",
        "surface=" .. p.physical_surface.name .. " force=" .. p.force.name)
    check(s5.tag .. "-player-off-team", p.force.name ~= s5.team, "force=" .. p.force.name)
    local ok, frame = pcall(function() return p.gui.screen["sb_pen_frame"] end)
    check(s5.tag .. "-pen-gui-shown", ok and frame ~= nil and frame.valid)
    local info = mts("get_team_info", s5.team)
    check(s5.tag .. "-slot-free", info == nil or info.status == "available", "status=" .. tostring(info and info.status))
    local listed = false
    for _, t in ipairs(mts("get_team_list")) do
        if t.force_name == s5.team and t.is_occupied then listed = true end
    end
    check(s5.tag .. "-not-occupied-in-team-list", not listed)
    expect_events(s5.tag .. "-released-event", "released", 1)
    -- Going back to the pen switches the engine's death announcement off for
    -- that one kill; it must be on again afterwards.
    check(s5.tag .. "-death-announcements-restored", game.player_death_notifications_enabled == true)
    step(s5.tag .. "-checked")
end

-- ─── Scenario 6: dangOreus ──────────────────────────────────────────────

STEPS["s6-dangoreus"] = function()
    local f = storage.fx
    local s = f.surface
    check("s6-dangoreus-active", script.active_mods["dangOreus"] ~= nil, tostring(script.active_mods["dangOreus"]))
    local cx, cy = f.origin.x + 150, f.origin.y
    s.request_to_generate_chunks({ cx, cy }, 3)
    s.force_generate_chunk_requests()
    local ores = s.find_entities_filtered{ type = "resource", area = { { cx - 60, cy - 60 }, { cx + 60, cy + 60 } } }
    if not check("s6-ore-on-team-surface", #ores > 0, #ores .. " resource entities on " .. s.name) then step("s6-dangoreus"); return end
    -- Spots on ore, far apart, where the entity fits.
    local used = {}
    local function spot(name)
        for _, ore in ipairs(ores) do
            local p = ore.position
            local far = true
            for _, u in ipairs(used) do
                if math.abs(u.x - p.x) < 6 and math.abs(u.y - p.y) < 6 then far = false end
            end
            if far and s.can_place_entity{ name = name, position = p, force = storage.team } then
                used[#used + 1] = p
                return p
            end
        end
    end
    -- create_entity returns nil when the entity dies inside its own
    -- script_raised_built, so look at what stands there afterwards.
    local function build(name, pos)
        local e = s.create_entity{ name = name, position = pos, force = storage.team, raise_built = true }
        local there = s.find_entities_filtered{ name = name, area = { { pos.x - 0.1, pos.y - 0.1 }, { pos.x + 0.1, pos.y + 0.1 } } }
        return e, #there > 0
    end
    for _, case in ipairs({
        { "wooden-chest", false }, { "stone-furnace", false }, { "assembling-machine-1", false },
        { "burner-mining-drill", true }, { "electric-mining-drill", true },
    }) do
        local name, survives = case[1], case[2]
        local pos = spot(name)
        if check("s6-spot-" .. name, pos ~= nil) then
            local _, alive = build(name, pos)
            check(survives and ("s6-miner-on-ore-allowed-" .. name) or ("s6-non-miner-on-ore-blocked-" .. name),
                alive == survives, string.format("at %.1f,%.1f alive=%s", pos.x, pos.y, tostring(alive)))
        end
    end
    local _, alive = build("wooden-chest", offset(-2.5, 3.5))
    check("s6-chest-off-ore-allowed", alive == true, "alive=" .. tostring(alive))
    step("s6-dangoreus")
end

-- ─── Chat probe, admin, typed commands ──────────────────────────────────

script.on_event(defines.events.on_player_joined_game, function(e)
    local p = game.get_player(e.player_index)
    p.admin = true
    p.print("MTS_PROBE_PLAYER_PRINT")
    game.print("MTS_PROBE_GAME_PRINT")
    step("joined", p.name .. " index=" .. p.index .. " admin=" .. tostring(p.admin))
end)

script.on_event(defines.events.on_player_left_game, function(e)
    step("left", tostring(e.player_index))
end)

script.on_event(defines.events.on_console_command, function(e)
    local who = e.player_index and game.get_player(e.player_index)
    say("CMD", e.command, (e.parameters or "") .. " by " .. (who and who.name or "server"))
end)

script.on_event(defines.events.on_built_entity, function(e)
    if storage.expect ~= "hand" or not (e.entity and e.entity.valid) then return end
    storage.expect = nil
    record_build("hand", e.entity)
end)

script.on_event(defines.events.on_robot_built_entity, function(e)
    if not storage.expect_robot or not (e.entity and e.entity.valid) then return end
    storage.expect_robot = nil
    record_build("robot", e.entity)
end)

script.on_event(defines.events.on_space_platform_built_entity, function(e)
    if not storage.expect_platform or not (e.entity and e.entity.valid) then return end
    storage.expect_platform = nil
    record_build("platform", e.entity)
end)

script.on_event(defines.events.on_tick, function(e)
    local q = storage.queue
    if #q == 0 then return end
    local due, keep = {}, {}
    for _, item in ipairs(q) do
        if item.at <= e.tick then due[#due + 1] = item else keep[#keep + 1] = item end
    end
    if #due == 0 then return end
    storage.queue = keep
    for _, item in ipairs(due) do run(item.name, item.args) end
end)

commands.add_command("mtst", "dev test steps (mts-scenario-test)", function(c)
    local name, rest = (c.parameter or ""):match("^(%S+)%s*(.*)$")
    run(name or "", { arg = rest })
end)

script.on_init(function() init_storage(); subscribe() end)
script.on_load(subscribe)
script.on_configuration_changed(function(changes)
    init_storage()
    subscribe()
    s4_on_config_changed(changes)
end)
