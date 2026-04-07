-- Solo Teams - control.lua
-- Author: bits-orio
-- License: MIT
--
-- Main control script. Wires up all event handlers, initializes storage,
-- and delegates to specialized modules.

local nav           = require("gui.nav")
local helpers       = require("helpers")
local spectator     = require("spectator")
local force_utils   = require("force_utils")
local surface_utils = require("surface_utils")
local commands_mod  = require("commands")
local platforms_gui = require("gui.platforms")
local stats_gui     = require("gui.stats")
local landing_pen   = require("gui.landing_pen")
local admin_gui     = require("gui.admin")
local welcome_gui   = require("gui.welcome")
local research_gui  = require("gui.research")
local platformer    = require("compat.platformer")
local vanilla       = require("compat.vanilla")
local friendship    = require("gui.friendship")

-- ─── Helpers ───────────────────────────────────────────────────────────

--- Spawn the player into the game world (Platformer or vanilla).
local function spawn_into_world(player)
    if platformer.is_active() then
        platformer.on_player_created(player)
    else
        vanilla.setup_player_surface(player)
    end
end

--- Register nav buttons for a player across all modules.
local function register_nav_buttons(player)
    welcome_gui.on_player_created(player)
    platforms_gui.on_player_created(player)
    stats_gui.on_player_created(player)
    research_gui.on_player_created(player)
    admin_gui.on_player_created(player)
end

--- Rebuild stats GUI for all connected players who have it open.
local function refresh_stats(leaving_index)
    for _, player in pairs(game.players) do
        if player.connected and player.gui.screen.sb_stats_frame then
            stats_gui.build_stats_gui(player, leaving_index)
        end
    end
end

--- Rebuild all gameplay GUIs (platforms, research, stats).
local function refresh_all_gameplay_guis()
    platforms_gui.update_all()
    research_gui.update_all()
    refresh_stats()
end

--- Rebuild all GUIs for connectivity changes.
local function rebuild_for_connectivity(leaving_index)
    platforms_gui.update_all()
    research_gui.update_all()
    landing_pen.update_pen_gui_all()
    landing_pen.rebuild_buddy_request_guis()
    admin_gui.update_all()
    refresh_stats(leaving_index)
end

-- ─── Tick Events ───────────────────────────────────────────────────────

