-- Multi-Team Support - scripts/player_team_history.lua
-- Author: bits-orio
-- License: MIT
--
-- How often each player claimed a new team or joined someone else's, and
-- the `player_teams` agent tool that reads it. Nothing else counts restarts:
-- storage.left_teams marks the teams a player left, but releasing a slot
-- clears it. This table is never cleared on release.
--
-- Storage, created once and never reset:
--   storage.player_team_history[player_index] =
--       { claims = n, joins = n, had_team_at_start = true or nil }
--   storage.player_team_history_since = the tick the table was created,
--       which is when counting began; nothing before it was recorded.
--
-- had_team_at_start marks a player who was on a team when the table was
-- created. On a save older than the counter, "claims after the first" would
-- call that player's next claim their first, though they are starting over.
--
-- A claim's leader fires a join too (team_slots counts the claim, then puts
-- the leader on the force), so joins into someone else's team are joins
-- minus claims. Written only from event handlers, which run identically on
-- every peer; the tool only reads. Created lazily on the write paths as well
-- as in on_init and on_configuration_changed, because a dev build reloaded
-- without a version change never runs on_configuration_changed.

local helpers   = require("scripts.helpers")
local spectator = require("scripts.spectator")
local reply     = require("scripts.agent_tools.reply")

local MAX_CANDIDATES = 10

-- A count younger than this is too young to read as a total, even for a
-- player with nothing else to show they played before it began: a day.
local RECENT_TICKS = 24 * 60 * 60 * 60

-- The caveats a reply carries in `note`, where the model reads them with the
-- numbers. A desc alone was not enough: asked on a server where counting had
-- begun at that load, the model answered "restarted 0 times".
local NOT_COUNTING = "Restarts are not counted on this server yet, so these zeros are not a count."
local BEGAN = {
    had_team = "Counting began %s hours ago, when this player already had a team.",
    old_team = "Counting began %s hours ago, after this player's team was formed.",
    recent   = "Counting began only %s hours ago.",
}
local UNRECORDED = " Earlier restarts were not recorded: give these as counts since then, not as totals."

local M = {}

M.manifest = {
    desc = "How many times one player started a new team (claims) or joined someone else's "
        .. "(joined_others). restarts is claims after the first; joining another team is not a restart. "
        .. "Counting began at counting_since_tick, counting_for_hours ago, and nothing before it was "
        .. "recorded: say the count runs from then and may miss earlier restarts. had_team_at_start=true "
        .. "means the player was already on a team then, so their first counted claim is a restart too. "
        .. "counting=false means it has not started. force is the player's team now. "
        .. "note, when present, says why the count may not be complete: pass it on.",
    params = {
        player = "string! the player's name; a unique part of it is enough",
    },
}

--- spectator's own rules, behind a guard: they index spectator storage
--- directly, and this runs on every force change, so on an old save updating
--- it can run before spectator.init_storage has made that table. An error in
--- an event handler stops a multiplayer server.
local function real_force(player)
    if not storage.spectator_real_force then return nil end
    return spectator.get_real_force(player)
end

local function effective_force(player)
    if not storage.spectator_real_force then return player.force.name end
    return spectator.get_effective_force(player)
end

--- Marks every player on a team right now, a member watching another team
--- from the spectator force included. `moved` = { index, left } is a player
--- whose force change is being counted as the table is created: the engine
--- has already moved them, so the force they left decides for them.
local function snapshot(moved)
    for _, player in pairs(game.players) do
        local had = helpers.is_team_force(effective_force(player))
        if moved and player.index == moved.index then had = helpers.is_team_force(moved.left) end
        if had then
            storage.player_team_history[player.index] = { claims = 0, joins = 0, had_team_at_start = true }
        end
    end
end

--- Creates the table the first time, with who was on a team at that moment;
--- its creation tick is when counting began. `moved` as in snapshot.
function M.init_storage(moved)
    if storage.player_team_history then return end
    storage.player_team_history = {}
    storage.player_team_history_since = game.tick
    snapshot(moved)
end

