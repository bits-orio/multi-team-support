-- Multi-Team Support - scripts/chat_channel.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- Team-synchronized chat channel. Each TEAM (not each player) is in "global"
-- or "local" (team-only) mode: syncing per team removes the asymmetric-
-- conversation leak where one member asks in team-only mode and a teammate
-- still in global mode replies for the whole server to read.
--
-- The engine's native chat delivery (sender's force only) IS team chat; the
-- channel only decides whether events/chat.lua relays a message beyond it.
-- Pen spectators are always global — no state, no toggle. A team-only team
-- member can shout one message globally by starting it with "!".
--
-- Leaf module (requires helpers only) so spectator core, the HUD, and the
-- chat event handler can all require it without cycles.
--
-- Storage shape:
--   storage.chat_channel[force_name] = "local"   -- absent = global (default)

local helpers = require("scripts.helpers")

local M = {}

-- Fixed per-mode colors, for muscle memory: green encourages the global
-- default; team-only is a calm blue (deliberately not red).
M.GLOBAL_COLOR = {0.4, 0.9, 0.4}
M.LOCAL_COLOR  = {0.45, 0.8, 1}

-- Soft blip when a spectating member's team message was also visible to
-- co-spectators. (Channel switches deliberately play no sound — the printed
-- announcement is enough.)
M.SOUND_EXPOSURE = "utility/list_box_click"

function M.get(force_name)
    local c = (storage.chat_channel or {})[force_name]
    return c == "local" and "local" or "global"
end

function M.is_local(force_name)
    return M.get(force_name) == "local"
end

-- Effective-force resolution without requiring spectator (leaf constraint):
-- same inline pattern as remote_api's effective_fn.
local function effective_fn(p)
    return (storage.spectator_real_force or {})[p.index]
        or (p.force and p.force.name)
end

--- Connected players whose effective force is this team — includes members
--- currently force-swapped into spectator mode, who must hear channel
--- switches too.
function M.connected_members(force_name)
    local out = {}
    for _, p in pairs(game.connected_players) do
        if effective_fn(p) == force_name then out[#out + 1] = p end
    end
    return out
end

--- Set a team's channel outright ("local" | "global"). No-op (returns
--- false) when it is already there — the switch UI selects rather than
--- cycles. On change, announces the new TEAM state to every member;
--- callers refresh HUDs on true.
function M.set(force_name, channel, switcher)
    if not helpers.is_team_force(force_name) then return false end
    local to_local = channel == "local"
    if M.is_local(force_name) == to_local then return false end
    storage.chat_channel = storage.chat_channel or {}
    storage.chat_channel[force_name] = to_local and "local" or nil

    local who = switcher
        and helpers.colored_name(switcher.name, switcher.chat_color)
        or "an admin"
    local line
    if to_local then
        line = "[color=0.45,0.8,1]Team chat is now TEAM-ONLY[/color] (switched by "
            .. who .. "). Messages stay within your team; start a message with"
            .. " ! to shout globally."
    else
        line = "[color=0.4,0.9,0.4]Team chat is now GLOBAL[/color] (switched by "
            .. who .. "). Everyone on the server sees your messages."
    end
    for _, member in ipairs(M.connected_members(force_name)) do
        member.print(line)
    end
    return true
end

--- Flip to the other channel (/mts-chat).
function M.toggle(force_name, switcher)
    return M.set(force_name,
        M.is_local(force_name) and "global" or "local", switcher)
end

--- Drop a released slot's channel so a future team starts on the default.
function M.on_release(force_name)
    if storage.chat_channel then storage.chat_channel[force_name] = nil end
end

return M
