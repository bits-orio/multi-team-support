-- Multi-Team Support - control.lua
-- Author: bits-orio
-- License: MIT
--
-- Main control script. Wires up all event handlers, initializes storage,
-- and delegates to specialized modules.

local nav             = require("gui.nav")
local helpers         = require("scripts.helpers")
local spectator       = require("scripts.spectator")
local force_utils     = require("scripts.force_utils")
local surface_utils   = require("scripts.surface_utils")
local commands_mod    = require("scripts.commands")
local teams_gui       = require("gui.teams")
local stats_gui       = require("gui.stats")
local awards_gui      = require("gui.awards")
local landing_pen     = require("gui.landing_pen")
local admin_gui       = require("gui.admin")
local welcome_gui     = require("gui.welcome")
local research_gui    = require("gui.research")
local platformer      = require("compat.platformer")
local vanilla         = require("compat.vanilla")
local voidblock       = require("compat.voidblock")
local dangoreus       = require("compat.dangoreus")
local friendship      = require("gui.friendship")
local tech_records    = require("scripts.tech_records")
local milestones      = require("milestones.engine")
local confirm_gui     = require("gui.confirm")
local follow_cam      = require("gui.follow_cam")
local planet_map      = require("scripts.planet_map")
local space_age       = require("scripts.space_age")
local force_pause     = require("scripts.force_pause")
local team_settings   = require("gui.team_settings")

-- ─── Helpers ───────────────────────────────────────────────────────────

--- Spawn the player into the game world (Platformer, VoidBlock, or vanilla).
local function spawn_into_world(player)
    if platformer.is_active() then
        platformer.on_player_created(player)
    elseif voidblock.is_active() then
        voidblock.setup_player_surface(player)
    else
        vanilla.setup_player_surface(player)
    end
end

--- Register nav buttons for a player across all modules.
local function register_nav_buttons(player)
    welcome_gui.on_player_created(player)
    teams_gui.on_player_created(player)
    stats_gui.on_player_created(player)
    awards_gui.on_player_created(player)
    research_gui.on_player_created(player)
    admin_gui.on_player_created(player)
    team_settings.on_player_created(player)
    -- Team Settings button is gated on team membership, so refresh it now.
    team_settings.refresh_nav_button(player)
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
    teams_gui.update_all()
    research_gui.update_all()
    refresh_stats()
end

--- Rebuild all GUIs for connectivity changes.
local function rebuild_for_connectivity(leaving_index)
    teams_gui.update_all()
    research_gui.update_all()
    landing_pen.update_pen_gui_all()
    landing_pen.rebuild_buddy_request_guis()
    admin_gui.update_all()
    refresh_stats(leaving_index)
    -- Follow cam panels list team members; connectivity changes may remove them
    follow_cam.rebuild_all()
    -- Leader may have changed (auto-election on leave) — awards GUI surfaces
    -- the leader's name, so it needs a rebuild too.
    awards_gui.update_all()
end

-- ─── Tick Events ───────────────────────────────────────────────────────

