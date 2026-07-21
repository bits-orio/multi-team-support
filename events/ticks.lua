-- events/ticks.lua
-- on_tick, all on_nth_tick handlers, plus map/surface/world events.

local landing_pen    = require("gui.landing_pen")
local clone_mirror   = require("compat.clone_mirror")
local dangoreus      = require("compat.dangoreus")
local claustorephobic = require("compat.claustorephobic")
local reassign_player_force = require("compat.reassign_player_force")
local surface_utils  = require("scripts.surface_utils")
local team_surfaces  = require("scripts.team_surfaces")
local spawn_labels   = require("scripts.spawn_labels")
local remote_api     = require("scripts.remote_api")
local teams_gui      = require("gui.teams")
local planet_map     = require("scripts.planet_map")
local ultracube_compat = require("compat.ultracube")
local space_is_fake  = require("compat.space_is_fake")
local gridlocked     = require("compat.gridlocked")
local milestones     = require("milestones.engine")
local awards_gui     = require("gui.awards")
local follow_cam     = require("gui.follow_cam")
local pause_control  = require("scripts.pause.control")
local chunk_trim     = require("scripts.chunk_trim")
local debug_engine   = require("scripts.debug")
local pop_text       = require("scripts.pop_text")
local platformer     = require("compat.platformer")
local voidblock      = require("compat.voidblock")
local vanilla        = require("compat.vanilla")
local mts_dimension_warp = require("compat.mts_dimension_warp")
local admin_gui      = require("gui.admin")
local force_utils    = require("scripts.force_utils")
local helpers        = require("scripts.helpers")
local lfm_hint       = require("gui.lfm_hint")
local spectator      = require("scripts.spectator")

local DISCORD_REMINDER_TICKS = 6 * 60 * 60 * 60  -- 6 hours at 60 UPS

local M = {}

--- True if any team force currently has active research (gates the throttled
--- research-progress-bar refresh).
local function any_team_researching()
    for _, force in pairs(game.forces) do
        if force_utils.is_team_force(force.name) and force.current_research then
            return true
        end
    end
    return false
end