local function init_events()
    script.on_event(defines.events.on_chunk_generated, landing_pen.on_chunk_generated)
    script.on_event(defines.events.on_surface_created, function(event)
        local surface = game.surfaces[event.surface_index]
        if surface then surface_utils.on_surface_created(surface) end
    end)
    script.on_nth_tick(18000, function() surface_utils.cleanup_charts() end)
    script.on_event(defines.events.on_tick, function()
        landing_pen.process_pending_teleports()
        if platformer.is_active() then
            platformer.process_pending_teleports()
        else
            vanilla.process_pending_teleports()
        end
        if storage.pending_admin_check and next(storage.pending_admin_check) then
            local done = {}
            for idx, target_tick in pairs(storage.pending_admin_check) do
                if game.tick >= target_tick then
                    done[#done + 1] = idx
                    local p = game.get_player(idx)
                    if p and p.connected and p.admin and not p.gui.screen.sb_admin_frame then
                        admin_gui.build_admin_gui(p)
                    end
                end
            end
            for _, idx in ipairs(done) do
                storage.pending_admin_check[idx] = nil
            end
        end
    end)
end

-- ─── Lifecycle ─────────────────────────────────────────────────────────

script.on_init(function()
    log("[solo-teams] on_init fired")
    storage.gui_collapsed            = {}
    storage.gui_location             = {}
    storage.stats_gui_state          = {}
    storage.stats_gui_location       = {}
    storage.stats_category_items     = {}
    storage.spawned_players          = {}
    storage.pen_slots                = {}
    storage.pen_gui_location         = {}
    storage.pending_pen_tp           = {}
    storage.buddy_requests           = {}
    storage.player_surfaces          = {}
    storage.pending_vanilla_tp       = {}
    storage.admin_flags              = {}
    storage.pending_admin_check      = {}
    storage.admin_gui_collapsed      = {}
    storage.admin_gui_location       = {}
    storage.player_clock_start       = {}
    storage.tech_research_ticks      = {}
    storage.research_gui_location    = {}
    storage.research_gui_expanded    = {}
    storage.research_gui_diff_target = {}
    storage.show_offline_players     = {}
    admin_gui.get_flags()
    spectator.init()
    spectator.init_storage()
    commands_mod.register()
    init_events()
end)

script.on_load(function()
    storage.gui_collapsed            = storage.gui_collapsed            or {}
    storage.gui_location             = storage.gui_location             or {}
    storage.stats_gui_state          = storage.stats_gui_state          or {}
    storage.stats_gui_location       = storage.stats_gui_location       or {}
    storage.stats_category_items     = storage.stats_category_items     or {}
    storage.spawned_players          = storage.spawned_players          or {}
    storage.pen_slots                = storage.pen_slots                or {}
    storage.pen_gui_location         = storage.pen_gui_location         or {}
    storage.pending_pen_tp           = storage.pending_pen_tp           or {}
    storage.buddy_requests           = storage.buddy_requests           or {}
    storage.player_surfaces          = storage.player_surfaces          or {}
    storage.pending_vanilla_tp       = storage.pending_vanilla_tp       or {}
    storage.admin_flags              = storage.admin_flags              or {}
    storage.pending_admin_check      = storage.pending_admin_check      or {}
    storage.admin_gui_collapsed      = storage.admin_gui_collapsed      or {}
    storage.admin_gui_location       = storage.admin_gui_location       or {}
    storage.player_clock_start       = storage.player_clock_start       or {}
    storage.tech_research_ticks      = storage.tech_research_ticks      or {}
    storage.research_gui_location    = storage.research_gui_location    or {}
    storage.research_gui_expanded    = storage.research_gui_expanded    or {}
    storage.research_gui_diff_target = storage.research_gui_diff_target or {}
    storage.show_offline_players     = storage.show_offline_players     or {}
    spectator.init_storage()
    commands_mod.register()
    init_events()
end)

script.on_configuration_changed(function()
    log("[solo-teams] on_configuration_changed fired")
    storage.spawned_players          = storage.spawned_players          or {}
    storage.player_clock_start       = storage.player_clock_start       or {}
    storage.tech_research_ticks      = storage.tech_research_ticks      or {}
    storage.research_gui_location    = storage.research_gui_location    or {}
    storage.research_gui_expanded    = storage.research_gui_expanded    or {}
    storage.research_gui_diff_target = storage.research_gui_diff_target or {}
    storage.show_offline_players     = storage.show_offline_players     or {}
    for _, player in pairs(game.players) do
        if not storage.spawned_players[player.index] then
            storage.spawned_players[player.index] = true
        end
    end
    stats_gui.invalidate_categories()
    spectator.init()
    spectator.init_storage()
    init_events()
end)

-- ─── Player Events ─────────────────────────────────────────────────────

script.on_event(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    force_utils.create_player_force(player)
    register_nav_buttons(player)

    if admin_gui.flag("landing_pen_enabled") then
        landing_pen.place_player(player)
    else
        storage.spawned_players = storage.spawned_players or {}
        storage.spawned_players[player.index] = true
        spawn_into_world(player)
        force_utils.start_player_clock(player)
    end
    platforms_gui.update_all()
end)

script.on_event(defines.events.on_player_joined_game, function(event)
    local player = game.get_player(event.player_index)
    if player then spectator.on_player_joined(player) end
    if player and landing_pen.is_in_pen(player) then
        landing_pen.place_player(player)
    end
    if player then register_nav_buttons(player) end
    storage.pending_admin_check = storage.pending_admin_check or {}
    storage.pending_admin_check[event.player_index] = game.tick + 30
    rebuild_for_connectivity(nil)
end)

script.on_event(defines.events.on_player_left_game, function(event)
    local player = game.get_player(event.player_index)
    if player then spectator.on_player_left(player) end
    rebuild_for_connectivity(event.player_index)
end)

script.on_event(defines.events.on_player_promoted, function(event)
    local player = game.get_player(event.player_index)
    if player and player.connected then admin_gui.build_admin_gui(player) end
end)

script.on_event(defines.events.on_player_demoted, function(event)
    local player = game.get_player(event.player_index)
    if player and player.gui.screen.sb_admin_frame then
        player.gui.screen.sb_admin_frame.destroy()
    end
end)

-- ─── Surface & Controller Events ───────────────────────────────────────

script.on_event(defines.events.on_player_changed_surface, function(event)
    local player = game.get_player(event.player_index)
    if player and player.connected then
        if spectator.is_spectating(player)
           and player.controller_type ~= defines.controllers.remote then
            spectator.exit(player)
        end
        log("[solo-teams] surface_change: " .. player.name
            .. " → " .. (player.surface and player.surface.name or "nil"))
        force_utils.bounce_if_foreign(player)
        platforms_gui.build_platforms_gui(player)
    end
end)

script.on_event(defines.events.on_player_controller_changed, function(event)
    local player = game.get_player(event.player_index)
    if player and player.connected then
        spectator.on_controller_changed(player, event.old_controller_type)
        force_utils.bounce_if_foreign(player)
    end
end)

-- ─── Research Events ───────────────────────────────────────────────────

script.on_event(defines.events.on_research_finished, function(event)
    local tech  = event.research
    local force = tech.force
    storage.tech_research_ticks             = storage.tech_research_ticks or {}
    storage.tech_research_ticks[force.name] = storage.tech_research_ticks[force.name] or {}
    storage.tech_research_ticks[force.name][tech.name] = game.tick
    force_utils.sync_quality_all_forces()
    research_gui.update_all()
end)

-- ─── GUI Events ────────────────────────────────────────────────────────

script.on_event(defines.events.on_gui_click, function(event)
    local el = event.element
    if not el or not el.valid then return end

    if nav.dispatch_click(event) then return end

    if el.name == "sb_spawn_btn" then
        local player = game.get_player(event.player_index)
        if player and landing_pen.is_in_pen(player) then
            landing_pen.finish_spawn(player)
            spawn_into_world(player)
            force_utils.start_player_clock(player)
            refresh_all_gameplay_guis()
        end
        return
    end

    if el.name == "sb_buddy_request" then
        local player = game.get_player(event.player_index)
        if player and landing_pen.is_in_pen(player) and el.tags and el.tags.sb_target_index then
            local target = game.get_player(el.tags.sb_target_index)
            if target and target.connected and not landing_pen.is_in_pen(target) then
                landing_pen.send_buddy_request(player, target)
            end
        end
        return
    end

    if el.name == "sb_buddy_accept" then
        local player = game.get_player(event.player_index)
        if player and el.tags and el.tags.sb_requester_index then
            landing_pen.accept_buddy_request(player, el.tags.sb_requester_index)
            refresh_all_gameplay_guis()
        end
        return
    end

    if el.name == "sb_buddy_reject" then
        local player = game.get_player(event.player_index)
        if player and el.tags and el.tags.sb_requester_index then
            landing_pen.reject_buddy_request(player, el.tags.sb_requester_index)
        end
        return
    end

    if research_gui.on_gui_click(event) then return end
    if admin_gui.on_gui_click(event) then return end
    if stats_gui.on_gui_click(event) then return end
    platforms_gui.on_gui_click(event)
end)

script.on_event(defines.events.on_gui_elem_changed, function(event)
    stats_gui.on_gui_elem_changed(event)
end)

script.on_event(defines.events.on_gui_closed, function(event)
    if research_gui.on_gui_closed(event) then return end
    welcome_gui.on_gui_closed(event)
end)

script.on_event(defines.events.on_gui_checked_state_changed, function(event)
    -- "Show offline" toggle in platforms GUI
    local el = event.element
    if el and el.valid and el.name == "sb_show_offline_toggle" then
        local player = game.get_player(event.player_index)
        if player then
            helpers.toggle_show_offline(player)
            platforms_gui.build_platforms_gui(player)
            if player.gui.screen.sb_research_frame then
                research_gui.update_all()
            end
            if player.gui.screen.sb_stats_frame then
                stats_gui.build_stats_gui(player)
            end
        end
        return
    end

    local changed_flag = admin_gui.on_gui_checked_state_changed(event)
    if changed_flag then
        local admin_player = game.get_player(event.player_index)
        if admin_player then
            local state_str = admin_gui.flag(changed_flag) and "enabled" or "disabled"
            local label = admin_gui.get_flag_label(changed_flag)
            helpers.broadcast("[Admin] " .. admin_player.name .. " " .. state_str .. " " .. label)
        end
        if changed_flag == "buddy_join_enabled" then
            landing_pen.update_pen_gui_all()
        end
        if changed_flag == "friendship_enabled" and not admin_gui.flag("friendship_enabled") then
            friendship.break_all()
            platforms_gui.update_all()
        end
        if changed_flag == "friendship_enabled" and admin_gui.flag("friendship_enabled") then
            platforms_gui.update_all()
        end
        if changed_flag == "landing_pen_enabled" and not admin_gui.flag("landing_pen_enabled") then
            for _, player in pairs(game.players) do
                if landing_pen.is_in_pen(player) then
                    landing_pen.finish_spawn(player)
                    spawn_into_world(player)
                    force_utils.start_player_clock(player)
                end
            end
            refresh_all_gameplay_guis()
        end
        return
    end
    platforms_gui.on_friend_toggle(event)
end)

-- ─── Chat ──────────────────────────────────────────────────────────────

script.on_event(defines.events.on_console_chat, function(event)
    if not event.player_index then return end
    local author = game.get_player(event.player_index)
    if not author then return end
    local prefix = spectator.get_chat_prefix(author)
    for _, player in pairs(game.players) do
        if player.force ~= author.force then
            player.print(prefix .. author.name .. ": " .. event.message,
                         {color = author.color})
        end
    end
end)
