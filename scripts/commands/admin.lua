-- scripts/commands/admin.lua
-- Admin-only commands: disband, pause, resume, trim.

local teams_gui    = require("gui.teams")
local teams_data   = require("gui.teams_data")
local helpers      = require("scripts.helpers")
local force_utils  = require("scripts.force_utils")
local landing_pen  = require("gui.landing_pen")
local spectator    = require("scripts.spectator")
local confirm      = require("gui.confirm")
local pause_control = require("scripts.pause.control")
local surface_utils = require("scripts.surface_utils")
local chunk_trim   = require("scripts.chunk_trim")
local color_fix    = require("scripts.color_fix")

local M = {}

-- Collect the names of every surface a force owns, so the pause orchestrator
-- (airtight power freeze + visual wire layer) can act on them. Mirrors the
-- mts-v1 list_team_surfaces filter (surface_utils.get_owner).
local function owned_surface_names(force_name)
    local out = {}
    for _, surface in pairs(game.surfaces) do
        if surface.valid and surface_utils.get_owner(surface) == force_name then
            out[#out + 1] = surface.name
        end
    end
    return out
end

-- ─── Confirm Action ───────────────────────────────────────────────────

local function perform_disband(admin_player, data)
    local force_name = data and data.force_name
    local force = force_name and game.forces[force_name]
    if not force then
        admin_player.print({"mts-cmd.disband-team-gone"}); return
    end
    local slot = helpers.team_slot(force_name)
    if not slot or (storage.team_pool or {})[slot] ~= "occupied" then
        admin_player.print({"mts-cmd.disband-slot-freed"}); return
    end

    -- The dialog may have sat open while the team it described disbanded and a
    -- NEW team claimed the same slot. The generation captured at show time
    -- detects that recycle, so Confirm can never hit a team the admin never saw.
    local current_gen = (storage.team_slot_generation or {})[slot] or 0
    if data and data.slot_generation ~= nil and data.slot_generation ~= current_gen then
        admin_player.print({"mts-cmd.disband-slot-recycled", slot})
        return
    end

    local team_tag = helpers.team_tag_with_leader(force_name)
    -- Restore any member spectating away (so they are included below and sent to
    -- the pen, not orphaned onto the recycled slot) and exit outside viewers.
    spectator.exit_all_for_force(force_name)
    local members = {}
    for _, member in pairs(force.players) do members[#members + 1] = member end
    for _, member in ipairs(members) do
        if spectator.is_spectating(member) then spectator.exit(member) end
        storage.left_teams = storage.left_teams or {}
        storage.left_teams[member.index] = storage.left_teams[member.index] or {}
        storage.left_teams[member.index][force_name] = true

        local spec_force = game.forces["spectator"]
        if spec_force then member.force = spec_force end

        if member.connected then
            landing_pen.return_to_pen(member)
            member.print({"mts-chat.team-disbanded-member", team_tag})
        else
            -- Offline players can't teleport. Clear spawned flag so they land
            -- in the pen on reconnect.
            storage.spawned_players = storage.spawned_players or {}
            storage.spawned_players[member.index] = nil
        end
    end

    force_utils.cleanup_force_surfaces(force_name)
    force_utils.release_team_slot(force_name)

    helpers.broadcast({"mts-chat.team-disbanded-broadcast", team_tag})
    teams_gui.update_all()
    landing_pen.update_pen_gui_all()
    admin_player.print({"mts-cmd.disband-done", team_tag})
end

confirm.register("disband", perform_disband)

-- ─── Commands ─────────────────────────────────────────────────────────

function M.register()
    commands.add_command("mts-disband",
        {"mts-cmd.disband-help"},
        function(cmd)
            local caller = cmd.player_index and game.get_player(cmd.player_index)
            if not caller then game.print({"mts-cmd.player-only"}); return end
            if not caller.admin then caller.print({"mts-cmd.disband-admin-only"}); return end

            local param = cmd.parameter
            if not param or param == "" then
                caller.print({"mts-cmd.disband-usage"}); return
            end
            param = param:match("^%s*(.-)%s*$")
            local force_name = param:match("^team%-%d+$") and param
                or tonumber(param) and ("team-" .. param)
            if not force_name then
                caller.print({"mts-cmd.disband-invalid-team"}); return
            end
            local slot = helpers.team_slot(force_name)
            if not slot or not game.forces[force_name] then
                caller.print({"mts-cmd.team-not-exists", force_name}); return
            end
            if (storage.team_pool or {})[slot] ~= "occupied" then
                caller.print({"mts-cmd.disband-slot-not-occupied", slot}); return
            end

            local force = game.forces[force_name]
            local count = force_utils.force_member_count(force)

            -- Identify the team unambiguously: renamed teams (e.g. slot 1 calling
            -- itself "Team 2") make name-only confirmation dangerously easy to
            -- misread, so spell out slot, leader, and last activity.
            local members = teams_data.collect_team_members(force)
            local leader  = members.leader
            -- "★ <name>" is symbol + rich text only (no translatable words), so
            -- composing it in Lua and passing it as a parameter is safe.
            local leader_line = (leader and leader.valid)
                and ("\xE2\x98\x85 " .. helpers.colored_name(leader.name, leader.chat_color))
                or {"mts-confirm.disband-no-leader"}
            local activity = teams_data.ls_activity_info(members.members)
            local last_active = activity
                and (activity.any_online and {"mts-confirm.disband-online-now"} or activity.ago_text)
                or {"mts-confirm.disband-never-active"}
            confirm.show(caller, {
                title        = {"mts-confirm.disband-title", helpers.team_tag(force_name), slot},
                message      = {"mts-confirm.disband-message", helpers.team_tag(force_name),
                    slot, force_name, leader_line, last_active, count},
                confirm_text = {"mts-confirm.disband-ok"},
                cancel_text  = {"mts-confirm.cancel"},
                action       = "disband",
                data         = {
                    force_name      = force_name,
                    slot_generation = (storage.team_slot_generation or {})[slot] or 0,
                },
            })
        end)

    commands.add_command("mts-resume",
        {"mts-cmd.resume-help"},
        function(cmd)
            local caller = cmd.player_index and game.get_player(cmd.player_index)
            if not caller then game.print({"mts-cmd.player-only"}); return end
            if not caller.admin then caller.print({"mts-cmd.resume-admin-only"}); return end

            local param = cmd.parameter
            if not param or param == "" then
                caller.print({"mts-cmd.resume-usage"}); return
            end
            param = param:match("^%s*(.-)%s*$")
            local force_name = param:match("^team%-%d+$") and param
                or tonumber(param) and ("team-" .. param)
            if not force_name or not game.forces[force_name] then
                caller.print({"mts-cmd.team-not-exists", param}); return
            end
            if not pause_control.unpause_team(force_name, owned_surface_names(force_name)) then
                caller.print({"mts-cmd.resume-not-team", force_name}); return
            end
            caller.print({"mts-cmd.resume-started", helpers.team_tag_with_leader(force_name)})
        end)

    commands.add_command("mts-pause",
        {"mts-cmd.pause-help"},
        function(cmd)
            local caller = cmd.player_index and game.get_player(cmd.player_index)
            if not caller then game.print({"mts-cmd.player-only"}); return end
            if not caller.admin then caller.print({"mts-cmd.pause-admin-only"}); return end

            local param = cmd.parameter
            if not param or param == "" then
                caller.print({"mts-cmd.pause-usage"}); return
            end
            param = param:match("^%s*(.-)%s*$")
            local force_name = param:match("^team%-%d+$") and param
                or tonumber(param) and ("team-" .. param)
            if not force_name or not game.forces[force_name] then
                caller.print({"mts-cmd.team-not-exists", param}); return
            end
            if not pause_control.pause_team(force_name, owned_surface_names(force_name)) then
                caller.print({"mts-cmd.pause-not-team", force_name}); return
            end
            caller.print({"mts-cmd.pause-started",
                helpers.team_tag_with_leader(force_name), force_name})
        end)

    commands.add_command("mts-trim",
        {"mts-cmd.trim-help"},
        function(cmd)
            local caller = cmd.player_index and game.get_player(cmd.player_index)
            if not caller then game.print({"mts-cmd.player-only"}); return end
            if not caller.admin then caller.print({"mts-cmd.trim-admin-only"}); return end

            local tokens = {}
            for tok in (cmd.parameter or ""):gmatch("%S+") do tokens[#tokens + 1] = tok end

            local team_force, i = nil, 1
            if tokens[1] and tokens[1]:match("^team%-%d+$") then
                team_force = tokens[1]; i = 2
            end

            local entity_buffer, player_buffer
            if tokens[i] then
                entity_buffer = tonumber(tokens[i])
                if not entity_buffer or entity_buffer < 0 or entity_buffer > 100 then
                    caller.print({"mts-cmd.trim-entity-buffer-range"}); return
                end
            end
            if tokens[i + 1] then
                player_buffer = tonumber(tokens[i + 1])
                if not player_buffer or player_buffer < 0 or player_buffer > 100 then
                    caller.print({"mts-cmd.trim-player-buffer-range"}); return
                end
            end

            if team_force and not game.forces[team_force] then
                caller.print({"mts-cmd.team-not-exists", team_force}); return
            end

            local ok, count, err = chunk_trim.start{
                team_force    = team_force,
                entity_buffer = entity_buffer,
                player_buffer = player_buffer,
                caller_idx    = caller.index,
            }
            if not ok then caller.print(err or {"mts-cmd.trim-start-failed"}); return end
            caller.print({"mts-cmd.trim-queued", count})
        end)

    commands.add_command("mts-fixcolors",
        {"mts-cmd.fixcolors-help"},
        function(cmd)
            local caller = cmd.player_index and game.get_player(cmd.player_index)
            if not caller then game.print({"mts-cmd.player-only"}); return end
            if not caller.admin then caller.print({"mts-cmd.fixcolors-admin-only"}); return end
            color_fix.fix_all(caller)
        end)
end

return M
