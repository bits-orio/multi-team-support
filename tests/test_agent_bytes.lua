-- tests/test_agent_bytes.lua
-- Every agent tool reply has to reach the model as whole JSON. AI Agent
-- Bridge's service cuts a tool result past 4096 bytes (its
-- DefaultMaxToolResultBytes) and its companion refuses one past 8000, so
-- these cases grow each reply until reply.fit has to cut it, and check what
-- survives. The biggest server MTS can run is 60 teams, each named with the
-- 16 bytes a team name may have.

local W = require("tests.agent_world")
local mock = W.mock

local H = W.H
local world, finish, call, size = W.world, W.finish, W.call, W.size
local whole_numbers = W.whole_numbers

local report, check, eq = W.new_report()

local SERVICE_CUT = 4096
local BUDGET = 3900

-- ─── one team with many rows ──────────────────────────────────────────

do
    local N = 300
    world{teams = {[1] = {start = 0}, [2] = {start = 0}}}
    for i = 1, N do
        finish("tech", string.format("an-unusually-long-technology-name-for-testing-%03d", i),
               1, i * H + 1234, i * H / 3)
    end
    storage.team_clock_start["team-2"] = (N + 1) * H - 1   -- a clock just started
    game.tick = (N + 1) * H

    local wide = call("records", {force = "team-1", limit = 100})
    check("rows: a wide reply stays inside the budget", size(wide) <= BUDGET, "size " .. size(wide))
    check("rows: the cut is by bytes, below the limit", wide.shown < 100, "shown " .. wide.shown)
    eq("rows: shown matches the rows sent", #wide.rows, wide.shown)
    eq("rows: total is every held record", wide.total, N)
    eq("rows: newest survive the cut", wide.rows[1].what,
        string.format("an-unusually-long-technology-name-for-testing-%03d", N))
    check("rows: the counts survive the cut", wide.held == N and wide.finished == N)
    check("rows: no double leaks", whole_numbers(wide))
    eq("rows: the default limit still fits whole", call("records", {force = "team-1"}).shown, 20)

    local chase = call("record_chase", {force = "team-2", limit = 100})
    check("rows: chase stays inside the budget", size(chase) <= BUDGET, "size " .. size(chase))
    check("rows: chase cut by bytes", chase.shown < 100, "shown " .. chase.shown)
    eq("rows: chase total", chase.total, N)
    eq("rows: chase keeps the soonest", chase.rows[1].what,
        "an-unusually-long-technology-name-for-testing-001")
    eq("rows: chase counts survive the cut", chase.in_reach, N)
end

-- ─── 60 teams with long names ─────────────────────────────────────────

-- What the companion's sweep does with a provider's reply (ai-agent-bridge
-- companion-mod/scripts/sweep/registry.lua, foreign_metric's read): refuse
-- a reply showing fewer rows than its total, else one cell per row.
local function sweep_read(spec, r)
    if r.total and r.shown and r.shown < r.total then
        return nil, "showed " .. r.shown .. " of " .. r.total .. " rows"
    end
    local cells = {}
    for _, row in ipairs(r[spec.rows] or {}) do
        local value = tonumber(row[spec.value])
        if row[spec.name] and value then cells[#cells + 1] = {name = row[spec.name], value = value} end
    end
    return cells
end

local TEAMS, TECHS = 60, 150

--- 60 claimed teams with 16-byte names, every one finishing 150 techs, so
--- finished is three digits on every row. Each tech is finished in tick
--- order, which is the order records.update has to see, and the finishing
--- order and the clock starts both shuffle by slot, so first and fastest
--- spread across teams the way a long-running server's do.
local function big_server()
    local teams = {}
    for slot = 1, TEAMS do
        teams[slot] = {start = (slot * 13 % TEAMS) * 5, name = string.format("Longest Name %03d", slot)}
    end
    world{max_teams = TEAMS, teams = teams}
    for k = 1, TECHS do
        local function tick_of(slot) return 200000 + k * 1000 + ((slot * 37 + k * 11) % TEAMS) * 10 end
        local order = {}
        for slot = 1, TEAMS do order[slot] = slot end
        table.sort(order, function(a, b) return tick_of(a) < tick_of(b) end)
        for _, slot in ipairs(order) do
            finish("tech", "technology-number-" .. k, slot, tick_of(slot), tick_of(slot) / 3)
        end
    end
    for slot = 1, TEAMS do
        storage.team_online_ticks["team-" .. slot] = 1000000 + slot * 7777
    end
    game.tick = 50000000
end

do
    big_server()
    local full = call("records", {all = true})
    check("60 teams: the full table stays inside the budget", size(full) <= BUDGET, "size " .. size(full))
    eq("60 teams: the full table counts every team", full.total, TEAMS)
    eq("60 teams: shown matches the rows sent", #full.teams, full.shown)
    check("60 teams: a cut full table keeps the most held", full.teams[1].held >= full.teams[#full.teams].held)

    local spec = call("agent_tools_v1").tools.records.sweep
    local args = {force = "team-1"}
    for k, v in pairs(spec.args) do args[k] = v end
    local lean = call("records", args)
    eq("60 teams: the sweep's rows show every team", lean.shown, TEAMS)
    check("60 teams: with room to spare", size(lean) <= BUDGET / 2, "size " .. size(lean))
    local cells, refusal = sweep_read(spec, lean)
    check("60 teams: the sweep takes the reply", cells ~= nil, refusal)
    eq("60 teams: one cell per team", cells and #cells, TEAMS)
    eq("60 teams: the leader is the full table's leader", cells and cells[1].name, full.teams[1].force)

    local one = call("records", {force = "team-60"})
    check("60 teams: one team's reply fits", size(one) <= BUDGET, "size " .. size(one))
    eq("60 teams: and keeps its long label", one.label, "Team Longest Name 060")
    local chase = call("record_chase", {force = "team-60"})
    check("60 teams: chase fits", size(chase) <= BUDGET, "size " .. size(chase))

    local clocks = call("team_clocks", {})
    check("60 teams: team_clocks fits", size(clocks) <= BUDGET, "size " .. size(clocks))
    eq("60 teams: team_clocks counts every team", clocks.total, TEAMS)
    eq("60 teams: team_clocks shown matches its rows", #clocks.teams, clocks.shown)
    eq("60 teams: the most online team survives the cut", clocks.teams[1].force, "team-60")
end

-- A full table that does not fit is cut, and the sweep would refuse it: the
-- reason the sweep asks for held_only rows.
do
    big_server()
    local full = call("records", {all = true})
    if full.shown < full.total then
        check("past the budget: the sweep refuses a cut table", sweep_read({rows = "teams", name = "force",
            value = "held"}, full) == nil)
    else
        check("past the budget: the fixture is meant to overflow the full table", false,
            "size " .. size(full) .. " with every team shown")
    end
end

-- ─── reply.fit, reply.limit, reply.hours ──────────────────────────────

do
    world{teams = {}}
    local reply = require("scripts.agent_tools.reply")
    eq("budget: the one this file checks", reply.BUDGET, BUDGET)
    check("budget: under the service's cut", reply.BUDGET < SERVICE_CUT and reply.SERVICE_CUT == SERVICE_CUT)
    -- The service cuts the reply itself, the `r` inside the companion's
    -- { ok = true, r = ... }, so that is what a reply is measured as.
    eq("size: the reply alone, as the service measures it", reply.size({a = 1}), #'{"a":1}')
    eq("limit: missing is the default", reply.limit(nil, 20, 100), 20)
    eq("limit: not a number is the default", reply.limit("x", 20, 100), 20)
    eq("limit: clamped to the max", reply.limit(500, 20, 100), 100)
    eq("limit: at least one", reply.limit(0, 20, 100), 1)
    eq("limit: whole rows", reply.limit(3.7, 20, 100), 3)
    local built = reply.fit({}, function(shown) return {rows = shown, shown = #shown} end)
    eq("fit: no rows is still a reply", built.shown, 0)
    local huge = string.rep("x", 9000)
    local over = reply.fit({1, 2, 3}, function(shown) return {pad = huge, rows = shown} end)
    eq("fit: when nothing fits it sends no rows rather than loop", #over.rows, 0)
    -- Measured as the service measures it, the whole reply, and as many rows
    -- as that allows: one more would pass the budget.
    local rows = {}
    for i = 1, 100 do rows[i] = string.rep(string.char(96 + i % 26), 100) end
    local function build(shown) return {note = string.rep("n", 300), rows = shown, shown = #shown} end
    local fitted = reply.fit(rows, build)
    check("fit: within the budget", size(fitted) <= BUDGET, "size " .. size(fitted))
    check("fit: as many rows as fit", size(build(reply.cut(rows, fitted.shown + 1))) > BUDGET,
        "shown " .. fitted.shown)
    -- Many widths, so the search has to land on many different cut points.
    local widths_ok = true
    for width = 60, 140, 7 do
        local wide = {}
        for i = 1, 150 do wide[i] = string.rep("w", width) end
        local got = reply.fit(wide, build)
        local tight = size(got) <= BUDGET and size(build(reply.cut(wide, got.shown + 1))) > BUDGET
        if not tight then widths_ok = false end
    end
    check("fit: the most rows that fit, at every width", widths_ok)
    eq("hours: nil stays nil", reply.hours(nil), nil)
    eq("hours: whole is a number", reply.hours(2 * H), 2)
    eq("hours: two places as a short string", reply.hours(H * 1.79), "1.79")
    eq("hours: trailing zero dropped", reply.hours(H * 1.5), "1.5")
end

-- ─── caller text a reply repeats back ─────────────────────────────────

--- True when s is whole UTF-8: no character cut short at the end.
local function ends_whole(s)
    local i, n = 1, #s
    while i <= n do
        local b = s:byte(i)
        local len = b < 0x80 and 1 or b >= 0xF0 and 4 or b >= 0xE0 and 3 or b >= 0xC0 and 2 or 0
        if len == 0 or i + len - 1 > n then return false end
        i = i + len
    end
    return true
end

do
    world{teams = {[1] = {start = 0}}}
    local reply = require("scripts.agent_tools.reply")
    local long = string.rep("team-x", 2000)
    for _, tool in ipairs({"records", "record_chase", "team_clock"}) do
        local r = call(tool, {force = long})
        check("echo: " .. tool .. " refuses a long name inside the budget", r.found == false
            and size(r) <= BUDGET, "size " .. size(r))
        check("echo: " .. tool .. " repeats at most ECHO_BYTES of it", #r.force <= reply.ECHO_BYTES,
            "bytes " .. #r.force)
    end
    eq("echo: a short name comes back whole", call("records", {force = "team-9"}).force, "team-9")
    -- 63 bytes of ASCII, then a 3-byte character across the 64-byte line.
    -- Details print lengths: a clipped string may not be printable.
    local accented = string.rep("a", 63) .. "\226\130\172" .. "tail"
    local clipped = reply.echo(accented)
    check("echo: a character across the line is left out whole", clipped == string.rep("a", 63),
        "bytes " .. #clipped)
    local doubled = reply.echo(string.rep("\195\169", 100))
    check("echo: what is left is whole UTF-8", ends_whole(doubled) and #doubled == 64, "bytes " .. #doubled)
    eq("echo: a string at the limit is kept", reply.echo(string.rep("b", 64)), string.rep("b", 64))
    eq("echo: not a string is left alone", reply.echo(42), 42)

    mock.add_live_player{name = "Eagle34"}
    local who = call("player_teams", {player = long})
    check("echo: player_teams refuses a long name inside the budget", size(who) <= BUDGET, "size " .. size(who))
    check("echo: and repeats at most ECHO_BYTES of it", #who.player <= reply.ECHO_BYTES)
end

do
    -- Twelve players whose names all contain "a", long enough that ten of
    -- them would pass the budget.
    world{teams = {}}
    for i = 1, 12 do
        mock.add_live_player{name = string.format("a%02d", i) .. string.rep("z", 450)}
    end
    local r = call("player_teams", {player = "a"})
    check("candidates: an ambiguous name is not guessed", r.found == false)
    check("candidates: the list stays inside the budget", size(r) <= BUDGET, "size " .. size(r))
    eq("candidates: total is every match", r.total, 12)
    eq("candidates: shown matches the names sent", #r.candidates, r.shown)
    check("candidates: cut by bytes", r.shown < 10, "shown " .. tostring(r.shown))
end

return report
