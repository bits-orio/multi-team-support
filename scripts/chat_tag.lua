-- Multi-Team Support - scripts/chat_tag.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- Per-message channel badge, stamped onto player.tag.
--
-- The engine prints every chat message to the sender's own force before any
-- mod runs, and that native line cannot be cancelled or edited (see
-- events/chat.lua). player.tag is the only handle on it: the engine appends
-- the tag after the player's name, so the badge rides along on the one line
-- MTS otherwise cannot touch. That makes chat scrollback a record of the
-- channel each message was sent under — something the HUD switch, which only
-- ever shows the CURRENT state, cannot provide.
--
-- Both states carry a badge. Marking only one would make absence meaningful,
-- and absence is ambiguous: a fresh join, a pen spectator and an admin-moved
-- player all look identical to a team gone dark.
--
-- The tag is also drawn on the map and above multiplayer selection
-- rectangles, i.e. opposing teams can read it. That is accepted: a team-only
-- badge does tell opponents this team went dark, but the alternative leaks the
-- same fact through the badge's absence.
--
-- One case the badge cannot narrow: a "!" shout goes server-wide without
-- changing the channel, so that line still reads [TEAM]. The leading "!" the
-- sender typed is right there on the same line and is the marker for it —
-- nothing per-message can be stamped after the engine has already printed.

local chat_channel = require("scripts.chat_channel")
local helpers      = require("scripts.helpers")

local M = {}

-- count-font is the only vanilla font that both fits the width budget and
-- sets border = true (size 13, from default-bold). The black outline is what
-- keeps the badge readable over arbitrary terrain in the map view, where an
-- unbordered tag washes out; the dark chat panel would not need it.
local FONT = "count-font"

--- Colors come from chat_channel rather than literals so the badge and the
--- printed "Team chat is now ..." announcement can never drift apart.
local function badge(color, word)
    return ("[color=%s,%s,%s][font=%s][%s][/font][/color]")
        :format(color[1], color[2], color[3], FONT, word)
end

-- Both badges are constant, so build them once at parse time rather than
-- reformatting per player per second in the refresh below.
local GLOBAL_BADGE = badge(chat_channel.GLOBAL_COLOR, "GLOBAL")
local LOCAL_BADGE  = badge(chat_channel.LOCAL_COLOR,  "TEAM")

--- The badge for one player's current channel — their team's under team
--- scope, their own under individual scope; chat_channel resolves which.
--- Players with no team (pen spectators) have no channel to report and get
--- "", matching the chat switch, which gui/chat_switch.lua removes for them.
function M.badge_for(player, force_name)
    if not helpers.is_team_force(force_name) then return "" end
    return chat_channel.is_local_for(player) and LOCAL_BADGE or GLOBAL_BADGE
end

--- Stamp one player's badge from their effective team. force_name is the
--- player's effective force, or nil for none.
---
--- Only writes on change: this runs for every connected player every second,
--- and reassigning the tag redraws their nameplate. Always assigns "" rather
--- than nil — tag is a string field, and nil would error.
function M.update_player(player, force_name)
    local want = M.badge_for(player, force_name)
    if player.tag ~= want then player.tag = want end
end

return M
