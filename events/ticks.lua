-- events/ticks.lua
-- on_tick, all on_nth_tick handlers, plus map/surface/world events.

local h              = require("events.helpers")
local landing_pen    = require("gui.landing_pen")
local clone_mirror   = require("compat.clone_mirror")
local dangoreus      = require("compat.dangoreus")
local surface_utils  = require("scripts.surface_utils")
local spawn_labels   = require("scripts.spawn_labels")
local remote_api     = require("scripts.remote_api")
local teams_gui      = require("gui.teams")
local planet_map     = require("scripts.planet_map")
local ultracube_compat = require("compat.ultracube")
local milestones     = require("milestones.engine")
local awards_gui     = require("gui.awards")
local follow_cam     = require("gui.follow_cam")
local force_pause    = require("scripts.force_pause")
local chunk_trim     = require("scripts.chunk_trim")
local debug_engine   = require("scripts.debug")
local pop_text       = require("scripts.pop_text")
local platformer     = require("compat.platformer")
local voidblock      = require("compat.voidblock")
local vanilla        = require("compat.vanilla")
local admin_gui      = require("gui.admin")
local force_utils    = require("scripts.force_utils")
local team_settings  = require("gui.team_settings")
local helpers        = require("scripts.helpers")

local DISCORD_REMINDER_TICKS = 6 * 60 * 60 * 60  -- 6 hours at 60 UPS

local M = {}

function M.register()
    script.on_event(defines.events.on_chunk_generated, function(event)
        landing_pen.on_chunk_generated(event)
        clone_mirror.on_chunk_generated(event)
        if dangoreus.is_active() then dangoreus.on_chunk_generated(event) end
    end)

    script.on_event(defines.events.on_surface_created, function(event)
        local surface = game.surfaces[event.surface_index]
        if not surface then return end
        surface_utils.on_surface_created(surface)
        local owner = surface_utils.get_owner(surface)
        if owner then
            spawn_labels.draw(owner, surface)
            remote_api.raise_team_surface_created(surface.name, owner)
            teams_gui.update_all()
        end
        planet_map.hide_base_planets_for_all()
    end)

    script.on_event(defines.events.on_force_reset, function(event)
        if event.force then planet_map.apply_force_locks(event.force) end
    end)
    script.on_event(defines.events.on_technology_effects_reset, function(event)
        if event.force then planet_map.apply_force_locks(event.force) end
    end)

    -- Ultracube compat: drive player setup and force-slot recycling.
    ultracube_compat.register_events()

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
        pop_text.tick(game.tick)
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
                    if p and p.connected then admin_gui.refresh_nav_button(p) end
                end
            end
            for _, idx in ipairs(done) do storage.pending_admin_check[idx] = nil end
        end
    end)

    script.on_nth_tick(1,     function() debug_engine.tick() end)
    script.on_nth_tick(2,     function() follow_cam.tick() end)
    script.on_nth_tick(6,     function()
        for _, force in pairs(game.forces) do
            if force_utils.is_team_force(force.name) and force.current_research then
                teams_gui.update_queue_progress_all()
                return
            end
        end
    end)
    script.on_nth_tick(10,    function() force_pause.tick() end)
    script.on_nth_tick(30,    function() chunk_trim.tick() end)
    script.on_nth_tick(60,    function()
        for force_name, leader_idx in pairs(storage.team_leader or {}) do
            local force  = game.forces[force_name]
            local leader = game.get_player(leader_idx)
            if force and force.valid and leader and leader.valid and leader.connected then
                local c, fc = leader.color, force.custom_color
                if not fc
                    or math.abs(c.r - fc.r) > 0.001
                    or math.abs(c.g - fc.g) > 0.001
                    or math.abs(c.b - fc.b) > 0.001
                then
                    force.custom_color = c
                    spawn_labels.refresh_for_force(force_name)
                    h.refresh_all_gameplay_guis()
                    awards_gui.update_all()
                    follow_cam.rebuild_all()
                    team_settings.update_all_for_force(force_name)
                end
            end
        end
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