function M.register()
    script.on_event(defines.events.on_chunk_generated, function(event)
        landing_pen.on_chunk_generated(event)
        clone_mirror.on_chunk_generated(event)
        if dangoreus.is_active() then dangoreus.on_chunk_generated(event) end
        if claustorephobic.is_active() then claustorephobic.on_chunk_generated(event) end
        reassign_player_force.on_chunk_generated(event)
    end)

    script.on_event(defines.events.on_surface_created, function(event)
        local surface = game.surfaces[event.surface_index]
        if not surface then return end
        -- Pin team variant surfaces to a per-base-planet seed BEFORE any chunk
        -- generates, so every team's copy of a planet generates identical
        -- terrain natively (outer planets aren't cloned).
        surface_utils.normalize_variant_seed(surface)
        surface_utils.on_surface_created(surface)
        local owner = surface_utils.get_owner(surface)
        if owner then
            spawn_labels.draw(owner, surface)
            -- Skip the inline raise for a surface create_team_surface is still
            -- building; it re-raises after planet association + chunk pre-gen so
            -- consumers don't observe an unassociated, ungenerated surface.
            if not team_surfaces.is_deferring(surface.name) then
                remote_api.raise_team_surface_created(surface.name, owner)
            end
            teams_gui.update_all()
        end
        planet_map.hide_base_planets_for_all()
    end)

    script.on_event(defines.events.on_force_reset, function(event)
        if event.force then planet_map.apply_force_locks(event.force) end
    end)
    script.on_event(defines.events.on_technology_effects_reset, function(event)
        if event.force then
            -- A tech-effects reset preserves research but re-points each
            -- discovery tech's unlock at the BASE planet. apply_force_locks
            -- then clean-slates the variants, so re-derive the team's unlocks
            -- from its researched discovery techs or its earned planets relock.
            planet_map.apply_force_locks(event.force)
            planet_map.reapply_discovery_unlocks(event.force)
        end
    end)

    -- Reactive correction for cross-team logistic-request planet selections.
    -- The hub's "Import from" dropdown can't be filtered per-force in Factorio
    -- 2.x. When a team-force space-platform request is edited, rewrite the
    -- slot's import_from to point at the team's own variant of the same base
    -- planet. The handler ignores ground entities (chests), whose import_from
    -- is inert residue copied from a hub. Heavy DIAG logging inside the
    -- handler — strip once verified.
    script.on_event(defines.events.on_entity_logistic_slot_changed,
        planet_map.on_logistic_slot_changed)

    -- Compat fan-out: Factorio keeps only the LAST script.on_event per event id
    -- per mod, so the compat shims can't each register these MTS custom events --
    -- they'd clobber each other and only the last-registered would fire (CC-1).
    -- One MTS-owned registration per id calls every shim's self-guarding handler
    -- in a deterministic order.
    script.on_event(remote_api.events.on_team_created, function(e)
        gridlocked.on_team_created(e)
    end)
    script.on_event(remote_api.events.on_team_released, function(e)
        ultracube_compat.on_team_released(e)   -- fresh cube + victory reset
        space_is_fake.on_team_released(e)       -- clear SiF starting-area guard
        gridlocked.on_team_released(e)          -- reset chunk-point balance
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
        script.on_nth_tick(120, dangoreus.on_nth_tick)
    end

    -- Pending teleports and admin check run every tick.
    script.on_event(defines.events.on_tick, function()
        -- Self-healing bridge registration: applies once per session even when on_init /
        -- on_configuration_changed didn't fire (plain save reload, or the bridge was added
        -- to an already-running save). Cheap no-op after the first tick.
        remote_api.ensure_bridge_registered()
        pop_text.tick(game.tick)
        lfm_hint.tick(game.tick)
        landing_pen.process_pending_teleports()
        -- Match the spawn-dispatch precedence in events/helpers.lua: MDW first.
        -- (MDW reuses the shared compat_utils teleport queue, so this drains the
        -- same storage.pending_vanilla_tp the vanilla/voidblock paths use.)
        if mts_dimension_warp.is_active() then
            mts_dimension_warp.process_pending_teleports()
        elseif platformer.is_active() then
            platformer.process_pending_teleports()
        elseif voidblock.is_active() then
            voidblock.process_pending_teleports()
        else
            vanilla.process_pending_teleports()
        end
        -- Re-apply the home-view zoom a few ticks after a spectate-exit, so the
        -- controller change settling doesn't clobber it.
        if storage.zoom_apply and next(storage.zoom_apply) then
            for idx, info in pairs(storage.zoom_apply) do
                if game.tick >= info.at then
                    local p = game.get_player(idx)
                    if p and p.connected then
                        pcall(function() p.zoom = info.zoom end)
                    end
                    storage.zoom_apply[idx] = nil
                end
            end
        end
        if storage.pending_admin_check and next(storage.pending_admin_check) then
            local done = {}
            for idx, target_tick in pairs(storage.pending_admin_check) do
                if game.tick >= target_tick then
                    done[#done + 1] = idx
                    local p = game.get_player(idx)
                    if p and p.connected then admin_gui.refresh_nav_button(p) end
                end
            end
            for _, idx in ipairs(done) do storage.pending_admin_check[idx] = nil end
        end
    end)

    script.on_nth_tick(1,     function() debug_engine.tick() end)
    script.on_nth_tick(2,     function() follow_cam.tick() end)
    -- Staggered visual wire reconnect after an API-driven unpause. Cheap no-op
    -- when nothing is pending; self-clears each force the instant it finishes.
    script.on_nth_tick(10,    function() pause_control.tick() end)
    -- Remember each player's home-view zoom so returning from spectating
    -- another team restores it (no zoom-changed event exists).
    script.on_nth_tick(20,    function() spectator.track_home_zoom() end)
    script.on_nth_tick(30,    function()
        chunk_trim.tick()
        -- Research-progress bars, refreshed at 30 ticks (0.5s) rather than 6
        -- (10 Hz). Research spans seconds-to-minutes, so a half-second cadence
        -- is visually identical while cutting the viewers x forces x queue-slot
        -- scan to a fifth (PF-10). Folded in here because on_nth_tick keys one
        -- handler per period -- a separate on_nth_tick(30) would clobber this one.
        if any_team_researching() then teams_gui.update_queue_progress_all() end
    end)
    script.on_nth_tick(300,   function()
        if milestones.tick() then awards_gui.update_all() end
    end)
    script.on_nth_tick(3600,  function() teams_gui.update_activity_labels_all() end)
    script.on_nth_tick(18000, function() surface_utils.cleanup_charts() end)
    script.on_nth_tick(DISCORD_REMINDER_TICKS, function()
        if game.tick == 0 then return end
        local discord_url = settings.global["mts_discord_url"].value
        if discord_url ~= "" then
            helpers.broadcast(
                "Join our Discord for reset notifications and to vote on the next game: " .. discord_url
            )
        end
    end)
end

return M
