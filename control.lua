-- Multi-Team Support - control.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- Bootstrap: initialises storage, wires modules, and delegates all event
-- registrations to the events/ folder.  Event handlers live there; this
-- file stays focused on lifecycle (on_init / on_load / on_configuration_changed).

local admin_gui        = require("gui.admin")
local spectator        = require("scripts.spectator")
local pause_control    = require("scripts.pause.control")
local pause_state      = require("scripts.pause.state")
local pause_wires      = require("scripts.pause.wires")
local team_settings    = require("gui.team_settings")
local chunk_trim       = require("scripts.chunk_trim")
local spawn_labels     = require("scripts.spawn_labels")
local debug_engine     = require("scripts.debug")
local pop_text         = require("scripts.pop_text")
local force_utils      = require("scripts.force_utils")
local team_clock       = require("scripts.team_clock")
local planet_map       = require("scripts.planet_map")
local tech_records     = require("scripts.tech_records")
local milestones       = require("milestones.engine")
local dangoreus        = require("compat.dangoreus")
local ultracube_compat = require("compat.ultracube")
local commands_mod     = require("scripts.commands")
local landing_pen      = require("gui.landing_pen")
local teams_gui        = require("gui.teams")
local stats_gui        = require("gui.stats")
local platform_hub_gui = require("gui.platform_hub")
local space_age        = require("scripts.space_age")
local surface_utils    = require("scripts.surface_utils")
local blueprint_lock   = require("scripts.blueprint_lock")
local global_milestones = require("scripts.global_milestones")
local remote_api        = require("scripts.remote_api")
-- Inject team_surfaces at parse time to break the team_surfaces -> team_slots
-- -> remote_api require cycle (remote_api can't require it directly, and
-- Factorio forbids require() at runtime).
remote_api.set_deferred_deps({ team_surfaces = require("scripts.team_surfaces") })
local pre_start         = require("scripts.pre_start")
require("scripts.team_disband")  -- injects remote_api.disband_impl (mts-v1 disband_team)

-- Inject starter-item delivery hooks into admin_flags. It can't require
-- remote_api itself (that closes a load-time cycle via team_clock → spectator →
-- gui.admin → admin_flags); control.lua sits outside that cycle, so it wires the
-- two together here at load time.
require("scripts.admin_flags").set_delivery_hooks{
    override = remote_api.starter_delivery_override,
    raise    = remote_api.raise_starter_items_added,
}

local ev_ticks            = require("events.ticks")
local ev_player_lifecycle = require("events.player_lifecycle")
local ev_player_force     = require("events.player_force")
local ev_player_surface   = require("events.player_surface")
local ev_research         = require("events.research")
local ev_gui_clicks       = require("events.gui_clicks")
local ev_gui_state        = require("events.gui_state")
local ev_chat             = require("events.chat")

local function init_events()
    ev_ticks.register()
    ev_player_lifecycle.register()
    ev_player_force.register()
    ev_player_surface.register()
    ev_research.register()
    ev_gui_clicks.register()
    ev_gui_state.register()
    ev_chat.register()
    global_milestones.register()
    platform_hub_gui.register()
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
    storage.pending_spawn_pop        = {}
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
    storage.seen_players             = {}
    storage.player_last_seen         = {}
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
    storage.return_button_location   = {}
    global_milestones.init_storage()
    admin_gui.get_flags()
    spectator.init()
    spectator.init_storage()
    pause_state.init_storage()
    pause_wires.init_storage()
    team_clock.init_storage()
    team_settings.init_storage()
    chunk_trim.init_storage()
    spawn_labels.init_storage()
    debug_engine.init_storage()
    pop_text.init_storage()

    -- Pre-create all team forces and build Space Age planet maps.
    force_utils.create_team_pool()
    planet_map.build()
    planet_map.refresh_discovery_techs()
    planet_map.apply_all_force_locks()
    planet_map.reapply_all_discovery_unlocks()

    tech_records.init_storage()
    milestones.discover_items()
    dangoreus.init()
    ultracube_compat.on_init()
    blueprint_lock.apply()
    pre_start.ensure_permission_group()
    pre_start.init_storage()

    commands_mod.register()
    init_events()
    remote_api.ensure_bridge_registered()
end)

script.on_load(function()
    -- on_load must NOT write to storage (causes multiplayer desyncs).
    commands_mod.register()
    init_events()
end)

script.on_configuration_changed(function()
    log("[multi-team-support] on_configuration_changed fired")
    pause_state.init_storage()
    pause_wires.init_storage()
    team_clock.init_storage()
    team_settings.init_storage()
    chunk_trim.init_storage()
    spawn_labels.init_storage()
    debug_engine.init_storage()
    pop_text.init_storage()
    remote_api.ensure_bridge_registered()
    remote_api.validate_delivery_override()  -- drop override if its consumer mod was removed

    -- Resume any team still marked paused across a config change, via the
    -- power-disable pause API so both power sources and visual wires restore.
    -- TODO(P2 docking): skip teams that are intentionally docked once docking
    -- lands, so a mod update doesn't thaw a parked team.
    for fn in pairs(storage.paused_forces or {}) do
        local force = game.forces[fn]
        if force and force.valid then
            local names = {}
            for _, s in pairs(game.surfaces) do
                if s.valid and surface_utils.get_owner(s) == fn then
                    names[#names + 1] = s.name
                end
            end
            pause_control.unpause_team(fn, names)
        end
    end
    storage.team_settings = nil

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
    storage.return_button_location   = storage.return_button_location   or {}
    global_milestones.init_storage()
    storage.awards_gui_state         = storage.awards_gui_state         or {}
    storage.awards_gui_location      = storage.awards_gui_location      or {}
    storage.team_leader              = storage.team_leader              or {}
    storage.team_pool                = storage.team_pool                or {}
    storage.team_names               = storage.team_names               or {}
    storage.team_clock_start         = storage.team_clock_start         or {}
    storage.left_teams               = storage.left_teams               or {}
    storage.seen_players             = storage.seen_players             or {}
    storage.player_last_seen         = storage.player_last_seen         or {}

    -- Back-fill seen_players so existing players aren't greeted as new after an update.
    for _, player in pairs(game.players) do
        storage.seen_players[player.index] = true
    end
    -- Back-fill spawned_players for saves upgrading from a version without this flag.
    for _, player in pairs(game.players) do
        if not storage.spawned_players[player.index]
           and player.surface and player.surface.name ~= "landing-pen" then
            storage.spawned_players[player.index] = true
        end
    end
    -- Start the per-team online clock from this upgrade onward (no retroactive
    -- back-fill): stamp online_since for teams that already have members online.
    for slot, status in pairs(storage.team_pool or {}) do
        if status == "occupied" then team_clock.refresh("team-" .. slot) end
    end

    stats_gui.invalidate_categories()
    spectator.init()
    spectator.init_storage()
    tech_records.init_storage()
    milestones.discover_items()
    space_age.invalidate_cache()
    planet_map.build()
    planet_map.refresh_discovery_techs()
    planet_map.apply_all_force_locks()
    planet_map.reapply_all_discovery_unlocks()
    dangoreus.init()
    ultracube_compat.on_init()
    blueprint_lock.apply()
    pre_start.ensure_permission_group()
    pre_start.init_storage()
    landing_pen.update_pen_gui_all()
    teams_gui.update_all()

    -- Backfill or refresh spawn labels for saves upgrading from older versions.
    for _, surface in pairs(game.surfaces) do
        if surface.valid then
            local owner_fn = surface_utils.get_owner(surface)
            if owner_fn then spawn_labels.draw(owner_fn, surface) end
        end
    end

    init_events()
end)