local function init_events()
    script.on_event(defines.events.on_chunk_generated, function(event)
        landing_pen.on_chunk_generated(event)
        if voidblock.is_active() then
            voidblock.on_chunk_generated(event)
        end
        if dangoreus.is_active() then
            dangoreus.on_chunk_generated(event)
        end
    end)
    script.on_event(defines.events.on_surface_created, function(event)
        local surface = game.surfaces[event.surface_index]
        if surface then
            surface_utils.on_surface_created(surface)
            -- Space Age: re-hide base planets for all team forces. We
            -- deliberately DON'T use apply_all_force_locks here — that
            -- would re-lock per-team planet variants and wipe any
            -- planet-discovery research the team has completed, causing
            -- the "space map" button to vanish every time a space platform
            -- is built.
            planet_map.hide_base_planets_for_all()
            -- dangOreus: build resource_table for new team surfaces.
            if dangoreus.is_active() then
                dangoreus.setup_surface(surface)
            end
        end
    end)

    -- dangOreus compat: block non-miners on ore, spill on destroyed containers.
    if dangoreus.is_active() then
        script.on_event({
            defines.events.on_built_entity,
            defines.events.on_robot_built_entity,
            defines.events.script_raised_built,
            defines.events.script_raised_revive,
        }, dangoreus.on_built_entity)
        script.on_event(defines.events.on_entity_died, dangoreus.on_entity_died)
        -- Floor-is-lava tick (same cadence as dangOreus)
        script.on_nth_tick(120, dangoreus.on_nth_tick)
    end

    -- Re-apply space-location locks when force state is reset externally
    -- (mirrors Team Starts' approach for Space Age).
    script.on_event(defines.events.on_force_reset, function(event)
        if event.force then planet_map.apply_force_locks(event.force) end
    end)
    script.on_event(defines.events.on_technology_effects_reset, function(event)
        if event.force then planet_map.apply_force_locks(event.force) end
    end)
    script.on_nth_tick(18000, function() surface_utils.cleanup_charts() end)

    -- Poll milestones every 300 ticks (5 seconds).
    -- Lightweight check across all trackers × items × occupied teams.
    -- When a new record is recorded, refresh the Awards GUI for anyone
    -- viewing it (piggy-backs on the existing milestone detection event
    -- rather than introducing a separate poll).
    script.on_nth_tick(300, function()
        if milestones.tick() then
            awards_gui.update_all()
        end
    end)

    -- Update follow cams every 2 ticks (~30 FPS). Server cost is just
    -- per-camera position/surface property writes; rendering is client-side.
    script.on_nth_tick(2, function() follow_cam.tick() end)

    -- Drive pending force-pause / force-resume sweeps. Entity-budget is
    -- enforced inside force_pause.tick(); this interval just gives it
    -- a predictable cadence.
    script.on_nth_tick(10, function() force_pause.tick() end)
    script.on_event(defines.events.on_tick, function()
        landing_pen.process_pending_teleports()
        if platformer.is_active() then
            platformer.process_pending_teleports()
        elseif voidblock.is_active() then
            voidblock.process_pending_teleports()
        else
            vanilla.process_pending_teleports()
        end
        if storage.pending_admin_check and next(storage.pending_admin_check) then
            local done = {}
            for idx, target_tick in pairs(storage.pending_admin_check) do
                if game.tick >= target_tick then
                    done[#done + 1] = idx
                    local p = game.get_player(idx)
                    if p and p.connected then
                        -- Refresh admin nav button based on current admin status
                        admin_gui.refresh_nav_button(p)
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
    log("[multi-team-support] on_init fired")
    storage.gui_collapsed            = {}
    storage.gui_location             = {}
    storage.stats_gui_state          = {}
    storage.stats_gui_location       = {}
    storage.stats_category_items     = {}
    storage.awards_gui_state         = {}
    storage.awards_gui_location      = {}
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
    storage.left_teams               = {}
    storage.player_clock_start       = {}
    storage.tech_research_ticks      = {}
    storage.follow_cam               = {}
    storage.follow_cam_location      = {}
    storage.map_force_to_planets     = {}
    storage.map_planet_to_force      = {}
    storage.god_pre_remote           = {}
    storage.dangoreus                = {}
    storage.research_gui_location    = {}
    storage.research_gui_expanded    = {}
    storage.research_gui_diff_target = {}
    storage.show_offline_players     = {}
    admin_gui.get_flags()
    spectator.init()
    spectator.init_storage()
    force_pause.init_storage()
    team_settings.init_storage()

    -- Pre-create all team forces ("team-1" through "team-N")
    force_utils.create_team_pool()

    -- Build the team↔planet variant maps (Space Age only; no-op otherwise)
    -- and apply space-location locks so teams only see their own planets.
    planet_map.build()
    planet_map.apply_all_force_locks()

    -- Initialize records and milestone tracking
    tech_records.init_storage()
    milestones.discover_items()

    -- dangOreus compat: port its logic onto our team nauvis surfaces
    dangoreus.init()

    commands_mod.register()
    init_events()
end)

script.on_load(function()
    -- on_load must NOT write to storage — doing so causes multiplayer desyncs
    -- because the server doesn't run on_load when a client joins.
    -- Individual functions already guard with "storage.xxx = storage.xxx or {}"
    -- at the point of use, so no initialization is needed here.
    commands_mod.register()
    init_events()
end)

script.on_configuration_changed(function()
    log("[multi-team-support] on_configuration_changed fired")
    force_pause.init_storage()
    team_settings.init_storage()
    storage.spawned_players          = storage.spawned_players          or {}
    storage.player_clock_start       = storage.player_clock_start       or {}
    storage.tech_research_ticks      = storage.tech_research_ticks      or {}
    storage.follow_cam               = storage.follow_cam               or {}
    storage.follow_cam_location      = storage.follow_cam_location      or {}
    storage.map_force_to_planets     = storage.map_force_to_planets     or {}
    storage.map_planet_to_force      = storage.map_planet_to_force      or {}
    storage.god_pre_remote           = storage.god_pre_remote           or {}
    storage.dangoreus                = storage.dangoreus                or {}
    storage.research_gui_location    = storage.research_gui_location    or {}
    storage.research_gui_expanded    = storage.research_gui_expanded    or {}
    storage.research_gui_diff_target = storage.research_gui_diff_target or {}
    storage.show_offline_players     = storage.show_offline_players     or {}
    storage.awards_gui_state         = storage.awards_gui_state         or {}
    storage.awards_gui_location      = storage.awards_gui_location      or {}
    storage.team_leader              = storage.team_leader              or {}
    storage.team_pool                = storage.team_pool                or {}
    storage.team_names               = storage.team_names               or {}
    storage.team_clock_start         = storage.team_clock_start         or {}
    storage.left_teams               = storage.left_teams               or {}
    -- Back-fill spawned_players for users upgrading from a version that
    -- didn't track this flag. Skip players currently in the landing pen,
    -- otherwise their pen buttons go dead (is_in_pen would return false).
    for _, player in pairs(game.players) do
        if not storage.spawned_players[player.index]
           and player.surface and player.surface.name ~= "landing-pen" then
            storage.spawned_players[player.index] = true
        end
    end
    stats_gui.invalidate_categories()
    spectator.init()
    spectator.init_storage()

    -- Re-discover milestone items in case mod combo changed
    tech_records.init_storage()
    milestones.discover_items()

    -- Invalidate Space Age detection cache so we re-probe after the mod list changed
    space_age.invalidate_cache()

    -- Rebuild planet mappings + re-apply locks. Handles: max_teams change,
    -- Space Age added/removed, or variant prototypes changing.
    planet_map.build()
    planet_map.apply_all_force_locks()

    -- Re-init dangOreus compat (may be newly added/removed)
    dangoreus.init()

    -- Rebuild open GUIs so any layout/data changes from the version bump
    -- take effect immediately instead of showing stale content.
    landing_pen.update_pen_gui_all()
    teams_gui.update_all()

    init_events()
end)

-- ─── Player Events ─────────────────────────────────────────────────────

script.on_event(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    register_nav_buttons(player)
    admin_gui.auto_populate_starter_items(player)

    if admin_gui.flag("landing_pen_enabled") then
        -- Player stays on spectator force in the landing pen.
        -- They'll claim a team slot when they click "Spawn into game".
        local spec_force = game.forces["spectator"]
        if spec_force then player.force = spec_force end
        landing_pen.place_player(player)
    else
        -- No landing pen: claim a team slot immediately and spawn
        force_utils.claim_team_slot(player)
        storage.spawned_players = storage.spawned_players or {}
        storage.spawned_players[player.index] = true
        spawn_into_world(player)
        force_utils.start_player_clock(player)
    end
    teams_gui.update_all()
end)

script.on_event(defines.events.on_player_joined_game, function(event)
    local player = game.get_player(event.player_index)
    if player then spectator.on_player_joined(player) end
    if player and landing_pen.is_in_pen(player) then
        landing_pen.place_player(player)
    end
    if player then register_nav_buttons(player) end
    if player then force_pause.on_player_joined(player) end
    storage.pending_admin_check = storage.pending_admin_check or {}
    storage.pending_admin_check[event.player_index] = game.tick + 30
    rebuild_for_connectivity(nil)
end)

script.on_event(defines.events.on_player_left_game, function(event)
    local player = game.get_player(event.player_index)
    if player then
        spectator.on_player_left(player)
        follow_cam.on_player_left(player)
        force_pause.on_player_left(player)
    end
    rebuild_for_connectivity(event.player_index)
end)

-- When a player changes force (e.g. claims a team slot from the pen), the
-- destination team may have been paused because it had no online players.
-- Kick off a resume sweep so production starts back up for the newcomer,
-- and refresh the Team Settings nav button since membership just changed.
script.on_event(defines.events.on_player_changed_force, function(event)
    local player = game.get_player(event.player_index)
    if player and player.connected then
        force_pause.on_force_changed(player)
        team_settings.refresh_nav_button(player)
        -- Rebuild any open settings panel — it's now backed by a different
        -- force (or should close if the player went back to spectator).
        if player.gui.screen.sb_team_settings_frame then
            team_settings.build_gui(player)
        end
    end
end)

script.on_event(defines.events.on_player_promoted, function(event)
    local player = game.get_player(event.player_index)
    if player and player.connected then
        admin_gui.refresh_nav_button(player)
    end
end)

script.on_event(defines.events.on_player_demoted, function(event)
    local player = game.get_player(event.player_index)
    if player then
        admin_gui.refresh_nav_button(player)
        if player.gui.screen.sb_admin_frame then
            player.gui.screen.sb_admin_frame.destroy()
        end
    end
end)

-- ─── Surface & Controller Events ───────────────────────────────────────

script.on_event(defines.events.on_player_changed_surface, function(event)
    local player = game.get_player(event.player_index)
    if player and player.connected then
        helpers.diag("on_player_changed_surface (before handlers)", player)
        if spectator.is_spectating(player)
           and player.controller_type ~= defines.controllers.remote then
            spectator.exit(player)
        end
        force_utils.bounce_if_foreign(player)
        teams_gui.build_gui(player)
        helpers.diag("on_player_changed_surface (after handlers)", player)
    end
end)

script.on_event(defines.events.on_player_controller_changed, function(event)
    local player = game.get_player(event.player_index)
    if player and player.connected then
        helpers.diag("on_player_controller_changed (before handlers, old_ctrl="
            .. tostring(event.old_type) .. ")", player)

        -- Anchor god-mode position across remote-view round-trips.
        --
        -- In Platformer mode the player has no character and lives in a god
        -- controller whose position IS the player's physical position. When
        -- they enter a remote view of another surface and press Esc, Factorio
        -- drops the god cursor onto the last-viewed surface (e.g. landing-pen)
        -- because there's no character to fall back to.
        --
        -- Workaround: when entering remote view from god, save the god's
        -- physical surface+position. When exiting remote back to god, if the
        -- physical surface changed, teleport the god back to the saved spot.
        storage.god_pre_remote = storage.god_pre_remote or {}
        if event.old_type == defines.controllers.god
           and player.controller_type == defines.controllers.remote
           and player.physical_surface and player.physical_surface.valid then
            storage.god_pre_remote[player.index] = {
                surface_name = player.physical_surface.name,
                position     = {
                    x = player.physical_position.x,
                    y = player.physical_position.y,
                },
            }
        elseif event.old_type == defines.controllers.remote
           and player.controller_type == defines.controllers.god then
            local saved = storage.god_pre_remote[player.index]
            storage.god_pre_remote[player.index] = nil
            if saved and player.physical_surface
               and player.physical_surface.name ~= saved.surface_name then
                local s = game.surfaces[saved.surface_name]
                if s and s.valid then
                    helpers.diag("god_pre_remote: restoring god to "
                        .. saved.surface_name, player)
                    player.teleport(saved.position, s)
                end
            end
        end

        spectator.on_controller_changed(player, event.old_type)
        force_utils.bounce_if_foreign(player)
        helpers.diag("on_player_controller_changed (after handlers)", player)
    end
end)

-- ─── Research Events ───────────────────────────────────────────────────

script.on_event(defines.events.on_research_finished, function(event)
    -- Handle tech records (first/fastest tracking + announcements)
    local records_changed = tech_records.on_research_finished(event)
    -- Sync quality and refresh research GUI
    force_utils.sync_quality_all_forces()
    research_gui.update_all()
    if records_changed then
        awards_gui.update_all()
    end
end)

-- ─── GUI Events ────────────────────────────────────────────────────────

script.on_event(defines.events.on_gui_click, function(event)
    local el = event.element
    if not el or not el.valid then return end

    if nav.dispatch_click(event) then return end

    -- Confirmation dialogs (leave, kick)
    if confirm_gui.on_gui_click(event) then return end

    -- Follow Cam close button (refresh teams GUI so radar tooltips update)
    if follow_cam.on_gui_click(event) then
        teams_gui.update_all()
        return
    end

    if el.name == "sb_spawn_btn" then
        local player = game.get_player(event.player_index)
        if player and landing_pen.is_in_pen(player) then
            if spectator.is_spectating(player) then
                spectator.exit(player)
            end
            -- Claim a team slot (assigns player to "team-N" force)
            local force_name = force_utils.claim_team_slot(player)
            if not force_name then return end  -- No slots available

            local default_group = game.permissions.get_group("Default")
            if default_group then default_group.add_player(player) end
            admin_gui.auto_populate_starter_items(player)
            landing_pen.grant_starter_items(player)
            landing_pen.finish_spawn(player)
            spawn_into_world(player)
            force_utils.start_player_clock(player)
            helpers.broadcast(helpers.colored_name(player.name, player.chat_color)
                .. " has joined " .. helpers.team_tag(player.force.name) .. ".")
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

    if el.name == "sb_buddy_cancel" then
        local player = game.get_player(event.player_index)
        if player and landing_pen.is_in_pen(player) then
            landing_pen.cancel_buddy_request(player)
        end
        return
    end

    if research_gui.on_gui_click(event) then return end
    if admin_gui.on_gui_click(event) then return end
    if team_settings.on_gui_click(event) then return end
    if stats_gui.on_gui_click(event) then return end
    if awards_gui.on_gui_click(event) then return end
    teams_gui.on_gui_click(event)
end)

script.on_event(defines.events.on_gui_confirmed, function(event)
    team_settings.on_gui_confirmed(event)
end)

script.on_event(defines.events.on_gui_selection_state_changed, function(event)
    if admin_gui.on_gui_selection_state_changed(event) then
        local admin_player = game.get_player(event.player_index)
        if admin_player then
            local limit = admin_gui.buddy_team_limit()
            helpers.broadcast("[Admin] " .. helpers.colored_name(admin_player.name, admin_player.chat_color) .. " set max team size to " .. limit)
        end
        landing_pen.update_pen_gui_all()
        return
    end
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
            teams_gui.build_gui(player)
            if player.gui.screen.sb_research_frame then
                research_gui.update_all()
            end
            if player.gui.screen.sb_stats_frame then
                stats_gui.build_stats_gui(player)
            end
        end
        return
    end

    if team_settings.on_gui_checked_state_changed(event) then return end

    local changed_flag = admin_gui.on_gui_checked_state_changed(event)
    if changed_flag then
        local admin_player = game.get_player(event.player_index)
        if admin_player then
            local state_str = admin_gui.flag(changed_flag) and "enabled" or "disabled"
            local label = admin_gui.get_flag_label(changed_flag)
            helpers.broadcast("[Admin] " .. helpers.colored_name(admin_player.name, admin_player.chat_color) .. " " .. state_str .. " " .. label)
        end
        if changed_flag == "buddy_join_enabled" then
            landing_pen.update_pen_gui_all()
            -- Rebuild admin GUI to show/hide team limit dropdown
            for _, p in pairs(game.players) do
                if p.connected and p.admin and p.gui.screen.sb_admin_frame then
                    admin_gui.build_admin_gui(p)
                end
            end
        end
        if changed_flag == "friendship_enabled" and not admin_gui.flag("friendship_enabled") then
            friendship.break_all()
            teams_gui.update_all()
        end
        if changed_flag == "friendship_enabled" and admin_gui.flag("friendship_enabled") then
            teams_gui.update_all()
        end
        if changed_flag == "landing_pen_enabled" and not admin_gui.flag("landing_pen_enabled") then
            for _, player in pairs(game.players) do
                if landing_pen.is_in_pen(player) then
                    local default_group = game.permissions.get_group("Default")
                    if default_group then default_group.add_player(player) end
                    landing_pen.finish_spawn(player)
                    spawn_into_world(player)
                    force_utils.start_player_clock(player)
                end
            end
            refresh_all_gameplay_guis()
        end
        return
    end
    teams_gui.on_friend_toggle(event)
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
