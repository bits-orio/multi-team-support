-- Multi-Team Support - commands.lua
-- Author: bits-orio
-- License: MIT
--
-- Registers console commands:
--   /mts-players  - list all players and their surfaces with GPS pings
--   /mts-teams    - list all teams with their members and status
--   /mts-leave    - leave your current team (prompts for confirmation)
--   /mts-kick     - kick a player from your team (prompts for confirmation)
--   /mts-rename   - rename your team (team leader only)

local teams_gui     = require("gui.teams")
local helpers       = require("helpers")
local force_utils   = require("force_utils")
local landing_pen   = require("gui.landing_pen")
local spectator     = require("spectator")
local confirm       = require("gui.confirm")

local commands_mod = {}

-- ─── Confirm Handlers ─────────────────────────────────────────────────
-- Registered at module load (desync-safe).

--- Perform the actual leave-team action after user confirms.
local function perform_leave(player, _data)
    if landing_pen.is_in_pen(player) then
        player.print("You are already in the Landing Pen.")
        return
    end
    if spectator.is_spectating(player) then
        spectator.exit(player)
    end
    if force_utils.remove_from_team(player) then
        landing_pen.return_to_pen(player)
        player.print("You have left your team.")
        teams_gui.update_all()
    end
end

--- Perform the actual kick action after leader confirms.
local function perform_kick(leader, data)
    local target = data and data.target_idx and game.get_player(data.target_idx)
    if not (target and target.valid) then
        leader.print("Kick target is no longer available.")
        return
    end
    -- Re-check: leader still leader, target still on same team
    if not force_utils.is_team_leader(leader) then
        leader.print("You are no longer the team leader.")
        return
    end
    if target.force ~= leader.force then
        leader.print(helpers.colored_name(target.name, target.chat_color)
            .. " is no longer on your team.")
        return
    end

    if spectator.is_spectating(target) then
        spectator.exit(target)
    end
    if force_utils.remove_from_team(target) then
        landing_pen.return_to_pen(target)
        local team_tag = helpers.team_tag(leader.force.name)
        target.print("You have been kicked from " .. team_tag .. " by "
            .. helpers.colored_name(leader.name, leader.chat_color) .. ".")
        leader.print("Kicked " .. helpers.colored_name(target.name, target.chat_color)
            .. " from " .. team_tag .. ".")
        teams_gui.update_all()
    end
end

confirm.register("leave", perform_leave)
confirm.register("kick",  perform_kick)

-- ─── Commands ─────────────────────────────────────────────────────────

