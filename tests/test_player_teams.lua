-- tests/test_player_teams.lua
-- Headless tests for player_teams and the claim and join counter behind it
-- (scripts/player_team_history.lua): counting through the real team_slots
-- and the real on_player_changed_force handler, the snapshot of who already
-- had a team when counting began, and the storage lifecycle around it.

local W = require("tests.agent_world")
local mock = W.mock

local H = W.H
local world, call = W.world, W.call

local report, check, eq = W.new_report()

--- One counter of a player's history row, 0 when there is no row, so a
--- broken counter fails a check instead of stopping the whole file.
local function counted(player, field)
    return ((storage.player_team_history or {})[player.index] or {})[field] or 0
end

--- Whether the snapshot marked this player as already on a team.
local function marked(player)
    return ((storage.player_team_history or {})[player.index] or {}).had_team_at_start == true
end

-- ─── counting through the real claim and force change ─────────────────

do
    world{max_teams = 4, tick = 500}
    require("events.player_force").register()
    local team_slots = require("scripts.team_slots")
    local eagle = mock.add_live_player{name = "Eagle34"}
    local rune  = mock.add_live_player{name = "RuneBoggler"}
    local pen   = mock.add_live_player{name = "Penny"}

    local fresh = call("player_teams", {player = "Eagle34"})
    check("history: a player is found before counting starts", fresh.found == true)
    check("history: counting has not started", fresh.counting == false)
    check("history: and no tick is claimed for it", fresh.counting_since_tick == nil)
    eq("history: no claims yet", fresh.claims, 0)
    check("history: a player in the pen is on no team", fresh.force == nil, tostring(fresh.force))
    check("history: nobody had a team before counting began", fresh.had_team_at_start == nil)

    -- Lazy start: no on_init in this world, so the first claim creates the table.
    game.tick = 1000
    eq("history: claim through the real team_slots", team_slots.claim_team_slot(eagle), "team-1")
    eq("history: the leader is on the team", eagle.force.name, "team-1")
    local one = call("player_teams", {player = "Eagle34"})
    eq("history: a claim counts", one.claims, 1)
    eq("history: the leader's own join is not joining others", one.joined_others, 0)
    eq("history: the first claim is not a restart", one.restarts, 0)
    eq("history: counting began at the first write", one.counting_since_tick, 1000)
    check("history: and says it is counting", one.counting == true)
    eq("history: the team the player is on", one.force, "team-1")
    check("history: a claim from the pen is not a team at start", one.had_team_at_start == nil)

    -- A spectate hop is not a join.
    storage.spectator_real_force[eagle.index] = "team-1"
    eagle.force = "spectator"
    eagle.force = "team-1"
    storage.spectator_real_force[eagle.index] = nil
    eq("history: spectating and coming back is not a join", counted(eagle, "joins"), 1)

    -- Leave and release the slot: the count survives.
    eagle.force = "spectator"
    team_slots.release_team_slot("team-1")
    eq("history: survives the slot's release", call("player_teams", {player = "Eagle34"}).claims, 1)

    game.tick = 5000
    team_slots.claim_team_slot(eagle)
    local two = call("player_teams", {player = "eagle34"})
    eq("history: a name in any case finds the player", two.player, "Eagle34")
    eq("history: a second claim", two.claims, 2)
    eq("history: is one restart", two.restarts, 1)
    eq("history: counting still runs from the first tick", two.counting_since_tick, 1000)

    game.tick = 6000
    eq("history: another player claims", team_slots.claim_team_slot(rune), "team-2")
    eagle.force = "spectator"
    eagle.force = "team-2"
    local three = call("player_teams", {player = "Eagle"})
    eq("history: a unique part of a name is enough", three.player, "Eagle34")
    eq("history: joining someone else's team", three.joined_others, 1)
    eq("history: is not a restart", three.restarts, 1)
    eq("history: force follows the player", three.force, "team-2")
    eq("history: 5000 ticks of counting, as hours", three.counting_for_hours, "0.02")

    -- A pen spectator accepted into a team really did join: their real
    -- force is the spectator force, not the team they land on.
    storage.spectator_real_force[pen.index] = "spectator"
    pen.force = "team-2"
    storage.spectator_real_force[pen.index] = nil
    eq("history: a pen spectator taken in is a join", call("player_teams", {player = "Penny"}).joined_others, 1)

    -- An event naming the force the player is already on moved nobody.
    local penny_joins = counted(pen, "joins")
    require("scripts.player_team_history").on_player_changed_force(
        {player_index = pen.index, force = game.forces["team-2"]})
    eq("history: a change to the same force is not a join",
        counted(pen, "joins"), penny_joins)

    -- The old force was merged away: reading it must not error.
    local gone = setmetatable({valid = false}, {__index = function(_, key)
        error("LuaForce API call when LuaForce was invalid: " .. tostring(key), 0)
    end})
    local ok = pcall(require("scripts.player_team_history").on_player_changed_force,
        {player_index = rune.index, force = gone})
    check("history: an invalid old force is not read", ok)

    -- An old save updating: a force change can arrive before spectator
    -- storage exists. Counting must not stop the server over it.
    local saved = storage.spectator_real_force
    storage.spectator_real_force = nil
    local joins_before = counted(pen, "joins")
    pen.force = "spectator"
    local no_table_ok = pcall(function() pen.force = "team-2" end)
    check("history: no spectator storage yet is not an error", no_table_ok)
    eq("history: and the join still counts", counted(pen, "joins"), joins_before + 1)
    eq("history: the tool reads the plain force then",
        call("player_teams", {player = "Penny"}).force, "team-2")
    storage.spectator_real_force = saved

    local again = storage.player_team_history_since
    require("scripts.player_team_history").init_storage()
    eq("history: init keeps the first tick", storage.player_team_history_since, again)
    eq("history: init keeps the counts", counted(eagle, "claims"), 2)
    check("history: init takes no second snapshot", not marked(eagle) and not marked(pen))

    local many = call("player_teams", {player = "e"})
    check("history: an ambiguous name is not guessed", many.found == false)
    eq("history: it lists who it could be", table.concat(many.candidates or {}, ","),
        "Eagle34,Penny,RuneBoggler")
    local nobody = call("player_teams", {player = "zz"})
    check("history: an unknown name is not found", nobody.found == false and nobody.candidates == nil)

    -- A removed player's index can be reused: the history must go with it.
    rune.force = "spectator"
    require("events.player_removed").register()
    script.handlers[defines.events.on_pre_player_removed]({player_index = rune.index})
    check("history: a removed player's row is dropped", storage.player_team_history[rune.index] == nil)
    check("history: nobody else's", storage.player_team_history[eagle.index] ~= nil)
