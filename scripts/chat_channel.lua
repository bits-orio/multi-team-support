-- Multi-Team Support - scripts/chat_channel.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- Chat privacy channel: "global" (default) or "local" (team-only).
--
-- SCOPE. The admin flag individual_chat_enabled decides who one switch moves:
--   team scope (default) — the whole TEAM moves together. Syncing per team
--     removes the asymmetric-conversation leak where one member asks in
--     team-only mode and a teammate still in global mode answers for the
--     whole server to read.
--   individual scope — each PLAYER carries their own channel. That leak comes
--     back by construction, which is why it stayed off until the chat badge
--     (scripts/chat_tag.lua) put each message's channel in the line itself: a
--     teammate can now see they are about to answer in the open.
--
-- Each scope keeps its own storage. A team's setting survives a round trip;
-- the per-player table is re-seeded from it on every flip to individual, so
-- an individual choice does not outlive an admin flipping scope back and
-- forth. Flips migrate in the privacy-preserving direction only — see
-- M.on_scope_change.
--
-- The engine's native chat delivery (sender's force only) IS team chat; the
-- channel only decides whether events/chat.lua relays a message beyond it.
-- Pen spectators are always global — no state, no toggle. A team-only member
-- can shout one message globally by starting it with "!".
--
-- Requires helpers and admin_flags, both of which are themselves leaves, so
-- spectator core, the HUD, and the chat event handler can all require this
-- without closing a cycle.
--
-- Storage shape (absent = global, the default, in both):
--   storage.chat_channel[force_name]          = "local"   -- team scope
--   storage.chat_channel_player[player_index] = "local"   -- individual scope

local helpers     = require("scripts.helpers")
local admin_flags = require("scripts.admin_flags")

local M = {}

-- Fixed per-mode colors, for muscle memory: green encourages the global
-- default; team-only is a calm blue (deliberately not red). Every rendering
-- of channel state -- the switch announcements below, the chat badge in
-- scripts/chat_tag.lua, the spectate disclosure -- reads these, so retuning
-- one constant retunes all of them.
M.GLOBAL_COLOR = {0.4, 0.9, 0.4}
M.LOCAL_COLOR  = {0.45, 0.8, 1}

-- Soft blip when a spectating member's team message was also visible to
-- co-spectators. (Channel switches deliberately play no sound — the printed
-- announcement is enough.)
M.SOUND_EXPOSURE = "utility/list_box_click"

--- Effective-force resolution without requiring spectator (leaf constraint):
--- same inline pattern as remote_api's effective_fn.
local function effective_fn(p)
    return (storage.spectator_real_force or {})[p.index]
        or (p.force and p.force.name)
end

--- Is the feature currently individual-scoped? Team scope is the default, so
--- an unset flag and a save from before the switch existed both read as team.
function M.is_individual()
    return admin_flags.flag("individual_chat_enabled") == true
end

--- The storage table and key holding one player's channel under the current
--- scope. Both nil when they have no team at all (pen spectators), which is
--- what makes "no team means no channel" a single rule here rather than a
--- check repeated at every call site.
local function slot(player)
    local force_name = effective_fn(player)
    if not helpers.is_team_force(force_name) then return nil end
    if M.is_individual() then
        storage.chat_channel_player = storage.chat_channel_player or {}
        return storage.chat_channel_player, player.index
    end
    storage.chat_channel = storage.chat_channel or {}
    return storage.chat_channel, force_name
end

--- Is this player's chat currently team-only? False for anyone without a team.
function M.is_local_for(player)
    local tbl, key = slot(player)
    return tbl ~= nil and tbl[key] == "local"
end

--- Connected players whose effective force is this team — includes members
--- currently force-swapped into spectator mode, who must hear channel
--- switches too.
local function connected_members(force_name)
    local out = {}
    for _, p in pairs(game.connected_players) do
        if effective_fn(p) == force_name then out[#out + 1] = p end
    end
    return out
end

--- Everyone whose channel moves together with this player's: the whole team
--- under team scope, only themselves under individual scope. Callers use it
--- both to announce and to refresh HUDs, so the two can never disagree.
function M.peers(player)
    if M.is_individual() then return {player} end
    return connected_members(effective_fn(player))
end

local function announce(to_local, switcher, individual)
    local color = to_local and M.LOCAL_COLOR or M.GLOBAL_COLOR
    local state = helpers.colored_name(
        to_local and "TEAM-ONLY" or "GLOBAL", color)
    local subject
    if individual then
        subject = "Your chat is now " .. state .. "."
    else
        subject = "Team chat is now " .. state .. " (switched by "
            .. (switcher
                and helpers.colored_name(switcher.name, switcher.chat_color)
                or "an admin") .. ")."
    end
    if to_local then
        return subject .. " Messages stay within your team; start a message"
            .. " with ! to shout globally."
    end
    return subject .. " Everyone on the server sees your messages."
end

--- Set this player's channel outright ("local" | "global"). No-op (returns
--- false) when it is already there — the switch UI selects rather than
--- cycles. On change, announces to everyone the change actually moved;
--- callers refresh HUDs for M.peers on true.
function M.set_for(player, channel, switcher)
    local tbl, key = slot(player)
    if not tbl then return false end
    local to_local = channel == "local"
    if (tbl[key] == "local") == to_local then return false end
    tbl[key] = to_local and "local" or nil

    local individual = M.is_individual()
    local line = announce(to_local, switcher, individual)
    for _, member in ipairs(M.peers(player)) do
        member.print(line)
    end
    return true
end

--- Carry channel state across a scope flip, in the privacy-preserving
--- direction only: throwing the admin switch must never silently start
--- broadcasting what was private a second earlier.
---   → individual: everyone inherits their own team's current channel.
---   → team: a team goes team-only if ANY member was individually team-only.
---     Most-private wins, because the alternative exposes whoever chose it.
--- Both directions count offline players. Being offline does not revoke your
--- membership, and excluding them would silently drop a team-only member's
--- choice while they were away — exactly the exposure this function exists
--- to prevent.
function M.on_scope_change(now_individual)
    storage.chat_channel        = storage.chat_channel or {}
    storage.chat_channel_player = storage.chat_channel_player or {}
    for _, p in pairs(game.players) do
        local force_name = effective_fn(p)
        if helpers.is_team_force(force_name) then
            if now_individual then
                storage.chat_channel_player[p.index] =
                    storage.chat_channel[force_name]
            elseif storage.chat_channel_player[p.index] == "local" then
                storage.chat_channel[force_name] = "local"
            end
        end
    end
end

--- Drop a released slot's team channel so a future team starts on the
--- default. Only the team-scoped value: an individual channel is a personal
--- preference that follows the player to whatever team they join next, and
--- resetting it here would silently flip someone who had chosen team-only
--- back to broadcasting. Removed players are purged by events/player_removed.
function M.on_release(force_name)
    if storage.chat_channel then storage.chat_channel[force_name] = nil end
end

return M
