-- Multi-Team Support - gui/chat_switch.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- Center-top two-segment chat mode switch: GLOBAL | TEAM. Both segments are
-- always visible; the lit one is the team's current channel and clicking the
-- dark one selects it (select, not cycle — clicking the active segment does
-- nothing). Pure view module: the click handlers live in gui/hud_clock.lua
-- (which requires this module; requiring it back would close a cycle), and
-- update_player is called from the same one-second HUD refresh plus the
-- display-change events, so anchor and styles self-heal.
--
-- Only team players get the switch; pen spectators are always global and
-- have nothing to toggle.

local helpers      = require("scripts.helpers")
local chat_channel = require("scripts.chat_channel")

local M = {}

local FRAME_NAME = "mts_chat_switch"

M.SEG_GLOBAL = "mts_chat_seg_global"
M.SEG_TEAM   = "mts_chat_seg_team"

-- 2 x 88px segments + 2px spacing + 2px frame padding each side. The API
-- cannot measure rendered element size, so the centering math hardcodes it.
local SWITCH_WIDTH = 88 * 2 + 2 + 2 * 2

-- Reassigning a style resets the element's LuaStyle, so only write on change.
local function set_style(el, style_name)
    if el.style.name ~= style_name then el.style = style_name end
end

--- Create, refresh, or remove the switch for one player. force_name is the
--- player's effective team, or nil/non-team to remove.
function M.update_player(player, force_name)
    local screen = player.gui.screen
    local frame = screen[FRAME_NAME]
    if not (force_name and helpers.is_team_force(force_name)) then
        if frame then frame.destroy() end
        return
    end

    if not frame then
        frame = screen.add{type = "frame", name = FRAME_NAME, direction = "horizontal"}
        frame.style.padding = 2
        local row = frame.add{type = "flow", name = "mts_chat_row", direction = "horizontal"}
        row.style.horizontal_spacing = 2
        row.add{type = "button", name = M.SEG_GLOBAL, caption = "GLOBAL"}
        row.add{type = "button", name = M.SEG_TEAM,   caption = "TEAM"}
    end

    local row      = frame.mts_chat_row
    local seg_g    = row[M.SEG_GLOBAL]
    local seg_t    = row[M.SEG_TEAM]
    local is_local = chat_channel.is_local(force_name)
    -- Force-swapped into full spectate: the toggle keeps working, but team
    -- messages are also visible to co-spectators — the asterisk carries that.
    local swapped  = player.force.name ~= force_name

    set_style(seg_g, is_local and "mts_chat_seg_inactive" or "mts_chat_seg_global_active")
    set_style(seg_t, is_local and "mts_chat_seg_team_active" or "mts_chat_seg_inactive")
    seg_t.caption = swapped and "TEAM*" or "TEAM"

    seg_g.tooltip = "Chat is GLOBAL — everyone on the server sees your team's messages."
        .. (is_local and "\nClick to switch your whole team to global chat." or "")
    seg_t.tooltip = "Chat is TEAM-ONLY — messages stay inside your team."
        .. " Start a message with ! to shout globally."
        .. (is_local and "" or "\nClick to switch your whole team to team-only chat.")
        .. (swapped and ("\n* While spectating, other spectators can also"
            .. " see your team messages.") or "")

    -- Anchor: horizontally centered, just under the screen top. display_
    -- resolution can be transiently 0 for a just-connecting player; skipping
    -- the write is fine — the next one-second refresh re-anchors.
    local res = player.display_resolution
    if res and res.width and res.width > 0 then
        local scale = player.display_scale or 1
        frame.location = {
            x = math.floor(res.width / 2 - SWITCH_WIDTH * scale / 2),
            y = math.floor(10 * scale),
        }
    end
end

return M
