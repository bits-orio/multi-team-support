-- gui/pen_ops.lua
-- grant_starter_items and finish_spawn, shared by landing_pen.lua and
-- buddy_requests.lua. Extracted here to break the mutual require cycle:
--   landing_pen → buddy_requests → pen_ops  (no back-edge to landing_pen)

local admin_gui     = require("gui.admin")
local remote_api    = require("scripts.remote_api")
local platformer    = require("compat.platformer")
local voidblock     = require("compat.voidblock")
local deep_core_ops = require("compat.deep_core_ops")
local compat_utils  = require("compat.compat_utils")
local pen_gui       = require("gui.pen_gui")
local buddy_store   = require("scripts.buddy_store")

local M = {}

function M.grant_starter_items(player)
    if not player.character then return end
    -- A delivery-override consumer (e.g. Brave New MTS) delivers starter items to
    -- the team's logistic chests at base placement, so skip the character grant.
    if remote_api.starter_delivery_override() then return end
    local items = admin_gui.get_starter_items()
    if not items then
        if platformer.is_active() then
            items = platformer.CHARACTER_STARTING_ITEMS
        elseif deep_core_ops.is_active() then
            items = deep_core_ops.CHARACTER_STARTING_ITEMS
        elseif voidblock.is_active() then
            items = voidblock.CHARACTER_STARTING_ITEMS
        else
            items = compat_utils.CHARACTER_STARTING_ITEMS
        end
    end
    player.character.clear_items_inside()
    for _, item in pairs(items) do
        -- Clean-inserts {name, count} and restores any captured armor
        -- equipment grid (e.g. faster-start's pre-filled power armor).
        admin_gui.insert_starter_item(player, item)
    end
end

function M.finish_spawn(player)
    storage.spawned_players = storage.spawned_players or {}
    storage.spawned_players[player.index] = true
    if storage.pen_slots then storage.pen_slots[player.index] = nil end
    -- A player leaving the pen can no longer be a buddy requester, so drop any
    -- request they had pending (and its Accept dialogs on members' screens).
    -- Makes this the single "left the pen" cleanup point for every spawn path,
    -- including the admin pen-disable force-spawn.
    buddy_store.clear(player.index)
    if player.gui.screen.sb_pen_frame then
        player.gui.screen.sb_pen_frame.destroy()
    end
    pen_gui.update_pen_gui_all()
end

return M