end

do
    world{tick = 100}
    local history = require("scripts.player_team_history")
    history.init_storage()
    local rune  = mock.add_live_player{name = "RuneBoggler"}
    local short = mock.add_live_player{name = "Rune"}
    eq("names: the same name in any case beats a longer match", call("player_teams", {player = "rune"}).player,
        "Rune")
    eq("names: the exact name first", call("player_teams", {player = "RuneBoggler"}).player, "RuneBoggler")
    -- A claim whose join the counter never saw (the leader's force change
    -- fired before it shipped) must not read as a negative join.
    storage.player_team_history[short.index] = {claims = 2, joins = 1}
    eq("history: joined_others never goes below zero",
        call("player_teams", {player = "Rune"}).joined_others, 0)
    check("history: unrelated player untouched", storage.player_team_history[rune.index] == nil)
end

do
    world{tick = 4100000}
    local history = require("scripts.player_team_history")
    history.init_storage()
    mock.add_live_player{name = "Eagle34"}
    local r = call("player_teams", {player = "Eagle34"})
    eq("history: a fresh table reports when counting began", r.counting_since_tick, 4100000)
    eq("history: zero hours ago", r.counting_for_hours, 0)
    game.tick = 4100000 + 3 * H
    eq("history: and how long it has run", call("player_teams", {player = "Eagle34"}).counting_for_hours, 3)
end

-- ─── who already had a team when counting began ───────────────────────

