-- gui/return_button.lua
-- Standalone "Exit remote view" button shown only when a remote-only compat
-- (e.g. Platformer) is active AND the player's remote view is currently
-- pointed at a foreign team's surface. Pressing the button returns the
-- remote view to the player's own physical character without leaving
-- remote mode -- mirroring what Esc does in Platformer.

local compat_utils  = require("compat.compat_utils")
local force_utils   = require("scripts.force_utils")
local surface_utils = require("scripts.surface_utils")
local helpers       = require("scripts.helpers")

local return_button = {}

local FRAME_NAME  = "sb_return_button_frame"
local BUTTON_NAME = "sb_return_button_click"
local DEFAULT_POS = {x = 5, y = 5}

local function destroy(player)
    local frame = player.gui.screen[FRAME_NAME]
    if frame then
        storage.return_button_location = storage.return_button_location or {}
        storage.return_button_location[player.index] = frame.location
        frame.destroy()
    end
end

local function should_show(player)
    if not compat_utils.is_compat_remote_only_mode() then return false end
    local owner = surface_utils.get_owner(player.surface)
    if not owner then return false end
    if not force_utils.is_team_force(owner) then return false end
    return owner ~= player.force.name
end

function return_button.update(player)
    if not (player and player.valid and player.connected) then return end

    if not should_show(player) then
        destroy(player)
        return
    end

    storage.return_button_location = storage.return_button_location or {}
    local frame = player.gui.screen[FRAME_NAME]
    if not frame then
        frame = player.gui.screen.add{
            type      = "frame",
            name      = FRAME_NAME,
            direction = "horizontal",
        }
        frame.location = storage.return_button_location[player.index] or DEFAULT_POS
        frame.add{
            type    = "button",
            name    = BUTTON_NAME,
            caption = "Exit remote view",
            style   = "button",
            tooltip = "Return remote view to your own base",
        }
    end
end

function return_button.on_gui_click(event)
    local el = event.element
    if not el or not el.valid then return false end
    if el.name ~= BUTTON_NAME then return false end

    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return true end

    local phys_surface = player.physical_surface
    local phys_pos     = player.physical_position
    if not (phys_surface and phys_surface.valid and phys_pos) then return true end

    helpers.diag("return_button: REMOTE → " .. phys_surface.name, player)
    player.set_controller{
        type     = defines.controllers.remote,
        surface  = phys_surface,
        position = phys_pos,
    }
    -- Surface change fires on_player_changed_surface which calls update();
    -- no need to destroy here.
    return true
end

return return_button
