-- events/player_removed.lua
-- Handle permanent player removal (on_pre_player_removed) — e.g. an admin
-- running game.remove_offline_players() or /purge-player.
--
-- "Removed" is NOT "left" (disconnect): a removed player_index is orphaned in
-- every player-index-keyed storage table, in team_leader, and in cross-player
-- GUIs (a member's Accept/Reject dialog). Removed indexes can be reused, so a
-- new player inheriting a stale index would inherit the old player's state.
--
-- on_pre_player_removed fires BEFORE the engine deletes the player, so
-- game.get_player(index) is still valid here — the handler can read player.force
-- and run team_slots.remove_from_team (leader promotion / solo-disband). The
-- post-deletion on_player_removed can't, so it isn't used.

local team_slots  = require("scripts.team_slots")
local force_utils = require("scripts.force_utils")
local buddy_store = require("scripts.buddy_store")
local follow_cam  = require("gui.follow_cam")
local spectator   = require("scripts.spectator")

local M = {}

-- Every player-index-keyed storage table. Kept next to the removal sweep so the
-- two stay in step. Excludes tables cleaned by a dedicated path:
--   • buddy_requests   -> buddy_store.clear (below)
--   • follow_cam (nested) -> follow_cam.on_player_left (below)
--   • team_leader (force-keyed value) -> team_slots.remove_from_team (below)
local PLAYER_TABLES = {
    -- landing pen / spawn
    "spawned_players", "pen_slots", "pen_gui_location", "pending_pen_tp",
    "pending_spawn_pop", "player_surfaces", "pending_vanilla_tp",
    "pending_platform_tp", "left_teams", "player_clock_start",
    -- GUI window state / positions
    "gui_location", "stats_gui_state", "stats_gui_location", "stats_category_items",
    "awards_gui_state", "awards_gui_location", "admin_gui_location",
    "research_gui_location", "research_gui_expanded", "research_gui_diff_target",
    "return_button_location", "team_settings_location", "follow_cam_location",
    "lfm_hint_close_tick",
    -- session / misc
    "seen_players", "player_last_seen", "show_offline_players", "god_pre_remote",
    "pending_admin_check", "odb_suppress_claim", "color_fix_last", "zoom_apply",
    -- spectator (flat, player-index-keyed)
    "spectator_real_force", "spectating_target", "spectator_saved_craft_mod",
    "spectator_saved_location", "spectator_prev_controller", "spectator_last_zoom",
    "spectator_last_remote_view",
}

local function cleanup_player_storage(idx)
    for _, tbl in ipairs(PLAYER_TABLES) do
        if storage[tbl] then storage[tbl][idx] = nil end
    end
end

function M.register()
    script.on_event(defines.events.on_pre_player_removed, function(event)
        local idx    = event.player_index
        local player = game.get_player(idx)

        if player and player.valid then
            -- Restore a spectating member to their real force first, so
            -- remove_from_team acts on the actual team, not "spectator".
            if spectator.is_spectating(player) then spectator.exit(player) end
            -- Leader promotion / solo-disband / left_teams bookkeeping / slot
            -- release all live in remove_from_team — run it while the player and
            -- the force roster are still intact.
            if force_utils.is_team_force(player.force.name) then
                team_slots.remove_from_team(player)
            end
            -- Drop this player's follow-cam state (nested by index).
            follow_cam.on_player_left(player)
        end

        -- Drop any join request this player had pending (as requester) and its
        -- Accept/Reject frames on members' screens. Requests TO this player's
        -- former team are handled by wipe_slot_state if they were the last
        -- member (via remove_from_team above).
        buddy_store.clear(idx)

        cleanup_player_storage(idx)
    end)
end

return M
