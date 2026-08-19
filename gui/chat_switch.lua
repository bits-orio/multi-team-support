-- Multi-Team Support - gui/chat_switch.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- Center-top two-segment chat mode switch: GLOBAL | TEAM. Both segments are
-- always visible; the lit one is the current channel — the team's, or the
-- player's own when the individual_chat_enabled admin flag is on — and
-- clicking the dark one selects it (select, not cycle — clicking the active
-- segment does nothing). Pure view module: click handlers live in hud_clock
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

    -- Retire frames built before the translucent container style existed.
    if frame and frame.style.name ~= "mts_chat_switch_frame" then
        frame.destroy(); frame = nil
    end

    if not frame then
        frame = screen.add{type = "frame", name = FRAME_NAME,
            style = "mts_chat_switch_frame", direction = "horizontal"}
        local row = frame.add{type = "flow", name = "mts_chat_row", direction = "horizontal"}
        row.style.horizontal_spacing = 2
        row.add{type = "button", name = M.SEG_GLOBAL, caption = {"mts-gui.chat-seg-global"}}
        row.add{type = "button", name = M.SEG_TEAM,   caption = {"mts-gui.chat-seg-team"}}
    end

    local row      = frame.mts_chat_row
    local seg_g    = row[M.SEG_GLOBAL]
    local seg_t    = row[M.SEG_TEAM]
    local is_local = chat_channel.is_local_for(player)
    -- Under individual scope a click moves only the clicker, so the tooltips
    -- must not keep promising to move the whole team: each channel x scope
    -- combination is a whole-tooltip key ("Click to switch ..." tail
    -- included) so translators never assemble sentences from fragments.
    local indiv    = chat_channel.is_individual()
    -- Force-swapped into full spectate: the toggle keeps working, but team
    -- messages are also visible to co-spectators — the asterisk carries that.
    local swapped  = player.force.name ~= force_name

    set_style(seg_g, is_local and "mts_chat_seg_inactive" or "mts_chat_seg_global_active")
    set_style(seg_t, is_local and "mts_chat_seg_team_active" or "mts_chat_seg_inactive")
    seg_t.caption = swapped and {"mts-gui.chat-seg-team-spectating"}
                            or  {"mts-gui.chat-seg-team"}

    if is_local then
        seg_g.tooltip = indiv and {"mts-tip.chat-global-switch-individual"}
                              or  {"mts-tip.chat-global-switch-team"}
    else
        seg_g.tooltip = indiv and {"mts-tip.chat-global-active-individual"}
                              or  {"mts-tip.chat-global-active-team"}
    end

    local t_tip
    if is_local then
        t_tip = {"mts-tip.chat-team-active"}
    else
        t_tip = indiv and {"mts-tip.chat-team-switch-individual"}
                      or  {"mts-tip.chat-team-switch-team"}
    end
    if swapped then
        -- The note key carries its own leading newline.
        t_tip = {"", t_tip, {"mts-tip.chat-team-spectator-note"}}
    end
    seg_t.tooltip = t_tip

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
