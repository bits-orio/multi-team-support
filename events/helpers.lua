-- events/helpers.lua
-- Shared spawn and GUI refresh helpers used by multiple event handler modules.

local welcome_gui   = require("gui.welcome")
local teams_gui     = require("gui.teams")
local stats_gui     = require("gui.stats")
local awards_gui    = require("gui.awards")
local research_gui  = require("gui.research")
local admin_gui     = require("gui.admin")
local team_settings = require("gui.team_settings")
local landing_pen   = require("gui.landing_pen")
local follow_cam    = require("gui.follow_cam")
local platformer    = require("compat.platformer")
local deep_core_ops = require("compat.deep_core_ops")
local voidblock     = require("compat.voidblock")
local vanilla       = require("compat.vanilla")

local h = {}

--- Spawn the player into the world via the active compat layer.
function h.spawn_into_world(player)
    if platformer.is_active() then
        platformer.on_player_created(player)
    elseif deep_core_ops.is_active() then
        deep_core_ops.on_player_created(player)
    elseif voidblock.is_active() then
        voidblock.setup_player_surface(player)
    else
        vanilla.setup_player_surface(player)
    end
end

--- Register all nav buttons for a freshly created or rejoined player.
function h.register_nav_buttons(player)
    welcome_gui.on_player_created(player)
    teams_gui.on_player_created(player)
    stats_gui.on_player_created(player)
    awards_gui.on_player_created(player)
    research_gui.on_player_created(player)
    admin_gui.on_player_created(player)
    team_settings.on_player_created(player)
    team_settings.refresh_nav_button(player)
end

--- Rebuild the stats GUI for every connected player who has it open.
function h.refresh_stats(leaving_index)
    for _, player in pairs(game.players) do
        if player.connected and player.gui.screen.sb_stats_frame then
            stats_gui.build_stats_gui(player, leaving_index)
        end
    end
end

--- Rebuild the core gameplay GUIs (teams, research, stats).
function h.refresh_all_gameplay_guis()
    teams_gui.update_all()
    research_gui.update_all()
    h.refresh_stats()
end

--- Full GUI rebuild triggered by connectivity changes (player join/leave).
function h.rebuild_for_connectivity(leaving_index)
    teams_gui.update_all()
    research_gui.update_all()
    landing_pen.update_pen_gui_all()
    landing_pen.rebuild_buddy_request_guis()
    admin_gui.update_all()
    h.refresh_stats(leaving_index)
    follow_cam.rebuild_all()
    awards_gui.update_all()
end

return h