function commands_mod.register()
    commands.add_command("mts-players", "List all players, their bases, and platform locations", function(cmd)
        local caller = cmd.player_index and game.get_player(cmd.player_index)
        local owners, order, owner_info = teams_gui.get_platforms_by_owner()
        local lines = {"[All Players]"}
        for _, owner in ipairs(order) do
            local info = owner_info[owner]
            -- Use team_tag for rich colored team name, fall back to plain if unavailable
            local colored = helpers.team_tag(info.force_name)
            lines[#lines + 1] = colored .. ":"
            for _, surface_info in ipairs(owners[owner]) do
                lines[#lines + 1] = "  [color=0.7,0.7,0.7]" .. surface_info.name
                    .. "[/color] " .. surface_info.gps .. "  @  " .. surface_info.location
            end
        end
        if #order == 0 then
            lines[#lines + 1] = "  No players found."
        end
        local msg = table.concat(lines, "\n")
        if caller then caller.print(msg) else game.print(msg) end
    end)

    commands.add_command("mts-leave", "Leave your current team and return to the Landing Pen", function(cmd)
        local caller = cmd.player_index and game.get_player(cmd.player_index)
        if not caller then
            game.print("This command can only be used by a player.")
            return
        end

        if landing_pen.is_in_pen(caller) then
            caller.print("You are already in the Landing Pen.")
            return
        end

        -- Show confirmation dialog explaining the consequences
        confirm.show(caller, {
            title        = "Leave " .. helpers.team_tag(caller.force.name) .. "?",
            message      = "Are you sure you want to leave your team?\n\n"
                .. "• You will return to the Landing Pen and lose your research.\n"
                .. "• Your character will die. All items in your inventory will drop\n"
                .. "  as a corpse on your team's surface (team members can recover them).\n"
                .. "• If you are the only member, your team's base will be deleted.\n"
                .. "• If you are the team leader, leadership will pass to another member.",
            confirm_text = "Leave Team",
            cancel_text  = "Cancel",
            action       = "leave",
        })
    end)

    commands.add_command("mts-rename", "Rename your team (team leader only). Usage: /mts-rename <new name>", function(cmd)
        local caller = cmd.player_index and game.get_player(cmd.player_index)
        if not caller then
            game.print("This command can only be used by a player.")
            return
        end

        if landing_pen.is_in_pen(caller) then
            caller.print("You are not on a team yet.")
            return
        end

        if not force_utils.is_team_leader(caller) then
            caller.print("Only the team leader can rename the team.")
            return
        end

        local new_name = cmd.parameter
        if not new_name or new_name:match("^%s*$") then
            caller.print("Usage: /mts-rename <new name>")
            return
        end
        new_name = new_name:match("^%s*(.-)%s*$")  -- trim
        if #new_name > 32 then new_name = new_name:sub(1, 32) end

        -- Check for duplicates
        storage.team_names = storage.team_names or {}
        for fn, name in pairs(storage.team_names) do
            if fn ~= caller.force.name and name == new_name then
                caller.print("Another team already uses that name.")
                return
            end
        end

        storage.team_names[caller.force.name] = new_name
        helpers.broadcast("[Team] " .. helpers.colored_name(caller.name, caller.chat_color)
            .. " renamed their team to " .. helpers.team_tag(caller.force.name))
        teams_gui.update_all()
    end)

    commands.add_command("mts-teams", "List all teams with their members and status", function(cmd)
        local caller = cmd.player_index and game.get_player(cmd.player_index)
        local lines = {"[Teams]"}
        for i = 1, force_utils.max_teams() do
            local force_name = "team-" .. i
            local force = game.forces[force_name]
            if force then
                -- Color the team name by force color (white if no color yet)
                local colored_name = helpers.team_tag(force_name)
                local slot = (storage.team_pool or {})[i]

                if slot ~= "occupied" then
                    lines[#lines + 1] = string.format(
                        "  [color=0.55,0.55,0.55][%s] (unclaimed)[/color]",
                        force_name
                    )
                else
                    local leader_idx = (storage.team_leader or {})[force_name]
                    local leader = leader_idx and game.get_player(leader_idx)
                    local leader_str = leader
                        and helpers.colored_name(leader.name, leader.chat_color)
                        or "[color=0.7,0.7,0.7]?[/color]"
                    local count = #force.players
                    lines[#lines + 1] = string.format(
                        "  [color=0.55,0.55,0.55][%s][/color] %s — leader: %s, %d player%s",
                        force_name, colored_name, leader_str,
                        count, count == 1 and "" or "s"
                    )
                end
            end
        end
        local msg = table.concat(lines, "\n")
        if caller then caller.print(msg) else game.print(msg) end
    end)

    commands.add_command("mts-kick", "Kick a player from your team (team leader only). Usage: /mts-kick <player-name>", function(cmd)
        local caller = cmd.player_index and game.get_player(cmd.player_index)
        if not caller then
            game.print("This command can only be used by a player.")
            return
        end

        if not force_utils.is_team_leader(caller) then
            caller.print("Only the team leader can kick players.")
            return
        end

        if force_utils.force_member_count(caller.force) < 2 then
            caller.print("You are the only player on your team.")
            return
        end

        local target_name = cmd.parameter
        if not target_name or target_name == "" then
            caller.print("Usage: /mts-kick <player-name>")
            return
        end

        target_name = target_name:match("^%s*(.-)%s*$")  -- trim
        local target = game.get_player(target_name)
        if not target then
            caller.print("Player '" .. target_name .. "' not found.")
            return
        end

        if target.index == caller.index then
            caller.print("You cannot kick yourself. Use /mts-leave instead.")
            return
        end

        if target.force ~= caller.force then
            caller.print(helpers.colored_name(target.name, target.chat_color)
                .. " is not on your team.")
            return
        end

        -- Show confirmation dialog
        confirm.show(caller, {
            title        = "Kick " .. target.name .. "?",
            message      = "Are you sure you want to kick "
                .. helpers.colored_name(target.name, target.chat_color)
                .. " from " .. helpers.team_tag(caller.force.name) .. "?\n\n"
                .. "• They will return to the Landing Pen and lose their research.\n"
                .. "• Their character will die. Items drop as a corpse on your base\n"
                .. "  (you can recover them).",
            confirm_text = "Kick Player",
            cancel_text  = "Cancel",
            action       = "kick",
            data         = {target_idx = target.index},
        })
    end)
end

return commands_mod
