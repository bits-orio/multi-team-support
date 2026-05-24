-- Multi-Team Support - scripts/team_clock.lua
-- Author: bits-orio
-- License: MIT
--
-- Per-team "online time": wall-clock ticks during which the team had at least
-- one connected member. Unlike the team birth clock (storage.team_clock_start),
-- this freezes while the whole team is offline, so a team that logs off for the
-- night isn't penalised against teams that happen to be online more hours.
--
-- This is wall-clock-while-online, NOT a sum of per-player online_time: two
-- members playing together for an hour is one hour of team progress, not two.
--
-- Informational only. Awards / records stay on the birth clock (server-elapsed)
-- so an offline base that keeps producing can't manufacture an unbeatable time.
--
-- Event-driven: we stamp `online_since` on the offline→online transition and
-- settle the accumulator on the online→offline transition. No per-tick work.
--
-- Storage shape:
--   storage.team_online_ticks[force_name] = accumulated ticks of finished streaks
--   storage.team_online_since[force_name] = tick the current streak began, or nil

local spectator = require("scripts.spectator")

local team_clock = {}

function team_clock.init_storage()
    storage.team_online_ticks = storage.team_online_ticks or {}
    storage.team_online_since = storage.team_online_since or {}
end

--- Count connected members whose *effective* force is this team, optionally
--- excluding one player. Effective force keeps a member who is peeking at the
--- spectator force counted under their real team. The exclude is used on
--- on_player_left_game, where the engine may or may not have already dropped the
--- leaver from connected_players — excluding by index is correct either way.
local function online_member_count(force_name, exclude_index)
    local n = 0
    for _, p in pairs(game.connected_players) do
        if p.index ~= exclude_index and spectator.get_effective_force(p) == force_name then
            n = n + 1
        end
    end
    return n
end

--- Recompute a team's online/offline state and settle its accumulator on a
--- transition. Call on any join / leave / force-change touching this team.
function team_clock.refresh(force_name, exclude_index)
    if not (force_name and force_name:find("^team%-")) then return end
    team_clock.init_storage()

    local online = online_member_count(force_name, exclude_index) > 0
    local since  = storage.team_online_since[force_name]

    if online and not since then
        storage.team_online_since[force_name] = game.tick
    elseif (not online) and since then
        storage.team_online_ticks[force_name] =
            (storage.team_online_ticks[force_name] or 0) + (game.tick - since)
        storage.team_online_since[force_name] = nil
    end
end

--- Total online ticks for a team right now: settled streaks plus the live one.
function team_clock.online_ticks(force_name)
    local total = (storage.team_online_ticks or {})[force_name] or 0
    local since = (storage.team_online_since or {})[force_name]
    if since then total = total + (game.tick - since) end
    return total
end

--- Begin tracking when a slot is claimed (clock starts at zero; the caller
--- follows up with refresh() once the player's force is set, which stamps the
--- first online_since).
function team_clock.on_claim(force_name)
    team_clock.init_storage()
    storage.team_online_ticks[force_name] = storage.team_online_ticks[force_name] or 0
end

--- Drop all online-time state when a slot is released.
function team_clock.on_release(force_name)
    if storage.team_online_ticks then storage.team_online_ticks[force_name] = nil end
    if storage.team_online_since then storage.team_online_since[force_name] = nil end
end

return team_clock
