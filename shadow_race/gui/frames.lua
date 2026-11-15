-- Multi-Team Support - shadow_race/gui/frames.lua
-- Author: bits-orio
-- License: MIT
--
-- What Shadow Race's windows share: the frame with its slim title bar, the small icon buttons, and the team a player is looking at the
-- race for.

local helpers   = require("scripts.helpers")
local spectator = require("scripts.spectator")

local M = {}

--- The player's own team, also while they watch another team as a
--- spectator; nil off a team.
function M.team_of(player)
    local force_name = spectator.get_effective_force(player)
    return helpers.is_team_force(force_name) and force_name or nil
end

local WHITE_ICONS = { ["utility/close"] = true, ["utility/track_button_white"] = true }

--- A small icon button for a title bar or a row. `action` goes into
--- tags.mts_shadow together with `extra`; `on` shows it pressed in.
function M.icon(parent, sprite, action, tooltip, on, extra)
    local tags = extra or {}
    tags.mts_shadow = action
    -- The game draws most of its icons in black: those go on the light
    -- tool button, the white ones on the dark title-bar button.
    local white = WHITE_ICONS[sprite]
    local button = parent.add{type = "sprite-button", sprite = sprite,
        style = white and "frame_action_button" or "tool_button", tooltip = tooltip, tags = tags}
    if not white then
        button.style.size = 24
        button.style.padding = 2
    end
    button.toggled = on == true
    return button
end

--- A screen frame with a slim title bar that drags it. Returns the frame
--- and its bar, so the caller can put its own icons before the close
--- button, which is added by M.finish_bar. `glass` makes it the translucent
--- panel, for a window that stays over the game for a whole run.
function M.titled(player, name, title, location, glass)
    local frame = player.gui.screen.add{type = "frame", name = name, direction = "vertical",
        style = glass and "mts_glass_frame" or "frame"}
    frame.location = location
    local bar = frame.add{type = "flow", name = "bar", direction = "horizontal"}
    bar.drag_target = frame
    bar.style.vertical_align = "center"
    bar.style.horizontal_spacing = 4
    local label = bar.add{type = "label", name = "title", caption = title}
    label.style.font = glass and "mts-hud-bold" or "default-bold"
    label.style.font_color = {1, 0.9, 0.75}
    label.ignored_by_interaction = true
    local spacer = bar.add{type = "empty-widget"}
    spacer.style.horizontally_stretchable = true
    spacer.style.height = 20
    spacer.style.minimal_width = 24
    spacer.drag_target = frame
    return frame, bar
end

--- The close button, last on the bar; tags.mts_shadow = close_action.
function M.finish_bar(bar, close_action)
    M.icon(bar, "utility/close", close_action)
end

function M.close(player, name)
    local frame = player.gui.screen[name]
    if frame then frame.destroy() end
end

return M
