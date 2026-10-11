-- tests/test_chat_scope.lua
-- Headless tests for chat_scope_v1, the probe AI Agent Bridge asks who may
-- hear a reply. Its key must name the team in a slot, not only the slot:
-- MTS reuses slots, and the bridge keeps private chat under that key for
-- longer than a team lasts. Slots are claimed and released through the real
-- team_slots, and the probe is called through the real mts-v1 interface.
-- The world is tests/agent_world.lua.

local W = require("tests.agent_world")
local mock = W.mock

local world = W.world

local report, check, eq = W.new_report()

--- A connected player on `force`. The mock builds its connected list once,
--- so a player added later joins it here.
local function online(name, force)
    local p = mock.add_live_player{name = name, force = force, connected = true}
    game.connected_players[#game.connected_players + 1] = p
    return p
end

local function scope(player, text)
    return remote.call("mts-v1", "chat_scope_v1", player.index, text or "how far along are we?")
end

--- A team switched to team-only chat, as chat_channel stores it.
local function team_only(force_name)
    storage.chat_channel = storage.chat_channel or {}
    storage.chat_channel[force_name] = "local"
end

local function audience(s)
    return table.concat((s.audience or {}).players or {}, ",")
end

-- ─── a claim, then the next team in the same slot ─────────────────────

do
    world{max_teams = 4, tick = 1000}
    local team_slots = require("scripts.team_slots")
    local ace, mate = online("Ace"), online("Mate")
    eq("claim: through the real team_slots", team_slots.claim_team_slot(ace), "team-1")
    mate.force = "team-1"
    team_only("team-1")

    local first = scope(ace)
    check("scope: team-only chat is private", first.private == true)
    eq("scope: the key is the force and the tick its team claimed it", first.key, "team-1@1000")
    eq("scope: the label is unchanged, the team's name", first.label, "Team 01")
    eq("scope: the tag is unchanged, the team badge", first.tag, "[T]")
    eq("scope: the audience is unchanged, the connected members",
        audience(first), ace.index .. "," .. mate.index)
    eq("scope: a teammate asks under the same key", scope(mate).key, "team-1@1000")
    game.tick = 9000
    eq("scope: the key does not move with the clock", scope(ace).key, "team-1@1000")

    -- The team disbands and new people claim the slot: same force name.
    ace.force, mate.force = "spectator", "spectator"
    team_slots.release_team_slot("team-1")
    check("release: the claim tick leaves with the team", storage.team_claimed_tick["team-1"] == nil)
    game.tick = 20000
    local next_lead = online("Next")
    eq("reclaim: the same slot", team_slots.claim_team_slot(next_lead), "team-1")
    team_only("team-1")
    local second = scope(next_lead)
    eq("reclaim: the next team has its own key", second.key, "team-1@20000")
    check("reclaim: never the key of the team before it", second.key ~= first.key)
    eq("reclaim: the old members are not its audience", audience(second), tostring(next_lead.index))
end

-- ─── the channel decides private or global, as before ─────────────────

do
    world{max_teams = 4, tick = 500}
    local team_slots = require("scripts.team_slots")
    local ace, bee = online("Ace"), online("Bee")
    team_slots.claim_team_slot(ace)
    game.tick = 700
    team_slots.claim_team_slot(bee)
    team_only("team-1")
    team_only("team-2")
    eq("two teams: each has its own key", scope(bee).key, "team-2@700")
    check("two teams: and its own audience", audience(scope(bee)) == tostring(bee.index))

    local shout = scope(ace, "!anyone out there?")
    eq("shout: a leading ! is global", shout.key, "global")
    check("shout: and not private", shout.private == false)
    eq("shout: with the global badge", shout.tag, "[G]")

    storage.chat_channel["team-1"] = nil
    eq("global chat: global", scope(ace).key, "global")

    local pen = online("Pen")
    eq("pen: a player with no team is global", scope(pen).key, "global")

    -- A member watching another team sits on the spectator force but is
    -- still on their team: same key, and they hear the reply.
    local spy = online("Spy")
    spy.force = "team-2"
    storage.spectator_real_force[spy.index] = "team-2"
    spy.force = "spectator"
    eq("spectating: a member watching away asks under the team's key", scope(spy).key, "team-2@700")
    eq("spectating: and is in the team's audience", audience(scope(bee)), bee.index .. "," .. spy.index)

    eq("home force: a member watching away is about their own team",
        remote.call("mts-v1", "home_force_v1", spy.index), "team-2")
    eq("home force: a player on their team is about it", remote.call("mts-v1", "home_force_v1", ace.index), "team-1")
    eq("home force: a pen player is about their own force", remote.call("mts-v1", "home_force_v1", pen.index), pen.force.name)
    check("home force: an unknown index is nobody", remote.call("mts-v1", "home_force_v1", 99) == nil)

    check("args: a non-number index is nobody", remote.call("mts-v1", "chat_scope_v1", "Ace", "hi") == nil)
    check("args: an unknown index is nobody", remote.call("mts-v1", "chat_scope_v1", 99, "hi") == nil)
end

-- ─── Staged Start: the claim names the team, not the clock ────────────

do
    world{max_teams = 4, tick = 3000}
    local team_slots = require("scripts.team_slots")
    local lead = online("Lead")
    team_slots.claim_team_slot(lead, {skip_clock = true})
    team_only("team-1")
    check("staged: the clock waits for Start Playing", storage.team_clock_start["team-1"] == nil)
    eq("staged: the key is the claim's all the same", scope(lead).key, "team-1@3000")
    game.tick = 7000
    storage.team_clock_start["team-1"] = 7000      -- what pre_start.commit writes
    eq("staged: Start Playing does not change the key", scope(lead).key, "team-1@3000")
end

-- ─── a team that held its slot when the save updated ──────────────────

do
    world{max_teams = 4, tick = 50000, teams = {[1] = {start = 0}}}
    local team_slots = require("scripts.team_slots")
    local incarnation = require("scripts.team_incarnation")
    storage.team_slot_generation[1] = 2        -- the slot changed hands twice before
    local old = online("Old", "team-1")
    team_only("team-1")

    local before = mock.to_json(storage)
    eq("legacy: a build that skipped the update reads the slot's generation",
        scope(old).key, "team-1@legacy-g2")
    eq("legacy: the probe writes nothing", mock.to_json(storage), before)

    incarnation.on_configuration_changed()
    eq("legacy: the update gives the team a key of its own", scope(old).key, "team-1@legacy-g2-t50000")
    check("legacy: never the bare force name earlier chat was filed under", scope(old).key ~= "team-1")
    check("legacy: never one constant every legacy team shares", scope(old).key ~= "team-1@legacy")
    game.tick = 55000
    incarnation.on_configuration_changed()     -- a later update
    eq("legacy: a later update keeps it", scope(old).key, "team-1@legacy-g2-t50000")

    old.force = "spectator"
    team_slots.release_team_slot("team-1")
    check("legacy: release drops it", storage.team_claimed_tick["team-1"] == nil)
    game.tick = 60000
    local new = online("New")
    eq("legacy: the slot comes back", team_slots.claim_team_slot(new), "team-1")
    team_only("team-1")
    eq("legacy: the next team has a tick", scope(new).key, "team-1@60000")
    eq("legacy: a claim keeps the generation it was made in",
        storage.team_claimed_tick["team-1"].generation, 3)

    incarnation.on_configuration_changed()     -- a later update
    eq("update: a claimed team keeps its tick", scope(new).key, "team-1@60000")
end

-- ─── two saves from before the update, a different team in each ───────

do
    -- The bridge keeps one history for every save of a map, so two saves
    -- that each had another team in team-4 before claims were recorded must
    -- not come out of the update with one key.
    local function updated(tick, generation, name)
        world{max_teams = 4, tick = tick, teams = {[4] = {start = 0}}}
        storage.team_slot_generation[4] = generation
        local p = online(name, "team-4")
        team_only("team-4")
        require("scripts.team_incarnation").on_configuration_changed()
        return scope(p).key
    end
    local first = updated(70000, 1, "Ace")
    eq("saves: the first save's team", first, "team-4@legacy-g1-t70000")
    check("saves: the second save's team has a key of its own", updated(90000, 2, "Bee") ~= first)
    -- A map older than slot generations (0.4.61) reads 0 for every slot.
    check("saves: the update's tick keeps them apart at one generation",
        updated(70000, 0, "Ace") ~= updated(90000, 0, "Bee"))
end

-- ─── a downgrade and back: an entry left behind is never inherited ────

do
    world{max_teams = 4, tick = 150000}
    local team_slots = require("scripts.team_slots")
    local incarnation = require("scripts.team_incarnation")
    local d, gone = online("D"), online("Gone")
    eq("downgrade: D claims", team_slots.claim_team_slot(d), "team-1")
    eq("downgrade: Gone claims", team_slots.claim_team_slot(gone), "team-2")
    team_only("team-1")
    local d_key = scope(d).key
    eq("downgrade: D's key", d_key, "team-1@150000")

    -- An older MTS runs. Its release bumps the slot's generation but leaves
    -- the entry, and its claim writes none: D leaves and E claims team-1,
    -- Gone leaves team-2 and nobody claims it.
    local function old_release(p, slot)
        p.force = "spectator"
        storage.team_pool[slot] = "available"
        storage.team_slot_generation[slot] = storage.team_slot_generation[slot] + 1
    end
    old_release(d, 1)
    old_release(gone, 2)
    game.tick = 200000
    local e = online("E")
    e.force = "team-1"
    storage.team_pool[1] = "occupied"
    storage.team_leader["team-1"] = e.index
    check("downgrade: D's entry is still there", storage.team_claimed_tick["team-1"] ~= nil)
    check("downgrade: E never gets D's key, even before the update",
        scope(e).key ~= d_key, scope(e).key)

    game.tick = 210000
    incarnation.on_configuration_changed()     -- back on this release
    eq("downgrade: the update gives E a key of its own", scope(e).key, "team-1@legacy-g1-t210000")
    check("downgrade: the entry a free slot was left with is dropped",
        storage.team_claimed_tick["team-2"] == nil)
end

-- ─── a bare tick, from a build before generations ─────────────────────

do
    world{max_teams = 4, tick = 80000, teams = {[2] = {start = 0}}}
    storage.team_claimed_tick = {["team-2"] = 61000, ["team-3"] = 62000}
    local p = online("P", "team-2")
    team_only("team-2")
    check("bare tick: not trusted, it cannot say which team it names",
        scope(p).key ~= "team-2@61000", scope(p).key)
    require("scripts.team_incarnation").on_configuration_changed()
    eq("bare tick: the update replaces it", scope(p).key, "team-2@legacy-g0-t80000")
    check("bare tick: a free slot's is dropped", storage.team_claimed_tick["team-3"] == nil)
end

-- ─── a released slot has no team, and no team key ─────────────────────

do
    world{max_teams = 4, tick = 1000}
    local team_slots = require("scripts.team_slots")
    local ace = online("Ace")
    team_slots.claim_team_slot(ace)
    ace.force = "spectator"
    team_slots.release_team_slot("team-1")

    -- An admin's console move onto the free slot, with a team-only channel
    -- (individual chat scope keeps a player's own across a release).
    local stray = online("Stray")
    stray.force = "team-1"
    team_only("team-1")
    local free = scope(stray)
    eq("free slot: a player on a released slot is global", free.key, "global")
    check("free slot: not private", free.private == false)
    check("free slot: with no audience", free.audience == nil)

    local never = online("Never")
    never.force = "team-3"
    team_only("team-3")
    eq("free slot: one never claimed is global too", scope(never).key, "global")
end

-- ─── control.lua makes the table on init and on update ────────────────

do
    -- control.lua pulls in the whole mod, so this one is read, not run.
    -- The repo root is the first entry tests/run.py put on package.path.
    local root = package.path:match("^([^;]+)/%?%.lua")
    local f = assert(io.open(root .. "/control.lua", "r"))
    local text = f:read("*a")
    f:close()
    local on_init = text:match("script%.on_init%(function%(%)(.-)\nend%)")
    local on_changed = text:match("script%.on_configuration_changed%(function%(%)(.-)\nend%)")
    check("init: on_init makes the table",
        (on_init or ""):find("team_incarnation.init_storage()", 1, true) ~= nil)
    check("init: on_configuration_changed reconciles it on an older save",
        (on_changed or ""):find("team_incarnation.on_configuration_changed()", 1, true) ~= nil)
    -- After the tables it reads: team_pool and team_slot_generation.
    local pool_at = (on_changed or ""):find("storage.team_slot_generation", 1, true)
    local reconcile_at = (on_changed or ""):find("team_incarnation.on_configuration_changed()", 1, true)
    check("init: after the slot tables are made", pool_at and reconcile_at and pool_at < reconcile_at)
end

return report
