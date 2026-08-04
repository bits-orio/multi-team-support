-- Multi-Team Support - gui/hud_clock.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- Persistent top-bar team chip — "TeamName | 1h 44m 46s" in a framed one-line
-- row right of the nav buttons — plus ownership of the center-top chat switch
-- (gui/chat_switch.lua renders it; the click handlers live here). The birth
-- clock (server time since the
-- team started playing) is the official basis for records/awards; the
-- schedule-fair online clock rides along in the tooltip once they diverge.
--
-- Captions (including team name/colour, which self-heal after renames and
-- leader colour drift) are rewritten once a second from the 60-tick handler
-- in events/ticks.lua. Creation/destruction also happens there, plus eagerly
-- on join and force change so the clock appears without a one-second lag.
-- A member peeking at another team via spectator mode keeps their OWN team's
-- clock: display follows the effective force, not player.force.

local helpers        = require("scripts.helpers")
local nav            = require("gui.nav")
local spectator      = require("scripts.spectator")
local team_clock     = require("scripts.team_clock")
local team_modifiers = require("scripts.team_modifiers")
local chat_channel   = require("scripts.chat_channel")
local chat_switch    = require("gui.chat_switch")

local M = {}

local FLOW_NAME = "mts_hud_clock"

local NOT_STARTED_COLOR = {0.6, 0.6, 0.6}
local CLOCK_COLOR       = {1, 1, 1}  -- pure white: the translucent panel eats contrast

--- Caption + tooltip + colour for a team's clock label. Shared with the
--- Teams GUI per-card clocks (gui/team_card.lua) so both read identically.
--- Returns nil caption for a non-team force.
function M.clock_caption(force_name)
    if not helpers.is_team_force(force_name) then return nil end

    local start = (storage.team_clock_start or {})[force_name]
    if not start then
        return "[img=utility/clock] not started",
            "The clock starts when the team leader clicks Start Playing.",
            NOT_STARTED_COLOR
    end

    local elapsed = game.tick - start
    if elapsed < 0 then elapsed = 0 end
    local tooltip = "Time since the team started playing — the official time"
        .. " for records and awards."
    local online = team_clock.online_ticks(force_name)
    if online and online < elapsed then
        tooltip = tooltip .. "\nOnline (at least one member connected): "
            .. helpers.fmt_duration(online)
    end
    return "[img=utility/clock] " .. helpers.fmt_duration(elapsed),
        tooltip, CLOCK_COLOR
end

--- Create, update, or remove the top-bar team chip (name | clock, framed,
--- one line, sitting right of the nav buttons) plus the center-top chat
--- switch, based on the player's effective force. Idempotent; safe from any
--- event context.
function M.update_player(player)
    if not (player and player.valid) then return end
    local top  = player.gui.top
    local root = top[FLOW_NAME]

    local force_name = spectator.get_effective_force(player)
    local caption, tooltip, color = M.clock_caption(force_name)
    if not caption then
        if root then root.destroy() end
        chat_switch.update_player(player, nil)
        return
    end

    -- Defensive rebuild across layout versions: the style-name check retires
    -- both the pre-chip label stack and the earlier opaque padded chip.
    if root and (not root.mts_hud_row or root.style.name ~= "mts_hud_chip_frame") then
        root.destroy(); root = nil
    end

    if not root then
        root = top.add{type = "frame", name = FLOW_NAME,
            style = "mts_hud_chip_frame", direction = "vertical"}
        root.style.left_margin = 8
        root.style.top_margin  = 15  -- centers the chip on the 56px nav-button row
        local row = root.add{type = "flow", name = "mts_hud_row", direction = "horizontal"}
        row.style.vertical_align     = "center"
        row.style.horizontal_spacing = 6
        local name_lbl = row.add{type = "label", name = "mts_hud_team_name"}
        name_lbl.style.font = "mts-hud-bold"
        local time_lbl = row.add{type = "label", name = "mts_hud_team_time"}
        time_lbl.style.font = "mts-hud-bold"
    end

    -- Font upgrade for chips built before the halo font existed (live saves).
    if root.mts_hud_row.mts_hud_team_name.style.font ~= "mts-hud-bold" then
        root.mts_hud_row.mts_hud_team_name.style.font = "mts-hud-bold"
        root.mts_hud_row.mts_hud_team_time.style.font = "mts-hud-bold"
    end

    local row      = root.mts_hud_row
    local force    = game.forces[force_name]
    local name_lbl = row.mts_hud_team_name
    name_lbl.caption          = helpers.display_name(force_name)
    name_lbl.style.font_color = force and helpers.force_color(force) or helpers.WHITE
    name_lbl.tooltip          = tooltip

    local time_lbl = row.mts_hud_team_time
    time_lbl.caption          = caption
    time_lbl.style.font_color = color
    time_lbl.tooltip          = tooltip

    -- Non-competitive mode tag, second line under the chip row, with this
    -- team's own modifiers appended ("non-competitive · peaceful") so an
    -- asymmetry is visible at a glance.
    local tag, tag_tip = team_modifiers.hud_tag(force_name)
    local tag_lbl = root.mts_hud_mode_tag
    if tag then
        if not tag_lbl then
            tag_lbl = root.add{type = "label", name = "mts_hud_mode_tag"}
            tag_lbl.style.font       = "default-small"
            tag_lbl.style.font_color = team_modifiers.MODE_COLOR
        end
        tag_lbl.caption = tag
        tag_lbl.tooltip = tag_tip
    elseif tag_lbl then
        tag_lbl.destroy()
    end

    chat_switch.update_player(player, force_name)
end

--- One-second refresh for every connected player (60-tick handler).
function M.update_all()
    for _, player in pairs(game.connected_players) do
        M.update_player(player)
    end
end

--- Select a specific channel for the player's team (switch segment click);
--- no-op when already active. On change, every member's HUD and switch
--- refresh in the same action rather than on the next one-second tick.
local function select_channel(player, channel)
    local force_name = spectator.get_effective_force(player)
    if not helpers.is_team_force(force_name) then return end
    if chat_channel.set(force_name, channel, player) then
        for _, member in ipairs(chat_channel.connected_members(force_name)) do
            M.update_player(member)
        end
    end
end

--- Flip the player's team chat channel (/mts-chat).
function M.toggle_chat_channel(player)
    local force_name = spectator.get_effective_force(player)
    if not helpers.is_team_force(force_name) then
        player.print("Spectator chat is always global.")
        return
    end
    select_channel(player,
        chat_channel.is_local(force_name) and "global" or "local")
end

nav.on_click(chat_switch.SEG_GLOBAL, function(event)
    select_channel(event.player, "global")
end)
nav.on_click(chat_switch.SEG_TEAM, function(event)
    select_channel(event.player, "local")
end)

return M
