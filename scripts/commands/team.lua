-- scripts/commands/team.lua
-- Player-facing team commands: players, leave, rename, teams, kick.

local teams_gui    = require("gui.teams")
local helpers      = require("scripts.helpers")
local force_utils  = require("scripts.force_utils")
local landing_pen  = require("gui.landing_pen")
local spectator    = require("scripts.spectator")
local confirm      = require("gui.confirm")
local team_rename  = require("scripts.team_rename")
local team_modifiers = require("scripts.team_modifiers")
local hud_clock    = require("gui.hud_clock")

local M = {}

-- ─── Confirm Actions ──────────────────────────────────────────────────

local function perform_leave(player, _data)
    if landing_pen.is_in_pen(player) then
        player.print({"mts-cmd.already-in-pen"})
        return
    end
    if spectator.is_spectating(player) then spectator.exit(player) end
    -- Capture before remove_from_team: a solo leaver auto-disbands the team
    -- and frees the slot — pen GUIs need to refresh to show it.
    local was_solo = force_utils.force_member_count(player.force) <= 1
    if force_utils.remove_from_team(player) then
        landing_pen.return_to_pen(player)
        player.print({"mts-cmd.left-team"})
        teams_gui.update_all()
        if was_solo then landing_pen.update_pen_gui_all() end
    end
end

local function perform_kick(leader, data)
    local target = data and data.target_idx and game.get_player(data.target_idx)
    if not (target and target.valid) then
        leader.print({"mts-cmd.kick-target-gone"})
        return
    end
    if not force_utils.is_team_leader(leader) then
        leader.print({"mts-cmd.kick-no-longer-leader"})
        return
    end
    if target.force ~= leader.force then
        leader.print({"mts-cmd.kick-target-left-team",
            helpers.colored_name(target.name, target.chat_color)})
        return
    end
    if spectator.is_spectating(target) then spectator.exit(target) end
    if force_utils.remove_from_team(target) then
        landing_pen.return_to_pen(target)
        local team_tag = helpers.team_tag_with_leader(leader.force.name)
        target.print({"mts-cmd.kicked-you", team_tag,
            helpers.colored_name(leader.name, leader.chat_color)})
        leader.print({"mts-cmd.kicked-player",
            helpers.colored_name(target.name, target.chat_color), team_tag})
        teams_gui.update_all()
    end
end

confirm.register("leave", perform_leave)
confirm.register("kick",  perform_kick)

-- ─── Commands ─────────────────────────────────────────────────────────

