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
local starter_scope = require("scripts.starter_scope")
local helpers       = require("scripts.helpers")

local M = {}

function M.grant_starter_items(player)
    if not player.character then return end
    -- A delivery-override consumer (e.g. Brave New MTS) delivers starter items to
    -- the team's logistic chests at base placement, so skip the character grant.
    if remote_api.starter_delivery_override() then return end
    -- An EMPTY captured list must fall through to the compat default, not be
    -- honoured literally: the clear_items_inside below would otherwise strip the
    -- player and hand back nothing, which on a start like Sea Block (spawn is a
    -- one-tile island) is unrecoverable. A table is truthy however empty it is,
    -- so the length check is what makes this safe.
    local items = admin_gui.get_starter_items()
    if not items or #items == 0 then
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

    -- Team-scoped entries (bulk map resources) are granted once per force, to
    -- whichever member spawns first; player-scoped entries go to everyone. Without
    -- this a two-person team started with two full copies of the map's kit and
    -- raced a solo team with double the resources. The ledger is only marked when
    -- a team entry was actually handed over, so a list with no team entries never
    -- burns the team's one grant.
    local force_name = player.force.name
    -- Team scoping only applies on a real team force. return_to_pen grants to a
    -- player who has ALREADY been moved to the spectator force (see
    -- scripts/commands/admin.lua, which reassigns before it calls back here), so
    -- without this guard the ledger would take a "spectator" entry that no slot
    -- cleanup ever clears -- and the first disbanded veteran to land in the pen
    -- would burn it, silently denying bulk items to every veteran returned after
    -- them. Someone waiting in the pen has no team to stock anyway, so they get
    -- the player-scoped items only.
    local on_team    = helpers.is_team_force(force_name)
    local owed_team  = on_team and not starter_scope.team_has_kit(force_name)
    local paid_team  = false

    for _, item in pairs(items) do
        local team_scoped = starter_scope.is_team(item)
        if (not team_scoped) or owed_team then
            -- Clean-inserts {name, count, quality} and restores any captured armor
            -- equipment grid (e.g. FasterStart's pre-filled modular armor).
            admin_gui.insert_starter_item(player, item)
            if team_scoped then paid_team = true end
        end
    end

    if paid_team then starter_scope.mark_team_kit(force_name) end
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
