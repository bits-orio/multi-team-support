-- tests/agent_world.lua
-- The world the agent tool tests run in: the mocked engine, stubs for every
-- module the tools' callers pull in, and the real modules under test loaded
-- fresh against it. Fixtures are written through the real scripts/records.lua
-- and slots are claimed and released through the real team_slots, so storage
-- holds exactly what the game would. Every tool is called through the real
-- mts-v1 interface, whose mock remote.call copies like the engine's.

local mock = require("tests.mock_factorio")

local M = {}

M.mock = mock
M.H = mock.TICKS_PER_HOUR

--- A pass/fail tally for one test file, and the check and eq that feed it.
function M.new_report()
    local report = {passed = 0, failed = 0, failures = {}}
    local function check(name, ok, detail)
        if ok then
            report.passed = report.passed + 1
        else
            report.failed = report.failed + 1
            report.failures[#report.failures + 1] = name .. (detail and ("  -> " .. detail) or "")
        end
    end
    local function eq(name, actual, expected)
        check(name, actual == expected,
            "expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
    return report, check, eq
end

local function noop() end

-- Modules a case loads for real. Dropped before every world, so each is
-- required fresh against that world's storage and stubs.
local FRESH = {
    "scripts.helpers", "scripts.records", "scripts.remote_api",
    "scripts.agent_tools.reply", "scripts.agent_tools.team_lookup",
    "scripts.agent_tools.records_read", "scripts.agent_tools.records",
    "scripts.agent_tools.record_chase", "scripts.player_team_history",
    "scripts.team_slots", "events.player_force", "events.player_removed",
    "scripts.team_incarnation", "milestones.external_keys", "milestones.engine",
    "milestones.config", "scripts.team_teardown",
}

local function stub(name, value) package.loaded[name] = value end

--- The real spectator's rules for leaving spectate: exit puts the player
--- back on their real force before it forgets it, as restore_player_state
--- then clear_spectator_storage do, and exit_all_for_force does that for
--- every member watching away from the force, connected or not.
local function spectator_stub()
    local real = function(p) return storage.spectator_real_force[p.index] end
    local function exit(p)
        local force_name = real(p)
        if not force_name then return end
        p.force = force_name
        storage.spectator_real_force[p.index] = nil
    end
    local function exit_all_for_force(force_name)
        local hits = {}
        for idx, fn in pairs(storage.spectator_real_force) do
            if fn == force_name then hits[#hits + 1] = idx end
        end
        for _, idx in ipairs(hits) do exit(game.get_player(idx)) end
    end
    return {
        get_real_force      = real,
        get_effective_force = function(p) return real(p) or p.force.name end,
        is_spectating       = function(p) return real(p) ~= nil end,
        setup_force = noop, exit = exit, exit_all_for_force = exit_all_for_force,
    }
end

--- Everything remote_api, team_slots and the two event modules require,
--- other than the modules under test.
local function install_stubs()
    local helpers = require("scripts.helpers")
    stub("scripts.spectator", spectator_stub())
    stub("scripts.team_clock", {
        -- Raw: nil stands in for an entry written before online time existed.
        online_ticks = function(fn) return storage.team_online_ticks[fn] end,
        on_claim = noop, on_release = noop, refresh = noop,
    })
    stub("scripts.surface_utils", {get_owner = noop, represented_planet = noop})
    stub("scripts.spawn_labels", {set_enabled = noop, refresh_for_force = noop})
    stub("scripts.pop_text", {milestone = noop, global_milestone = noop, rip = noop})
    -- The real module's team-scope rule: a team's chat is team-only when
    -- storage.chat_channel says "local" for the player's real team.
    stub("scripts.chat_channel", {
        on_release = noop,
        is_local_for = function(p)
            local team = (storage.spectator_real_force or {})[p.index] or p.force.name
            return (storage.chat_channel or {})[team] == "local"
        end,
    })
    stub("scripts.chat_tag", {GLOBAL_BADGE = "[G]", LOCAL_BADGE = "[T]"})
    stub("scripts.pause.control", {pause_team = noop, unpause_team = noop})
    stub("scripts.pause.state", {set_paused = noop, is_paused = noop})
    -- Required by remote_api on the factorio-2.1 line only. Stubbed here as
    -- well, so this file is the same on both branches.
    stub("scripts.pause.notify", {show = noop, clear = noop})
    stub("scripts.team_pins", {on_team_left = noop, on_team_joined = noop})
    stub("scripts.planet_map", {apply_force_locks = noop})
    stub("gui.friendship", {break_all_for = noop})
    stub("scripts.team_modifiers", {
        on_release = noop,
        is_marked = function(fn) return (storage.team_noncompetitive or {})[fn] == true end,
        ls_records_tag = function() return "" end,
    })
    stub("scripts.buddy_store", {clear_for_team = function() return {} end, clear = noop})
    stub("gui.pen_info_panel", {chart_for = noop})
    stub("scripts.starter_scope", {clear_team_kit = noop})
    stub("gui.team_settings", {refresh_nav_button = noop, build_gui = noop})
    stub("scripts.force_utils", {is_team_force = helpers.is_team_force})
    stub("gui.admin", {refresh_nav_button = noop})
    stub("gui.hud_clock", {update_player = noop})
    stub("gui.follow_cam", {on_player_left = noop})
    -- What team_teardown's evict calls: a pen return is recorded, not run.
    stub("gui.landing_pen", {
        return_to_pen = function(p)
            storage.penned = storage.penned or {}
            storage.penned[p.index] = true
        end,
        update_pen_gui_all = noop,
    })
    stub("gui.teams", {update_all = noop})
end

--- A fresh world. spec.teams = { [slot] = { start = tick, name = "Ace" } }
--- claims those slots with their clocks started at `start` (nil: a staged
--- team still waiting on Start Playing). Loads the real mts-v1 interface.
function M.world(spec)
    for _, name in ipairs(FRESH) do package.loaded[name] = nil end
    local max = spec.max_teams or 8
    mock.build{tick = spec.tick or 0, max_teams = max, teams = {}}
    mock.install_engine{max_teams = max}
    for _, name in ipairs({"player", "enemy", "neutral"}) do
        game.forces[name] = mock.make_force(name, {})
    end
    storage.team_clock_start, storage.team_leader = {}, {}
    storage.tech_records, storage.milestone_records = {}, {}
    for slot = 1, max do
        storage.team_names["team-" .. slot] = string.format("Team %02d", slot)
    end
    for slot, team in pairs(spec.teams or {}) do
        local fn = "team-" .. slot
        storage.team_pool[slot] = "occupied"
        storage.team_clock_start[fn] = team.start
        if team.name then storage.team_names[fn] = team.name end
    end
    install_stubs()
    require("scripts.remote_api")
    -- control.lua's parse-time wiring: a release evicts with teardown's rule.
    require("scripts.team_slots").set_evict_hook(require("scripts.team_teardown").evict)
end

--- Finishes a record through the real records.update at `tick`, so the
--- stored shape (first, fastest, entries, elapsed on the team's own clock)
--- is what the game writes. `online` is the team's online ticks then.
function M.finish(kind, key, slot, tick, online)
    local fn = "team-" .. slot
    game.tick = tick
    storage.team_online_ticks[fn] = online
    local tbl = kind == "tech" and storage.tech_records or storage.milestone_records
    require("scripts.records").update(tbl, key, fn, tick)
end

function M.call(fn, args) return remote.call("mts-v1", fn, args) end

--- The error a call raised, or nil when it returned.
function M.refused(fn, args)
    local ok, err = pcall(remote.call, "mts-v1", fn, args)
    return not ok and tostring(err) or nil
end

--- Bytes of JSON the bridge's service measures for a reply.
function M.size(r) return #mock.to_json(r) end

--- True when every number in v is whole: a double that leaked would leave
--- as fifty digits on the engine's JSON writer.
function M.whole_numbers(v)
    if type(v) == "number" then return v == math.floor(v) end
    if type(v) ~= "table" then return true end
    for _, x in pairs(v) do
        if not M.whole_numbers(x) then return false end
    end
    return true
end

function M.whats(rows)
    local out = {}
    for i, r in ipairs(rows) do out[i] = r.what end
    return table.concat(out, ",")
end

function M.by_what(rows, what)
    for _, r in ipairs(rows) do
        if r.what == what then return r end
    end
end

function M.forces_of(teams)
    local out = {}
    for i, t in ipairs(teams) do out[i] = t.force end
    return table.concat(out, ",")
end

return M
