-- tests/test_agent_manifest.lua
-- Headless tests for what the AI Agent Bridge reads about MTS's tools
-- before it calls one: the agent_tools_v1 manifest, the records sweep block
-- against the companion's rules, and the descs. Then the rules every tool
-- keeps: none writes storage, each refuses bad arguments the same way, and
-- the clock tools' replies. The world is tests/agent_world.lua.

local W = require("tests.agent_world")
local mock = W.mock

local H = W.H
local world, finish, call, refused = W.world, W.finish, W.call, W.refused
local whole_numbers, forces_of = W.whole_numbers, W.forces_of

local report, check, eq = W.new_report()

-- ─── the sweep block, against the companion's usable_spec ─────────────

-- The companion's rules (ai-agent-bridge companion-mod/scripts/sweep/
-- registry.lua, usable_spec, and axes.lua NAMES). A block failing them is
-- dropped quietly, so records_held would silently never exist.
local SWEEP_AXES = {force = true, surface = true, platform = true, player = true,
                    ["force+surface"] = true}

local function usable_spec(spec)
    if type(spec) ~= "table" then return false end
    if type(spec.axes) ~= "table" or #spec.axes == 0 then return false end
    for _, axis in ipairs(spec.axes) do
        if not SWEEP_AXES[axis] then return false end
    end
    if spec.default_axis ~= nil and not SWEEP_AXES[spec.default_axis] then return false end
    if type(spec.rows) ~= "string" then return false end
    if type(spec.name) ~= "string" and type(spec.name) ~= "table" then return false end
    return type(spec.value) == "string"
end

-- The bridge's param grammar (service/internal/catalog/params.go): a type
-- word, "!" for required, then the description.
local TYPE_WORDS = {string = true, integer = true, number = true, boolean = true,
                    ["list<string>"] = true, ["list<number>"] = true, ["list<point>"] = true}

local function type_word(line)
    local head = line:match("^(%S+)")
    local word = head and head:gsub("!$", "")
    if TYPE_WORDS[word] then return word end
    if word and word:match("^enum<[^>]*[^,%s>][^>]*>$") then return word end
    return nil
end

