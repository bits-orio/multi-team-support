-- gui/start_playing_gui.lua
-- "Start Playing" modal shown to new team members while their team is in
-- pre-start staging. The leader sees a green Start Playing button; non-leaders
-- see a "waiting for leader" message.

local helpers     = require("scripts.helpers")
local force_utils = require("scripts.force_utils")
local pre_start   = require("scripts.pre_start")

local M = {}

local FRAME_NAME = "sb_start_playing_frame"

-- ─── Show ─────────────────────────────────────────────────────────────

function M.show(player)
    if not (player and player.valid and player.connected) then return end
    if player.gui.screen[FRAME_NAME] then
        player.gui.screen[FRAME_NAME].destroy()
    end

    local frame = player.gui.screen.add{type = "frame", name = FRAME_NAME, direction = "vertical"}
    frame.auto_center = true
    frame.style.minimal_width = 380

    helpers.add_title_bar(frame, {"mts-gui.start-playing-title"})

    local body = frame.add{type = "flow", direction = "vertical"}
    body.style.left_padding    = 12
    body.style.right_padding   = 12
    body.style.top_padding     = 8
    body.style.bottom_padding  = 10
    body.style.vertical_spacing = 8

    local team_tag = helpers.team_tag(player.force.name)

    local info = body.add{type = "label"}
    info.caption = {"mts-gui.start-playing-info", team_tag}
    info.style.single_line  = false
    info.style.maximal_width = 356

    body.add{type = "line"}

    local is_leader = force_utils.is_team_leader(player)

    if is_leader then
        local hint = body.add{type = "label",
            caption = {"mts-gui.start-playing-leader-hint"}}
        hint.style.single_line  = false
        hint.style.maximal_width = 356

        local btn = body.add{
            type    = "button",
            name    = "sb_start_playing_btn",
            caption = {"mts-gui.start-playing-button"},
            style   = "confirm_button",
            tooltip = {"mts-tip.start-playing-button"},
        }
        btn.style.horizontally_stretchable = true
        btn.style.font                     = "default-large-semibold"
        btn.style.top_margin               = 4
    else
        local hint = body.add{type = "label",
            caption = {"mts-gui.start-playing-waiting"}}
        hint.style.single_line  = false
        hint.style.maximal_width = 356
    end
end

-- ─── Close ────────────────────────────────────────────────────────────

function M.close(player)
    if not (player and player.valid and player.connected) then return end
    if player.gui.screen[FRAME_NAME] then
        player.gui.screen[FRAME_NAME].destroy()
    end
end

function M.close_all_for_force(force_name)
    local force = game.forces[force_name]
    if not force then return end
    for _, player in pairs(force.players) do
        if player.connected then M.close(player) end
    end
end

-- ─── Rebuild on Reconnect ─────────────────────────────────────────────

function M.rebuild_if_pending(player)
    if not (player and player.valid and player.connected) then return end
    if not force_utils.is_team_force(player.force.name) then return end
    if pre_start.is_pending(player.force.name) then
        M.show(player)
    end
end

return M
