-- Multi-Team Support - gui/hud_clock.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- Persistent top-bar team clock: the player's team name with the team's
-- birth-clock elapsed time underneath. The birth clock (server time since the
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
local spectator      = require("scripts.spectator")
local team_clock     = require("scripts.team_clock")
local team_modifiers = require("scripts.team_modifiers")

local M = {}

local FLOW_NAME = "mts_hud_clock"

local NOT_STARTED_COLOR = {0.6, 0.6, 0.6}
local CLOCK_COLOR       = {0.9, 0.9, 0.9}

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

--- Create, update, or remove the top-bar clock for one player, based on
--- their effective force. Idempotent; safe from any event context.
function M.update_player(player)
    if not (player and player.valid) then return end
    local top  = player.gui.top
    local flow = top[FLOW_NAME]

    local force_name = spectator.get_effective_force(player)
    local caption, tooltip, color = M.clock_caption(force_name)
    if not caption then
        if flow then flow.destroy() end
        return
    end

    if not flow then
        flow = top.add{type = "flow", name = FLOW_NAME, direction = "vertical"}
        flow.style.left_margin = 8
        flow.style.top_margin  = 6
        local name_lbl = flow.add{type = "label", name = "mts_hud_team_name"}
        name_lbl.style.font = "default-bold"
        flow.add{type = "label", name = "mts_hud_team_time"}
    end

    local force    = game.forces[force_name]
    local name_lbl = flow.mts_hud_team_name
    name_lbl.caption          = helpers.display_name(force_name)
    name_lbl.style.font_color = force and helpers.force_color(force) or helpers.WHITE
    name_lbl.tooltip          = tooltip

    local time_lbl = flow.mts_hud_team_time
    time_lbl.caption          = caption
    time_lbl.style.font_color = color
    time_lbl.tooltip          = tooltip

    -- Non-competitive mode tag, with this team's own modifiers appended
    -- ("non-competitive · peaceful") so an asymmetry is visible at a glance.
    local tag, tag_tip = team_modifiers.hud_tag(force_name)
    local tag_lbl = flow.mts_hud_mode_tag
    if tag then
        if not tag_lbl then
            tag_lbl = flow.add{type = "label", name = "mts_hud_mode_tag"}
            tag_lbl.style.font       = "default-small"
            tag_lbl.style.font_color = team_modifiers.MODE_COLOR
        end
        tag_lbl.caption = tag
        tag_lbl.tooltip = tag_tip
    elseif tag_lbl then
        tag_lbl.destroy()
    end
end

--- One-second refresh for every connected player (60-tick handler).
function M.update_all()
    for _, player in pairs(game.connected_players) do
        M.update_player(player)
    end
end

return M
