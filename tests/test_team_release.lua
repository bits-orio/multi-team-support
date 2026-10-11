-- tests/test_team_release.lua
-- Headless tests for who is still on a team when a member leaves or its slot
-- is released. A member watching another team sits on the spectator force,
-- and one who was spectating when the server went down stays there offline
-- until they reconnect, when spectator puts them back on their team. Both
-- still belong to it: a leave must not disband the team under them, and a
-- release must take them off it, or they land on whichever team claims the
-- slot next, inside its private chat. Slots go through the real team_slots
-- and team_teardown, the chat scope through the real mts-v1 interface. The
-- world is tests/agent_world.lua.

local W = require("tests.agent_world")
local mock = W.mock

local report, check, eq = W.new_report()

--- A connected player on `force`. The mock builds its connected list once,
--- so a player added later joins it here.
local function online(name, force)
    local p = mock.add_live_player{name = name, force = force, connected = true}
    game.connected_players[#game.connected_players + 1] = p
    return p
end

local function go_offline(p)
    rawset(p, "connected", false)
    for i, q in ipairs(game.connected_players) do
        if q == p then table.remove(game.connected_players, i) break end
    end
end

--- What spectator.on_player_joined does for a player still spectating.
local function reconnect(p)
    rawset(p, "connected", true)
    game.connected_players[#game.connected_players + 1] = p
    require("scripts.spectator").exit(p)
end

--- The player watches another team, then the server goes down: no
--- on_player_left_game, so they stay offline on the spectator force.
local function spectating_at_crash(p, force_name)
    storage.spectator_real_force[p.index] = force_name
    p.force = "spectator"
    go_offline(p)
end

local function team_only(force_name)
    storage.chat_channel = storage.chat_channel or {}
    storage.chat_channel[force_name] = "local"
end

local function scope(player)
    return remote.call("mts-v1", "chat_scope_v1", player.index, "status?")
end

local function audience(s)
    return table.concat((s.audience or {}).players or {}, ",")
end

--- Two members on team-1, claimed at tick 1000, team-only chat.
local function pair()
    W.world{max_teams = 4, tick = 1000}
    local team_slots = require("scripts.team_slots")
    local ace, bee = online("Ace"), online("Bee")
    team_slots.claim_team_slot(ace)
    bee.force = "team-1"
    team_only("team-1")
    storage.spawned_players = {[ace.index] = true, [bee.index] = true}
    return team_slots, ace, bee
end

-- ─── the last member online leaves: the team goes on ──────────────────

do
    local team_slots, ace, bee = pair()
    local key = scope(ace).key
    spectating_at_crash(bee, "team-1")

    game.tick = 5000
    team_slots.remove_from_team(ace)
    eq("leave: the team goes on under its offline spectator", storage.team_pool[1], "occupied")
    eq("leave: who leads it now", storage.team_leader["team-1"], bee.index)
    eq("leave: Ace is off it", ace.force.name, "spectator")
    eq("leave: Bee is still spectating it, to come back to it",
        storage.spectator_real_force[bee.index], "team-1")
    eq("leave: Bee is not moved while offline", bee.force.name, "spectator")

    reconnect(bee)
    eq("reconnect: Bee is back on the team", bee.force.name, "team-1")
    eq("reconnect: asking under the team's own key", scope(bee).key, key)
    local cat = online("Cat")
    eq("reconnect: a stranger's claim takes another slot", team_slots.claim_team_slot(cat), "team-2")
end

do
    -- Online and watching another team: the same, and the lead passes.
    local team_slots, ace, bee = pair()
    storage.spectator_real_force[bee.index] = "team-1"
    bee.force = "spectator"
    team_slots.remove_from_team(ace)
    eq("leave: a member watching away online keeps the team", storage.team_pool[1], "occupied")
    eq("leave: and leads it", storage.team_leader["team-1"], bee.index)
end

do
    -- A stale spectate entry for a member already back on the force is the
    -- same member again. Counted twice, a team of one would never disband.
    W.world{max_teams = 4, tick = 1000}
    local team_slots = require("scripts.team_slots")
    local solo = online("Solo")
    team_slots.claim_team_slot(solo)
    storage.spectator_real_force[solo.index] = "team-1"
    team_slots.remove_from_team(solo)
    eq("count: a stale entry is not a second member", storage.team_pool[1], "available")
end

do
    -- An entry whose player is no longer valid is nobody: a team of one
    -- with it still disbands.
    W.world{max_teams = 4, tick = 1000}
    local team_slots = require("scripts.team_slots")
    local solo, ghost = online("Solo"), online("Ghost")
    team_slots.claim_team_slot(solo)
    storage.spectator_real_force[ghost.index] = "team-1"
    rawset(ghost, "valid", false)
    team_slots.remove_from_team(solo)
    eq("count: an invalid player's entry is not a member", storage.team_pool[1], "available")
end

-- ─── a release takes everyone still tied to the slot ──────────────────

do
    local team_slots, ace, bee = pair()
    local dot = online("Dot", "team-1")
    storage.spawned_players[dot.index] = true
    spectating_at_crash(bee, "team-1")
    -- No path releases a slot with members on it today. If one ever does,
    -- the release itself takes them off.
    ace.force = "spectator"
    team_slots.release_team_slot("team-1")
    eq("release: the offline spectator no longer watches for the team",
        storage.spectator_real_force[bee.index], nil)
    eq("release: and is on the spectator force", bee.force.name, "spectator")
    check("release: they land in the pen when they reconnect", storage.spawned_players[bee.index] == nil)
    eq("release: a member online on the force is off it", dot.force.name, "spectator")
    check("release: and back in the pen now", (storage.penned or {})[dot.index] == true)
    eq("release: and told", #dot.printed, 1)
    eq("release: nobody is left on the force", #game.forces["team-1"].players, 0)

    game.tick = 9000
    local cat = online("Cat")
    eq("reclaim: strangers get the slot", team_slots.claim_team_slot(cat), "team-1")
    team_only("team-1")
    reconnect(bee)
    eq("reclaim: Bee is not on the new team", bee.force.name, "spectator")
    eq("reclaim: Bee asks in the global scope", scope(bee).key, "global")
    eq("reclaim: the new team hears only itself", audience(scope(cat)), tostring(cat.index))
end

do
    -- Without control.lua's wiring (a harness), a release with someone left
    -- on the slot still runs: an error in a handler would stop the server.
    local team_slots, ace = pair()
    team_slots.set_evict_hook(nil)
    ace.force = "spectator"
    check("unwired: the release does not error", pcall(team_slots.release_team_slot, "team-1"))
    eq("unwired: the slot is released", storage.team_pool[1], "available")
end

do
    -- A slot past the 64-force cap has no force: nobody can be on it.
    W.world{max_teams = 4, tick = 1000}
    local team_slots = require("scripts.team_slots")
    game.forces["team-4"] = nil
    check("no force: releasing its slot does not error", pcall(team_slots.release_team_slot, "team-4"))
end

-- ─── the reaper's teardown, through the real release ──────────────────

do
    local team_slots, ace, bee = pair()
    -- team_teardown releases through force_utils: here the real team_slots.
    local force_utils = package.loaded["scripts.force_utils"]
    force_utils.cleanup_force_surfaces = function() return {} end
    force_utils.release_team_slot = team_slots.release_team_slot
    go_offline(ace)
    spectating_at_crash(bee, "team-1")

    local ok = require("scripts.team_teardown").teardown("team-1", {inactive = true})
    check("reaper: the teardown runs", ok)
    eq("reaper: the slot is free", storage.team_pool[1], "available")
    eq("reaper: the offline spectator is on the spectator force", bee.force.name, "spectator")
    eq("reaper: and no longer watches for the team", storage.spectator_real_force[bee.index], nil)
    check("reaper: they land in the pen when they reconnect", storage.spawned_players[bee.index] == nil)
    check("reaper: and are told why then", (storage.reaper_notice or {})[bee.index] == true)

    local cat = online("Cat")
    eq("reaper: strangers get the slot", team_slots.claim_team_slot(cat), "team-1")
    team_only("team-1")
    reconnect(bee)
    eq("reaper: Bee never joins the next team in the slot", bee.force.name, "spectator")
    eq("reaper: Bee asks in the global scope", scope(bee).key, "global")
end

-- ─── control.lua hands the release teardown's rule ────────────────────

do
    -- control.lua pulls in the whole mod, so this one is read, not run.
    -- The repo root is the first entry tests/run.py put on package.path.
    local root = package.path:match("^([^;]+)/%?%.lua")
    local f = assert(io.open(root .. "/control.lua", "r"))
    local text = f:read("*a")
    f:close()
    local body = text:match("^(.-)script%.on_init") or ""
    check("wiring: at parse time, before any handler",
        body:find('require("scripts.team_slots").set_evict_hook(require("scripts.team_teardown").evict)',
            1, true) ~= nil)
end

return report