local function bump(player_index, field, moved)
    M.init_storage(moved)
    local row = storage.player_team_history[player_index]
    if not row then
        row = { claims = 0, joins = 0 }
        storage.player_team_history[player_index] = row
    end
    row[field] = row[field] + 1
end

--- A claim: called by team_slots.claim_team_slot beside raise_team_created,
--- before the leader is moved onto the new force.
function M.on_claim(player_index)
    bump(player_index, "claims")
end

--- A member coming back from spectating: spectator.lua parks them on the
--- "spectator" force and restores them while spectator_real_force still
--- names their team. That is not a join, and counting it would turn every
--- spectate into one.
local function is_spectate_return(player, old_name, new_name)
    return old_name == "spectator" and real_force(player) == new_name
end

--- A move onto a team: called from the on_player_changed_force handler,
--- beside the mts-v1 on_player_joined_team raise.
function M.on_player_changed_force(event)
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end
    local new_name = player.force.name
    if not helpers.is_team_force(new_name) then return end
    local old = event.force
    local old_name = old and old.valid and old.name or nil
    if old_name == new_name or is_spectate_return(player, old_name, new_name) then return end
    bump(event.player_index, "joins", { index = event.player_index, left = old_name })
end

--- The player a caller named: the exact name, the same name in any case, or
--- the one name containing it. Otherwise nil and every name it could mean.
local function find_player(text)
    local ok, exact = pcall(function() return game.get_player(text) end)
    if ok and exact and exact.valid then return exact end
    local wanted, hits = text:lower(), {}
    for _, p in pairs(game.players) do
        local name = p.name:lower()
        if name == wanted then return p end
        if name:find(wanted, 1, true) then hits[#hits + 1] = p.name end
    end
    if #hits == 1 then return game.get_player(hits[1]) end
    table.sort(hits)
    return nil, hits
end

local function not_found(text, hits)
    local asked = reply.echo(text)
    if #hits == 0 then
        return { found = false, player = asked, reason = "no player by that name" }
    end
    return reply.fit(reply.cut(hits, MAX_CANDIDATES), function(shown)
        return { found = false, player = asked, total = #hits, shown = #shown, candidates = shown,
                 reason = "more than one player matches; ask again with one of candidates" }
    end)
end

--- Claims after the first, or every claim for a player who already had a
--- team when counting began.
local function restarts(row)
    local claims = row.claims or 0
    if row.had_team_at_start then return claims end
    return math.max(0, claims - 1)
end

--- Whether the player's team now was playing before counting began: its
--- own clock started earlier.
local function team_predates(team, since)
    local start = (storage.team_clock_start or {})[team]
    return start ~= nil and start < since
end

--- Which BEGAN line explains a count that may miss earlier restarts, or nil.
local function why_incomplete(row, team, since)
    if row.had_team_at_start then return "had_team" end
    if team_predates(team, since) then return "old_team" end
    if game.tick - since < RECENT_TICKS then return "recent" end
    return nil
end

--- The reply's note: why this player's count may not be complete, or nil
--- when it is. Counting that began with the map (tick 0) missed nothing.
local function caveat(row, team, since)
    if since == nil then return NOT_COUNTING end
    if since == 0 then return nil end
    local why = why_incomplete(row, team, since)
    if not why then return nil end
    return string.format(BEGAN[why], tostring(reply.hours(game.tick - since))) .. UNRECORDED
end

function M.call(args)
    local text = type(args) == "table" and args.player or nil
    if type(text) ~= "string" or text == "" then error("player is required", 0) end
    local player, hits = find_player(text)
    if not player then return not_found(text, hits) end
    local history = storage.player_team_history
    local row = (history or {})[player.index] or {}
    local claims, joins = row.claims or 0, row.joins or 0
    local since = history and storage.player_team_history_since or nil
    local team = effective_force(player)
    return {
        found = true, player = player.name,
        force = helpers.is_team_force(team) and team or nil,
        claims = claims,
        joined_others = math.max(0, joins - claims),
        restarts = restarts(row),
        had_team_at_start = row.had_team_at_start == true or nil,
        counting = history ~= nil,
        counting_since_tick = since,
        counting_for_hours = since and reply.hours(game.tick - since) or nil,
        note = caveat(row, team, since),
    }
end

return M