do
    world{teams = {[1] = {start = 0, name = "Ace"}, [2] = {start = H}, [3] = {start = 0}}}
    finish("tech", "a", 1, H)
    finish("tech", "b", 1, 2 * H)
    finish("tech", "b", 2, 2.5 * H)     -- 1.5h on its own clock: takes fastest
    finish("tech", "c", 3, 3 * H)
    game.tick = 4 * H

    local manifest = call("agent_tools_v1")
    eq("manifest: probe version", manifest.v, 1)
    for _, name in ipairs({"team_clock", "team_clocks", "records", "record_chase", "player_teams"}) do
        local entry = manifest.tools[name]
        check("manifest: lists " .. name, entry ~= nil and type(entry.desc) == "string")
        check("manifest: " .. name .. " is callable", remote.interfaces["mts-v1"][name] == true)
        for pname, line in pairs(entry and entry.params or {}) do
            check("manifest: " .. name .. "." .. pname .. " parses", type(line) == "string"
                and type_word(line) ~= nil, tostring(line))
        end
    end
    eq("manifest: kind is a closed vocabulary", type_word(manifest.tools.records.params.kind),
        "enum<tech,milestone,any>")
    eq("manifest: chase kind too", type_word(manifest.tools.record_chase.params.kind),
        "enum<tech,milestone,any>")
    eq("manifest: held_only is a boolean", type_word(manifest.tools.records.params.held_only), "boolean")
    check("manifest: player is required", manifest.tools.player_teams.params.player:match("^string! ") ~= nil)
    check("manifest: force is never declared, the bridge injects it",
        manifest.tools.records.params.force == nil and manifest.tools.player_teams.params.force == nil)

    local spec = manifest.tools.records.sweep
    check("sweep: the block is usable", usable_spec(spec))
    eq("sweep: metric name", spec.metric, "records_held")
    eq("sweep: unit", spec.unit, "records")
    eq("sweep: ranks by held", spec.value, "held")
    check("sweep: asks for every team", spec.args and spec.args.all == true)
    check("sweep: in the lean rows that fit every team", spec.args and spec.args.held_only == true)

    -- What the companion's foreign_metric.read does with it.
    local args = {force = "team-2"}
    for k, v in pairs(spec.args or {}) do args[k] = v end
    local r = call("records", args)
    local rows = r[spec.rows]
    check("sweep: the rows field holds rows", type(rows) == "table" and #rows == 3)
    check("sweep: never a cut reply, which it refuses", not (r.total and r.shown and r.shown < r.total))
    local by_force = {}
    for _, row in ipairs(rows or {}) do by_force[row[spec.name]] = tonumber(row[spec.value]) end
    eq("sweep: names cells by force, value is held", by_force["team-1"], 2)
    eq("sweep: a fastest-only holder counts, first would read 0", by_force["team-2"], 1)
    eq("sweep: every team", by_force["team-3"], 1)
end

-- ─── the descs say what the model cannot know ─────────────────────────

do
    world{teams = {}}
    local tools = call("agent_tools_v1").tools
    local rec, chase, teams = tools.records.desc, tools.record_chase.desc, tools.player_teams.desc
    check("desc: a record is first or fastest", rec:find("first or fastest", 1, true) ~= nil)
    check("desc: per technology and milestone", rec:find("technology", 1, true) and rec:find("milestone", 1, true))
    check("desc: on the team's own clock since it started playing",
        rec:find("own clock since it started playing", 1, true) ~= nil)
    check("desc: never game time", rec:find("never game time", 1, true) ~= nil)
    check("desc: records says a first-only milestone has no fastest",
        rec:find("counts first only has no fastest", 1, true) ~= nil)
    check("desc: chase says a first-only milestone is never in reach",
        chase:find("counts first only is never in reach", 1, true) ~= nil)
    check("desc: team_clock says when a Staged Start clock starts",
        tools.team_clock.desc:find("Start Playing", 1, true) ~= nil)
    -- Under Staged Start the clock starts at Start Playing, not at the claim.
    for name, entry in pairs(tools) do
        local d = entry.desc:lower()
        check("desc: " .. name .. " never says the clock runs since the claim",
            not (d:find("since claim", 1, true) or d:find("since it claimed", 1, true)
                 or d:find("since the slot was claimed", 1, true)), entry.desc)
    end
    check("desc: a player's records are their team's", rec:find("current team's", 1, true) ~= nil)
    check("desc: a disbanded team's are gone", rec:find("disbanded team's", 1, true) ~= nil)
    check("desc: chase says equal is out", chase:find("Equal is out", 1, true) ~= nil)
    check("desc: counting starts at counting_since_tick", teams:find("counting_since_tick", 1, true) ~= nil)
    check("desc: and may miss earlier restarts", teams:find("may miss earlier", 1, true) ~= nil)
    check("desc: says what had_team_at_start means", teams:find("had_team_at_start", 1, true) ~= nil)
    check("desc: team_clocks says what a short reply left out",
        tools.team_clocks.desc:find("shown can be under total", 1, true) ~= nil)
    for name, entry in pairs(tools) do
        check("desc: no em-dash in " .. name, entry.desc:find("\226\128\148", 1, true) == nil)
    end
end

-- ─── the tools never write storage ────────────────────────────────────

do
    world{teams = {[1] = {start = 0}, [2] = {start = 0}}}
    finish("tech", "a", 1, H)
    finish("tech", "a", 2, 2 * H)
    game.tick = 3 * H
    mock.add_live_player{name = "Eagle34", force = "team-1"}
    local before = mock.to_json(storage)
    call("records", {force = "team-1"})
    call("records", {all = true})
    call("records", {all = true, held_only = true})
    call("record_chase", {force = "team-2"})
    call("team_clocks", {})
    call("player_teams", {player = "Eagle34"})
    call("player_teams", {player = "nobody"})
    eq("pure: storage unchanged by every tool", mock.to_json(storage), before)
    check("pure: player_teams did not start counting", storage.player_team_history == nil)
end

-- ─── arguments and refusals ───────────────────────────────────────────

do
    world{teams = {[1] = {start = 0}}}
    local nt = call("records", {force = "spectator"})
    check("args: a non-team force is not found", nt.found == false)
    eq("args: with the reason team_clock gives", nt.reason,
        "not a team force; teams are named team-1, team-2 and so on")
    check("args: an unclaimed slot is not found", call("record_chase", {force = "team-7"}).found == false)
    eq("args: records needs force", refused("records", {}), "force is required")
    eq("args: record_chase needs force", refused("record_chase", {}), "force is required")
    eq("args: kind is checked", refused("records", {force = "team-1", kind = "bogus"}),
        "kind must be tech, milestone or any")
    eq("args: chase kind is checked", refused("record_chase", {force = "team-1", kind = "x"}),
        "kind must be tech, milestone or any")
    check("args: all=true needs no force", call("records", {all = true}).total == 1)
    eq("args: player_teams needs a player", refused("player_teams", {force = "team-1"}), "player is required")
end

-- ─── the clock tools ──────────────────────────────────────────────────

do
    world{tick = 10 * H, teams = {[1] = {start = 8.5 * H, name = "Ace"}}}
    storage.team_online_ticks["team-1"] = H / 4
    local r = call("team_clock", {force = "Team Ace"})
    eq("team_clock: resolves a label", r.force, "team-1")
    eq("team_clock: elapsed hours", r.elapsed_hours, "1.5")
    eq("team_clock: online hours", r.online_hours, "0.25")
    eq("team_clock: one team in full keeps its label", r.label, "Team Ace")
    eq("team_clock: and its raw ticks", r.elapsed_ticks, 1.5 * H)
    eq("team_clock: the tick its clock started", r.clock_start_tick, 8.5 * H)
    check("team_clock: no claimed_tick, a name that was wrong under Staged Start", r.claimed_tick == nil)
    eq("team_clock: refusal unchanged", call("team_clock", {force = "nope"}).reason,
        "not a team force; teams are named team-1, team-2 and so on")
    eq("team_clocks: one row per claimed team", call("team_clocks", {}).total, 1)
end

do
    world{tick = 10 * H, teams = {[1] = {start = 0, name = "Ace"}, [2] = {start = 2 * H},
                                  [3] = {start = 4 * H}, [4] = {start = nil}}}
    storage.team_online_ticks["team-1"] = H
    storage.team_online_ticks["team-2"] = 3 * H
    storage.team_online_ticks["team-3"] = H                -- ties team-1: slot order
    storage.paused_forces = {["team-2"] = true}
    local r = call("team_clocks", {})
    eq("team_clocks: most online time first, slot breaks a tie", forces_of(r.teams),
        "team-2,team-1,team-3,team-4")
    eq("team_clocks: total", r.total, 4)
    eq("team_clocks: shown", r.shown, 4)
    local first = r.teams[1]
    eq("team_clocks: online hours", first.online_hours, 3)
    eq("team_clocks: elapsed hours", first.elapsed_hours, 8)
    check("team_clocks: a paused team says so", first.paused == true)
    check("team_clocks: a running team leaves paused out", r.teams[2].paused == nil)
    local keys = {}
    for key in pairs(r.teams[2]) do keys[#keys + 1] = key end
    table.sort(keys)
    -- No label (the bridge prints force names as labels), no raw ticks.
    eq("team_clocks: a row is what a comparison needs", table.concat(keys, ","),
        "elapsed_hours,force,members,online_hours")
    check("team_clocks: a staged team has no elapsed yet", r.teams[4].elapsed_hours == nil)
    check("team_clocks: no double leaks", whole_numbers(r))
end

return report
