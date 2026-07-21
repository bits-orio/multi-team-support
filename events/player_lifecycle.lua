-- events/player_lifecycle.lua
-- on_player_created, on_player_joined_game, on_player_left_game

local h                 = require("events.helpers")
local helpers           = require("scripts.helpers")
local admin_gui         = require("gui.admin")
local landing_pen       = require("gui.landing_pen")
local spectator         = require("scripts.spectator")
local force_utils       = require("scripts.force_utils")
local follow_cam        = require("gui.follow_cam")
local teams_gui         = require("gui.teams")
local remote_api        = require("scripts.remote_api")
local team_clock        = require("scripts.team_clock")
local start_playing_gui = require("gui.start_playing_gui")
local color_fix         = require("scripts.color_fix")
local team_color        = require("scripts.team_color")

local M = {}

function M.register()
    -- Player colour changes are event-driven in 2.1 (replaced the 60-tick
    -- poll). Order matters: color_fix runs first so a leader's force adopts
    -- the FIXED (readable/distinct) colour, not the raw one; color_fix's own
    -- corrective write echoes back through this event and is suppressed by
    -- its color_fix_last value-compare.
    script.on_event(defines.events.on_player_color_changed, function(event)
        local player = game.get_player(event.player_index)
        if not (player and player.valid) then return end
        color_fix.on_color_changed(player)
        team_color.adopt_if_leader(player)
    end)

    script.on_event(defines.events.on_player_created, function(event)
        local player = game.get_player(event.player_index)
        h.register_nav_buttons(player)
        admin_gui.auto_populate_starter_items(player)

        -- With a delivery override (e.g. Brave New MTS), starter items go to the
        -- team's logistic chests, not the player. auto_populate (above) has just
        -- captured the map's default loadout into the admin list, so now empty the
        -- character: the player should arrive in the pen / on their team carrying
        -- nothing.
        if player and player.character and remote_api.starter_delivery_override() then
            player.character.clear_items_inside()
        end

        if admin_gui.flag("landing_pen_enabled") then
            local spec_force = game.forces["spectator"]
            if spec_force then player.force = spec_force end
            landing_pen.place_player(player)
        else
            -- The auto-claim on first connect coincides with on_player_joined_game's
            -- team-aware bridge message, so flag it to suppress the duplicate team-join.
            storage.odb_suppress_claim = storage.odb_suppress_claim or {}
            storage.odb_suppress_claim[player.index] = true
            local force_name = force_utils.claim_team_slot(player)
            if not force_name then
                -- Every team slot is full. Do NOT fall through to spawn_into_world
                -- here: the player is still on the built-in "player" force, which
                -- would strand them on a personal "player-nauvis" clone surface
                -- with no team. Route them into the landing pen instead (it holds
                -- unlimited players) so they can wait for a slot or request to
                -- join a recruiting team; the pen shows a capacity notice.
                storage.odb_suppress_claim[player.index] = nil
                local spec_force = game.forces["spectator"]
                if spec_force then player.force = spec_force end
                landing_pen.place_player(player)
            else
                storage.spawned_players = storage.spawned_players or {}
                storage.spawned_players[player.index] = true
                storage.pending_spawn_pop = storage.pending_spawn_pop or {}
                storage.pending_spawn_pop[player.index] = force_name
                h.spawn_into_world(player)
                force_utils.start_player_clock(player)
                team_clock.refresh(force_name)
            end
        end
        teams_gui.update_all()
    end)

    script.on_event(defines.events.on_player_joined_game, function(event)
        local player = game.get_player(event.player_index)
        if player then
            color_fix.on_joined(player)
            -- Direct dispatch: a clean-arriving colour writes nothing (no event
            -- echo), yet the force colour may still have drifted while the
            -- leader was away -- adoption must not depend on the event.
            team_color.adopt_if_leader(player)
        end
        if player then spectator.on_player_joined(player) end
        if player then
            if landing_pen.is_in_pen(player) then
                landing_pen.place_player(player)
            else
                -- Reconcile the space-map gate from pen STATE on every
                -- reconnect: offline transitions (kick while offline, pen
                -- disable, config-changed back-fill) can bypass finish_spawn,
                -- and the gate's pcall would mask a rejected offline write --
                -- without this, a stuck gate would be permanent.
                landing_pen.set_space_map_gate(player, false)
            end
        end
        if player then h.register_nav_buttons(player) end
        -- Rebuild the Start Playing frame for players reconnecting during pre-start.
        if player then start_playing_gui.rebuild_if_pending(player) end
        storage.pending_admin_check = storage.pending_admin_check or {}
        storage.pending_admin_check[event.player_index] = game.tick + 30
        h.rebuild_for_connectivity(nil)

        if player then
            storage.seen_players = storage.seen_players or {}
            local discord_url = settings.global["mts_discord_url"].value
            if not storage.seen_players[player.index] then
                storage.seen_players[player.index] = true
                local msg = "Welcome " .. player.name .. "!"
                if discord_url ~= "" then
                    msg = msg .. " Join our Discord for reset notifications: " .. discord_url
                end
                helpers.broadcast(msg)
                -- Announce any teams currently recruiting so new players know where to look.
                if admin_gui.flag("buddy_join_enabled") and admin_gui.flag("landing_pen_enabled") then
                    storage.team_looking_for_more = storage.team_looking_for_more or {}
                    local lfm_tags = {}
                    for i = 1, force_utils.max_teams() do
                        local fn = "team-" .. i
                        if (storage.team_pool or {})[i] == "occupied"
                           and storage.team_looking_for_more[fn] then
                            lfm_tags[#lfm_tags + 1] = helpers.team_tag(fn)
                        end
                    end
                    if #lfm_tags > 0 then
                        helpers.broadcast("Teams looking for more players: "
                            .. table.concat(lfm_tags, ", ") .. ".")
                    end
                end
            else
                local msg
                if force_utils.is_team_force(player.force.name) then
                    msg = "Welcome back " .. player.name .. " " .. helpers.team_tag_with_leader(player.force.name) .. "!"
                else
                    msg = "Welcome back " .. player.name .. "!"
                end
                helpers.broadcast(msg)
                -- If the returning player lands in the pen, tell them which teams are recruiting.
                if landing_pen.is_in_pen(player)
                   and admin_gui.flag("buddy_join_enabled")
                   and admin_gui.flag("landing_pen_enabled") then
                    storage.team_looking_for_more = storage.team_looking_for_more or {}
                    local lfm_tags = {}
                    for i = 1, force_utils.max_teams() do
                        local fn = "team-" .. i
                        if (storage.team_pool or {})[i] == "occupied"
                           and storage.team_looking_for_more[fn] then
                            lfm_tags[#lfm_tags + 1] = helpers.team_tag(fn)
                        end
                    end
                    if #lfm_tags > 0 then
                        helpers.broadcast("Teams looking for more players: "
                            .. table.concat(lfm_tags, ", ") .. ".")
                    end
                end
            end

            -- Team-aware connect announcement to the Open Discord Bridge (replaces the
            -- bridge's team-less baseline player_joined, which we disable on init).
            remote_api.emit_player_joined(player)

            -- Resume the team's online clock if this is the first member back.
            team_clock.refresh(player.force.name)
        end
    end)

    -- Re-fit a maximized follow cam when the player resizes the window or
    -- changes UI scale, so it keeps filling the screen.
    local function refit_follow_cam(event)
        local player = game.get_player(event.player_index)
        if player then follow_cam.on_display_changed(player) end
    end
    script.on_event(defines.events.on_player_display_resolution_changed, refit_follow_cam)
    script.on_event(defines.events.on_player_display_scale_changed, refit_follow_cam)

    script.on_event(defines.events.on_player_left_game, function(event)
        local player = game.get_player(event.player_index)
        if player then
            -- Team-aware disconnect announcement to the bridge (replaces the team-less
            -- baseline player_left). Emitted while the player's force is still their team.
            remote_api.emit_player_left(player)
            spectator.on_player_left(player)
            follow_cam.on_player_left(player)
            storage.player_last_seen = storage.player_last_seen or {}
            storage.player_last_seen[player.index] = game.tick
            -- Freeze the team's online clock if this was the last member online.
            -- Exclude the leaver: the engine may not have dropped them from
            -- connected_players yet at this point.
            team_clock.refresh(spectator.get_effective_force(player), player.index)
        end
        h.rebuild_for_connectivity(event.player_index)
    end)
end

return M