do
    -- A live save taking the update: teams are already played, and
    -- on_configuration_changed starts counting.
    world{max_teams = 4, tick = 9000, teams = {[1] = {start = 0}, [2] = {start = 0}}}
    require("events.player_force").register()
    local team_slots = require("scripts.team_slots")
    local lead = mock.add_live_player{name = "Lead", force = "team-1"}
    local mate = mock.add_live_player{name = "Mate", force = "team-2"}
    local pen  = mock.add_live_player{name = "Pen"}
    local spy  = mock.add_live_player{name = "Spy"}
    storage.spectator_real_force[spy.index] = "team-1"   -- a member watching another team

    require("scripts.player_team_history").init_storage()
    check("start: a leader on a team is marked", marked(lead))
    check("start: a member is marked", marked(mate))
    check("start: a member spectating away from their team is marked", marked(spy))
    check("start: a player in the pen is not", not marked(pen))
    eq("start: a mark is not a claim", counted(lead, "claims"), 0)

    local before = call("player_teams", {player = "Lead"})
    check("start: player_teams reports it", before.had_team_at_start == true)
    eq("start: no claim yet is no restart", before.restarts, 0)
    check("start: a player without one reports nothing", call("player_teams", {player = "Pen"})
        .had_team_at_start == nil)

    -- Lead starts over: leaves, the slot is released, and they claim again.
    lead.force = "spectator"
    team_slots.release_team_slot("team-1")
    game.tick = 10000
    team_slots.claim_team_slot(lead)
    local over = call("player_teams", {player = "Lead"})
    eq("start: the first counted claim", over.claims, 1)
    eq("start: is a restart for a player who had a team", over.restarts, 1)
    eq("start: and is still not joining others", over.joined_others, 0)

    team_slots.claim_team_slot(pen)
    local first = call("player_teams", {player = "Pen"})
    eq("start: a player from the pen claims", first.claims, 1)
    eq("start: their first claim is no restart", first.restarts, 0)

    local lead_team = lead.force.name
    lead.force = "spectator"
    team_slots.release_team_slot(lead_team)
    team_slots.claim_team_slot(lead)
    eq("start: each later claim adds one", call("player_teams", {player = "Lead"}).restarts, 2)

    local late = mock.add_live_player{name = "Late"}
    late.force = "team-2"
    check("start: someone joining after counting began is not marked", not marked(late))
    eq("start: their join counts", counted(late, "joins"), 1)
end

do
    -- No table yet, and the first event counted is a join. The engine has
    -- already moved the player, so the force they left decides for them.
    world{max_teams = 4, tick = 700, teams = {[1] = {start = 0}, [2] = {start = 0}}}
    require("events.player_force").register()
    local vet   = mock.add_live_player{name = "Vet", force = "team-2"}
    local fresh = mock.add_live_player{name = "Fresh"}
    fresh.force = "team-1"
    check("lazy join: the table starts with the join", storage.player_team_history ~= nil)
    eq("lazy join: counting began then", storage.player_team_history_since, 700)
    eq("lazy join: the join counts", counted(fresh, "joins"), 1)
    check("lazy join: a player from the pen is not marked by the team they just joined", not marked(fresh))
    check("lazy join: everyone else on a team is marked", marked(vet))
end

do
    world{max_teams = 4, tick = 700, teams = {[1] = {start = 0}, [2] = {start = 0}}}
    require("events.player_force").register()
    local mover = mock.add_live_player{name = "Mover", force = "team-2"}
    mover.force = "team-1"
    check("lazy move: a player moved from one team to another had a team", marked(mover))
    eq("lazy move: and the move is a join", counted(mover, "joins"), 1)
end

do
    -- No table yet, and the first event counted is a claim: team_slots
    -- counts it before the leader leaves the pen.
    world{max_teams = 4, tick = 800, teams = {[2] = {start = 0}}}
    require("events.player_force").register()
    local vet = mock.add_live_player{name = "Vet", force = "team-2"}
    local founder = mock.add_live_player{name = "Founder"}
    require("scripts.team_slots").claim_team_slot(founder)
    check("lazy claim: the claimer from the pen is not marked", not marked(founder))
    check("lazy claim: a player already on a team is", marked(vet))
    eq("lazy claim: the claim is no restart", call("player_teams", {player = "Founder"}).restarts, 0)
end

do
    -- A new map: on_init runs before anyone joins, so nobody is marked.
    world{tick = 0}
    require("scripts.player_team_history").init_storage()
    eq("new map: counting begins at tick 0", storage.player_team_history_since, 0)
    check("new map: an empty table", next(storage.player_team_history) == nil)
