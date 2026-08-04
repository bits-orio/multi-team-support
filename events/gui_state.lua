-- events/gui_state.lua
-- on_gui_confirmed, on_gui_selection_state_changed, on_gui_elem_changed,
-- on_gui_closed, on_gui_checked_state_changed

local h             = require("events.helpers")
local team_settings = require("gui.team_settings")
local admin_gui     = require("gui.admin")
local landing_pen   = require("gui.landing_pen")
local research_gui  = require("gui.research")
local welcome_gui   = require("gui.welcome")
local helpers       = require("scripts.helpers")
local spectator     = require("scripts.spectator")
local teams_gui     = require("gui.teams")
local stats_gui     = require("gui.stats")
local awards_gui    = require("gui.awards")
local friendship    = require("gui.friendship")
local force_utils   = require("scripts.force_utils")
local blueprint_lock = require("scripts.blueprint_lock")
local follow_cam    = require("gui.follow_cam")
local team_modifiers = require("scripts.team_modifiers")
local hud_clock     = require("gui.hud_clock")

local M = {}

function M.register()
    script.on_event(defines.events.on_gui_confirmed, function(event)
        admin_gui.on_gui_confirmed(event)
        team_settings.on_gui_confirmed(event)
    end)

    script.on_event(defines.events.on_gui_selection_state_changed, function(event)
        if admin_gui.on_gui_selection_state_changed(event) then
            local p = game.get_player(event.player_index)
            local new_limit = admin_gui.buddy_team_limit()
            if p then
                helpers.broadcast("[Admin] " .. helpers.colored_name(p.name, p.chat_color)
                    .. " set max team size to " .. new_limit)
            end
            -- Auto-clear LFM for any team whose current size meets or exceeds the new limit.
            storage.team_looking_for_more = storage.team_looking_for_more or {}
            storage.team_pool = storage.team_pool or {}
            for i = 1, force_utils.max_teams() do
                local fn = "team-" .. i
                if storage.team_pool[i] == "occupied" and storage.team_looking_for_more[fn] then
                    local force = game.forces[fn]
                    if force and #force.players >= new_limit then
                        storage.team_looking_for_more[fn] = nil
                        helpers.broadcast("[Team] " .. helpers.team_tag(fn)
                            .. " is no longer recruiting (team size limit reached).")
                        team_settings.update_all_for_force(fn)
                    end
                end
            end
            landing_pen.update_pen_gui_all()
        end
    end)

    script.on_event(defines.events.on_gui_elem_changed, function(event)
        stats_gui.on_gui_elem_changed(event)
    end)

    script.on_event(defines.events.on_gui_text_changed, function(event)
        if awards_gui.on_gui_text_changed(event) then return end
        if team_settings.on_gui_text_changed(event) then return end
    end)

    script.on_event(defines.events.on_gui_switch_state_changed, function(event)
        awards_gui.on_gui_switch_state_changed(event)
    end)

    script.on_event(defines.events.on_gui_closed, function(event)
        if follow_cam.on_gui_closed(event) then return end
        if research_gui.on_gui_closed(event) then return end
        welcome_gui.on_gui_closed(event)
        -- Pressing Esc on a space-platform hub closes the hub UI instead of
        -- exiting remote view. Detect the close and exit spectator ourselves
        -- so one keystroke does what the player expects.
        if event.gui_type == defines.gui_type.entity then
            local entity = event.entity
            if entity and entity.valid and entity.type == "space-platform-hub" then
                local p = game.get_player(event.player_index)
                if p and spectator.is_spectating(p) then
                    spectator.exit(p)
                    teams_gui.build_gui(p)
                end
            end
        end
    end)

    script.on_event(defines.events.on_gui_checked_state_changed, function(event)
        local el = event.element
        if el and el.valid and el.name == "sb_show_offline_toggle" then
            local player = game.get_player(event.player_index)
            if player then
                helpers.toggle_show_offline(player)
                if player.gui.screen.sb_platforms_frame then teams_gui.build_gui(player) end
                if player.gui.screen.sb_research_frame  then research_gui.update_all() end
                if player.gui.screen.sb_stats_frame     then stats_gui.build_stats_gui(player) end
            end
            return
        end

        -- Per-team modifier checkboxes (admin GUI, non-competitive mode).
        if el and el.valid and el.tags and el.tags.sb_team_modifier then
            local admin_player = game.get_player(event.player_index)
            if admin_player and admin_player.admin then
                local changed = team_modifiers.set(
                    el.tags.sb_target_force, el.tags.sb_team_modifier,
                    el.state, admin_player)
                if changed then
                    teams_gui.update_all()   -- card modifier lines
                    hud_clock.update_all()   -- "non-competitive · <modifier>" tags
                    -- Rebuild every open admin panel so the [non-competitive]
                    -- badge next to the team name appears immediately (for
                    -- the clicking admin and any other admin watching).
                    for _, p in pairs(game.players) do
                        if p.connected and p.admin and p.gui.screen.sb_admin_frame then
                            admin_gui.build_admin_gui(p)
                        end
                    end
                else
                    -- Rejected (e.g. mode raced off) — snap the checkbox back.
                    admin_gui.build_admin_gui(admin_player)
                end
            end
            return
        end

        -- Veto leaving non-competitive mode while any team is MARKED
        -- non-competitive (it ever had a modifier — removing it doesn't
        -- clear the mark; only disbanding the team does). An accidental
        -- enable that never marked a team toggles off freely. Checked
        -- BEFORE the generic flag handler so neither the flag flip nor its
        -- "[Admin] ... disabled ..." broadcast happens.
        if el and el.valid and el.tags
           and el.tags.sb_admin_flag == "non_competitive_enabled"
           and not el.state then
            local reason = team_modifiers.disable_blocked_reason()
            if reason then
                local admin_player = game.get_player(event.player_index)
                if admin_player then
                    admin_player.print(reason)
                    admin_gui.build_admin_gui(admin_player)  -- snap checkbox back on
                end
                return
            end
        end

        local changed_flag = admin_gui.on_gui_checked_state_changed(event)
        if changed_flag then
            local admin_player = game.get_player(event.player_index)
            if admin_player then
                local state_str = admin_gui.flag(changed_flag) and "enabled" or "disabled"
                local label = admin_gui.get_flag_label(changed_flag)
                helpers.broadcast("[Admin] "
                    .. helpers.colored_name(admin_player.name, admin_player.chat_color)
                    .. " " .. state_str .. " " .. label)
            end
            if changed_flag == "buddy_join_enabled" then
                landing_pen.update_pen_gui_all()
                for _, p in pairs(game.players) do
                    if p.connected and p.admin and p.gui.screen.sb_admin_frame then
                        admin_gui.build_admin_gui(p)
                    end
                end
            end
            if changed_flag == "friendship_enabled" then
                if not admin_gui.flag("friendship_enabled") then friendship.break_all() end
                teams_gui.update_all()
            end
            if changed_flag == "landing_pen_enabled" and not admin_gui.flag("landing_pen_enabled") then
                for _, player in pairs(game.players) do
                    if landing_pen.is_in_pen(player) then
                        local default_group = game.permissions.get_group("Default")
                        if default_group then default_group.add_player(player) end
                        landing_pen.finish_spawn(player)
                        storage.pending_spawn_pop = storage.pending_spawn_pop or {}
                        storage.pending_spawn_pop[player.index] = player.force.name
                        h.spawn_into_world(player)
                        force_utils.start_player_clock(player)
                    end
                end
                h.refresh_all_gameplay_guis()
            end
            if changed_flag == "allow_blueprint_imports" then
                blueprint_lock.apply()
            end
            if changed_flag == "non_competitive_enabled" then
                if admin_gui.flag("non_competitive_enabled") then
                    helpers.broadcast("[color=1,0.65,0]Per-team modifiers are now"
                        .. " allowed — team times are no longer directly comparable."
                        .. " Once a team receives a modifier it is marked"
                        .. " non-competitive, and this mode cannot be turned off"
                        .. " as long as any such team exists (only disbanding"
                        .. " clears the mark). See the Teams panel or"
                        .. " /mts-modifiers for every team's settings.[/color]")
                else
                    team_modifiers.revert_all()
                end
                -- Mode is surfaced in the HUD tag, Teams GUI title, and the
                -- admin panel's modifier section — refresh all three.
                hud_clock.update_all()
                teams_gui.update_all()
                for _, p in pairs(game.players) do
                    if p.connected and p.admin and p.gui.screen.sb_admin_frame then
                        admin_gui.build_admin_gui(p)
                    end
                end
            end
            return
        end
        teams_gui.on_friend_toggle(event)
    end)
end

return M
