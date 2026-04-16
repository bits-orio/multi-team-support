-- Multi-Team Support - gui/confirm.lua
-- Author: bits-orio
-- License: MIT
--
-- Reusable confirmation dialog with Confirm/Cancel buttons.
-- Usage:
--   confirm.show(player, {
--       title        = "Leave Team?",
--       message      = "Are you sure you want to leave?\nYour items will be dropped as a corpse.",
--       confirm_text = "Leave Team",
--       cancel_text  = "Cancel",
--       action       = "leave",           -- routed to confirm handlers table
--       data         = {some_key = ...},  -- optional, passed back as tags
--   })
--
-- Modules register handlers via confirm.register(action_name, fn).
-- The handler is invoked with (player, data_tags) when the user clicks Confirm.

local helpers = require("helpers")

local confirm = {}

-- Handler registry: { [action_name] = function(player, data) ... end }
-- Registered at module load (once), so no desync concerns.
local handlers = {}

local FRAME_NAME = "sb_confirm_frame"

--- Register a confirmation handler for an action name.
--- Called during module load (not during gameplay), so it's desync-safe.
function confirm.register(action_name, fn)
    handlers[action_name] = fn
end

--- Show the confirmation dialog to a player.
function confirm.show(player, opts)
    if not (player and player.valid) then return end

    -- Close any existing confirm dialog
    if player.gui.screen[FRAME_NAME] then
        player.gui.screen[FRAME_NAME].destroy()
    end

    local frame = player.gui.screen.add{
        type      = "frame",
        name      = FRAME_NAME,
        direction = "vertical",
    }
    frame.auto_center = true

    helpers.add_title_bar(frame, opts.title or "Confirm")

    -- Message body (supports multi-line via "\n")
    local msg = frame.add{
        type    = "label",
        caption = opts.message or "Are you sure?",
    }
    msg.style.single_line     = false
    msg.style.maximal_width   = 420
    msg.style.top_margin      = 6
    msg.style.bottom_margin   = 8
    msg.style.left_margin     = 4
    msg.style.right_margin    = 4

    frame.add{type = "line"}

    -- Button row
    local btn_flow = frame.add{type = "flow", direction = "horizontal"}
    btn_flow.style.top_margin           = 6
    btn_flow.style.bottom_margin        = 2
    btn_flow.style.horizontally_stretchable = true

    local cancel_btn = btn_flow.add{
        type    = "button",
        name    = "sb_confirm_cancel",
        caption = opts.cancel_text or "Cancel",
        style   = "back_button",
    }
    cancel_btn.style.horizontally_stretchable = true

    -- Build tags merging data + action
    local tags = {sb_confirm = true, action = opts.action}
    if opts.data then
        for k, v in pairs(opts.data) do tags[k] = v end
    end

    local confirm_btn = btn_flow.add{
        type    = "button",
        name    = "sb_confirm_ok",
        caption = opts.confirm_text or "Confirm",
        style   = "confirm_button",
        tags    = tags,
    }
    confirm_btn.style.horizontally_stretchable = true

    player.opened = frame
end

--- Close the confirmation dialog for a player.
local function close(player)
    if player and player.valid and player.gui.screen[FRAME_NAME] then
        player.gui.screen[FRAME_NAME].destroy()
    end
end

--- Handle GUI click. Returns true if consumed.
function confirm.on_gui_click(event)
    local el = event.element
    if not el or not el.valid then return false end
    local player = game.get_player(event.player_index)
    if not player then return false end

    if el.name == "sb_confirm_cancel" then
        close(player)
        return true
    end

    if el.name == "sb_confirm_ok" and el.tags and el.tags.sb_confirm then
        local action  = el.tags.action
        local data    = el.tags  -- includes everything the caller passed
        close(player)
        local fn = handlers[action]
        if fn then fn(player, data) end
        return true
    end

    return false
end

return confirm