function M.register()
    commands.add_command("t",
        {"mts-cmd.t-help"},
        function(cmd)
            local caller = cmd.player_index and game.get_player(cmd.player_index)
            if not caller then return end
            local msg = cmd.parameter
            if not msg or msg:match("^%s*$") then
                caller.print({"mts-cmd.t-usage"})
                return
            end
            local line = {"mts-cmd.team-chat-line",
                helpers.colored_name(caller.name, caller.chat_color), msg}
            for _, p in pairs(game.players) do
                if p.connected and p.force.name == caller.force.name then
                    p.print(line)
                end
            end
        end)

    commands.add_command("mts-players",
        {"mts-cmd.players-help"},
        function(cmd)
            local caller = cmd.player_index and game.get_player(cmd.player_index)
            local owners, order, owner_info = teams_gui.get_platforms_by_owner()
            local lines = {{"mts-cmd.players-header"}}
            for _, owner in ipairs(order) do
                local info = owner_info[owner]
                lines[#lines + 1] = {"mts-cmd.players-team-line",
                    helpers.team_tag(info.force_name)}
                for _, surface_info in ipairs(owners[owner]) do
                    lines[#lines + 1] = {"mts-cmd.players-surface-line",
                        surface_info.name, surface_info.gps, surface_info.location}
                end
            end
            if #order == 0 then lines[#lines + 1] = {"mts-cmd.players-none"} end
            local msg = helpers.ls_join(lines, "\n")
            if caller then caller.print(msg) else game.print(msg) end
        end)

    commands.add_command("mts-leave",
        {"mts-cmd.leave-help"},
        function(cmd)
            local caller = cmd.player_index and game.get_player(cmd.player_index)
            if not caller then game.print({"mts-cmd.player-only"}); return end
            if landing_pen.is_in_pen(caller) then
                caller.print({"mts-cmd.already-in-pen"}); return
            end
            confirm.show(caller, {
                title        = {"mts-confirm.leave-team-title",
                                helpers.team_tag(caller.force.name)},
                message      = {"mts-confirm.leave-team-message"},
                confirm_text = {"mts-confirm.leave-team-ok"},
                cancel_text  = {"mts-confirm.cancel"},
                action       = "leave",
            })
        end)

    commands.add_command("mts-rename",
        {"mts-cmd.rename-help"},
        function(cmd)
            local caller = cmd.player_index and game.get_player(cmd.player_index)
            if not caller then game.print({"mts-cmd.player-only"}); return end
            -- A missing argument is a command-usage error (distinct from an empty
            -- GUI field); everything else -- on-team/leader guard, length,
            -- uniqueness, no-op, apply, broadcast, on_team_renamed, refresh -- is
            -- the shared rule in scripts/team_rename.
            if not cmd.parameter or cmd.parameter:match("^%s*$") then
                caller.print({"mts-cmd.rename-usage"}); return
            end
            local ok, err = team_rename.attempt(caller, cmd.parameter)
            if not ok and err then caller.print(err) end
        end)

    commands.add_command("mts-teams",
        {"mts-cmd.teams-help"},
        function(cmd)
            local caller = cmd.player_index and game.get_player(cmd.player_index)
            local lines = {{"mts-cmd.teams-header"}}
            for i = 1, force_utils.max_teams() do
                local force_name = "team-" .. i
                local force = game.forces[force_name]
                if force then
                    local slot = (storage.team_pool or {})[i]
                    if slot ~= "occupied" then
                        lines[#lines + 1] = {"mts-cmd.teams-unclaimed-line", force_name}
                    else
                        local leader_idx = (storage.team_leader or {})[force_name]
                        local leader = leader_idx and game.get_player(leader_idx)
                        local leader_str = leader
                            and helpers.colored_name(leader.name, leader.chat_color)
                            or "[color=0.7,0.7,0.7]?[/color]"
                        local count = #force.players
                        lines[#lines + 1] = {"mts-cmd.teams-line",
                            force_name, helpers.team_tag(force_name), leader_str, count}
                    end
                end
            end
            local msg = helpers.ls_join(lines, "\n")
            if caller then caller.print(msg) else game.print(msg) end
        end)

    commands.add_command("mts-chat",
        {"mts-cmd.chat-help"},
        function(cmd)
            local caller = cmd.player_index and game.get_player(cmd.player_index)
            if not caller then
                game.print({"mts-cmd.player-only"}); return
            end
            hud_clock.toggle_chat_channel(caller)
        end)

    commands.add_command("mts-modifiers",
        {"mts-cmd.modifiers-help"},
        function(cmd)
            local caller = cmd.player_index and game.get_player(cmd.player_index)
            local lines
            if not team_modifiers.is_active() then
                lines = {{"mts-cmd.modifiers-competitive"}}
            else
                lines = {{"mts-cmd.modifiers-noncompetitive-header"}}
                for i = 1, force_utils.max_teams() do
                    local force_name = "team-" .. i
                    if (storage.team_pool or {})[i] == "occupied" then
                        local desc  = team_modifiers.ls_describe(force_name)
                        local badge = team_modifiers.ls_marked_badge(force_name)
                        local tag   = helpers.team_tag_with_leader(force_name)
                        local label = badge and {"", tag, " ", badge} or tag
                        lines[#lines + 1] = desc
                            and {"mts-cmd.modifiers-team-line", label, desc}
                            or  {"mts-cmd.modifiers-team-line-standard", label}
                    end
                end
            end
            local msg = helpers.ls_join(lines, "\n")
            if caller then caller.print(msg) else game.print(msg) end
        end)

    commands.add_command("mts-kick",
        {"mts-cmd.kick-help"},
        function(cmd)
            local caller = cmd.player_index and game.get_player(cmd.player_index)
            if not caller then game.print({"mts-cmd.player-only"}); return end
            if not force_utils.is_team_leader(caller) then
                caller.print({"mts-cmd.kick-not-leader"}); return
            end
            if force_utils.force_member_count(caller.force) < 2 then
                caller.print({"mts-cmd.kick-solo"}); return
            end
            local target_name = cmd.parameter
            if not target_name or target_name == "" then
                caller.print({"mts-cmd.kick-usage"}); return
            end
            target_name = target_name:match("^%s*(.-)%s*$")
            local target = game.get_player(target_name)
            if not target then
                caller.print({"mts-cmd.kick-player-not-found", target_name}); return
            end
            if target.index == caller.index then
                caller.print({"mts-cmd.kick-self"}); return
            end
            if target.force ~= caller.force then
                caller.print({"mts-cmd.kick-not-teammate",
                    helpers.colored_name(target.name, target.chat_color)}); return
            end
            confirm.show(caller, {
                title        = {"mts-confirm.kick-title", target.name},
                message      = {"mts-confirm.kick-message",
                    helpers.colored_name(target.name, target.chat_color),
                    helpers.team_tag(caller.force.name)},
                confirm_text = {"mts-confirm.kick-ok"},
                cancel_text  = {"mts-confirm.cancel"},
                action       = "kick",
                data         = {target_idx = target.index},
            })
        end)
end

return M