end

-- ─── the caveat travels in the reply ──────────────────────────────────

--- The reply's note, or "" so a missing one fails a find instead of erroring.
local function note(name)
    return call("player_teams", {player = name}).note or ""
end

local function has(text, part) return text:find(part, 1, true) ~= nil end

do
    world{tick = 500}
    mock.add_live_player{name = "Early"}
    check("note: before counting starts, the zeros are not a count", has(note("Early"), "not a count"),
        note("Early"))
    check("note: none on a reply that found nobody", call("player_teams", {player = "zz"}).note == nil)
end

do
    -- The rig's case: counting began at this load, and the player's team
    -- had been playing long before it.
    world{max_teams = 4, tick = 400 * H, teams = {[1] = {start = 100 * H}}}
    mock.add_live_player{name = "Vet", force = "team-1"}
    require("scripts.player_team_history").init_storage()
    game.tick = 400 * H + H / 2
    eq("note: zero restarts counted", call("player_teams", {player = "Vet"}).restarts, 0)
    local text = note("Vet")
    check("note: says counting began after the player had a team", has(text, "already had a team"), text)
    check("note: and how long ago", has(text, "0.5 hours ago"), text)
    check("note: and to give counts since then", has(text, "not as totals"), text)
end

do
    -- Marked at the start, now on a team newer than the count, counting a
    -- week old: only the mark says earlier restarts are missing.
    world{max_teams = 4, tick = 100 * H, teams = {[1] = {start = 10 * H}}}
    local team_slots = require("scripts.team_slots")
    local vet = mock.add_live_player{name = "Vet", force = "team-1"}
    require("scripts.player_team_history").init_storage()
    vet.force = "spectator"
    team_slots.release_team_slot("team-1")
    game.tick = 268 * H
    team_slots.claim_team_slot(vet)
    check("note: a player on a team when counting began", has(note("Vet"), "already had a team"), note("Vet"))
end

do
    -- Counting a week old; a player who joined after it began, onto a team
    -- playing since before it.
    world{max_teams = 4, tick = 100 * H, teams = {[1] = {start = 10 * H}}}
    require("scripts.player_team_history").init_storage()
    game.tick = 268 * H
    local late = mock.add_live_player{name = "Late"}
    late.force = "team-1"
    check("note: a team older than the count", has(note("Late"), "after this player's team was formed"),
        note("Late"))
end

do
    world{max_teams = 4, tick = 100 * H}
    require("scripts.player_team_history").init_storage()
    game.tick = 110 * H
    local new = mock.add_live_player{name = "New"}
    require("scripts.team_slots").claim_team_slot(new)
    check("note: a count under a day old", has(note("New"), "only 10 hours ago"), note("New"))
    game.tick = 125 * H
    eq("note: none once it is a day old, with nothing older about the player", note("New"), "")
end

do
    world{max_teams = 4, tick = 0}
    require("scripts.player_team_history").init_storage()
    game.tick = 2 * H
    local first = mock.add_live_player{name = "First"}
    require("scripts.team_slots").claim_team_slot(first)
    eq("note: none on a count that began with the map", note("First"), "")
end

-- ─── control.lua starts the counter on init and on update ─────────────

do
    -- control.lua pulls in the whole mod, so this one is read, not run.
    -- The repo root is the first entry tests/run.py put on package.path.
    local root = package.path:match("^([^;]+)/%?%.lua")
    local f = assert(io.open(root .. "/control.lua", "r"))
    local text = f:read("*a")
    f:close()
    local on_init = text:match("script%.on_init%(function%(%)(.-)\nend%)")
    local on_changed = text:match("script%.on_configuration_changed%(function%(%)(.-)\nend%)")
    check("init: on_init found", on_init ~= nil)
    check("init: on_configuration_changed found", on_changed ~= nil)
    check("init: on_init starts counting",
        (on_init or ""):find("player_team_history.init_storage()", 1, true) ~= nil)
    check("init: on_configuration_changed starts counting",
        (on_changed or ""):find("player_team_history.init_storage()", 1, true) ~= nil)
end

return report
