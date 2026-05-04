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
--   /mts-disband  - disband a team and free the slot (admin only)
--   /mts-pause    - pause a team's entities (admin only)
--   /mts-resume   - resume a team's entities (admin only)
--   /mts-trim     - trim unused chunks on team nauvis surfaces (admin only)
--   /mts-replay   - retroactively replay surface/chunk events for newly-installed mods (admin only)
--   /mts-debug    - schedule debug actions: research / list / stop (admin only)

local teams_gui     = require("gui.teams")
local helpers       = require("scripts.helpers")
local force_utils   = require("scripts.force_utils")
local landing_pen   = require("gui.landing_pen")
local spectator     = require("scripts.spectator")
local confirm       = require("gui.confirm")
local awards_gui    = require("gui.awards")
local force_pause   = require("scripts.force_pause")
local chunk_trim    = require("scripts.chunk_trim")
local event_replay  = require("scripts.event_replay")
local spawn_labels  = require("scripts.spawn_labels")
local debug_engine  = require("scripts.debug")

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

--- Perform the actual disband action after admin confirms.
local function perform_disband(admin_player, data)
    local force_name = data and data.force_name
    local force = force_name and game.forces[force_name]
    if not force then
        admin_player.print("Team no longer exists.")
        return
    end
    -- Re-check: slot still occupied
    local slot = tonumber(force_name:match("^team%-(%d+)$"))
    if not slot or (storage.team_pool or {})[slot] ~= "occupied" then
        admin_player.print("That team slot is no longer occupied.")
        return
    end

    local team_tag = helpers.team_tag(force_name)

    -- Move all players on this team back to the landing pen
    local members = {}
    for _, member in pairs(force.players) do
        members[#members + 1] = member
    end
    for _, member in ipairs(members) do
        if spectator.is_spectating(member) then
            spectator.exit(member)
        end
        -- Track that this player left this team (anti-abuse on rejoin)
        storage.left_teams = storage.left_teams or {}
        storage.left_teams[member.index] = storage.left_teams[member.index] or {}
        storage.left_teams[member.index][force_name] = true

        -- Move to spectator force
        local spec_force = game.forces["spectator"]
        if spec_force then member.force = spec_force end

        if member.connected then
            landing_pen.return_to_pen(member)
            member.print("Your team " .. team_tag .. " has been disbanded by an admin.")
        else
            -- Offline players can't teleport or create characters.
            -- Clear spawned flag so they land in the pen on reconnect.
            storage.spawned_players = storage.spawned_players or {}
            storage.spawned_players[member.index] = nil
        end
    end

    -- Clean up surfaces/platforms and release the slot
    force_utils.cleanup_force_surfaces(force_name)
    force_utils.release_team_slot(force_name)

    helpers.broadcast("[Team] " .. team_tag .. " has been disbanded by an admin.")
    teams_gui.update_all()
    landing_pen.update_pen_gui_all()
    admin_player.print("Disbanded " .. team_tag .. ".")
end

confirm.register("leave",   perform_leave)
confirm.register("kick",    perform_kick)
confirm.register("disband", perform_disband)

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
        spawn_labels.refresh_for_force(caller.force.name)
        teams_gui.update_all()
        awards_gui.update_all()
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

    commands.add_command("mts-disband", "Disband a team and free the slot (admin only). Usage: /mts-disband <team-N>", function(cmd)
        local caller = cmd.player_index and game.get_player(cmd.player_index)
        if not caller then
            game.print("This command can only be used by a player.")
            return
        end

        if not caller.admin then
            caller.print("Only admins can disband teams.")
            return
        end

        local param = cmd.parameter
        if not param or param == "" then
            caller.print("Usage: /mts-disband <team-N>  (e.g. /mts-disband team-3)")
            return
        end
        param = param:match("^%s*(.-)%s*$")  -- trim

        -- Accept "team-N" or just a number
        local force_name = param:match("^team%-%d+$") and param
            or tonumber(param) and ("team-" .. param)
        if not force_name then
            caller.print("Invalid team. Use team name (team-3) or slot number (3).")
            return
        end

        local slot = tonumber(force_name:match("^team%-(%d+)$"))
        if not slot or not game.forces[force_name] then
            caller.print("Team '" .. force_name .. "' does not exist.")
            return
        end

        if (storage.team_pool or {})[slot] ~= "occupied" then
            caller.print("Team slot " .. slot .. " is not occupied.")
            return
        end

        local team_tag = helpers.team_tag(force_name)
        local force = game.forces[force_name]
        local count = force_utils.force_member_count(force)

        confirm.show(caller, {
            title        = "Disband " .. team_tag .. "?",
            message      = "Are you sure you want to disband " .. team_tag .. "?\n\n"
                .. "• " .. count .. " player" .. (count == 1 and "" or "s")
                .. " will be sent back to the Landing Pen.\n"
                .. "• All team surfaces and platforms will be deleted.\n"
                .. "• The team slot will be freed for reuse.",
            confirm_text = "Disband Team",
            cancel_text  = "Cancel",
            action       = "disband",
            data         = {force_name = force_name},
        })
    end)

    commands.add_command("mts-resume", "Resume a team's entities after /mts-pause (admin only). Usage: /mts-resume <team-N>", function(cmd)
        local caller = cmd.player_index and game.get_player(cmd.player_index)
        if not caller then
            game.print("This command can only be used by a player.")
            return
        end

        if not caller.admin then
            caller.print("Only admins can force-resume teams.")
            return
        end

        local param = cmd.parameter
        if not param or param == "" then
            caller.print("Usage: /mts-resume <team-N>  (e.g. /mts-resume team-11)")
            return
        end
        param = param:match("^%s*(.-)%s*$")

        local force_name = param:match("^team%-%d+$") and param
            or tonumber(param) and ("team-" .. param)
        if not force_name or not game.forces[force_name] then
            caller.print("Team '" .. param .. "' does not exist.")
            return
        end

        if not force_pause.resume(force_name) then
            caller.print("Could not resume " .. force_name .. " (not a team force).")
            return
        end

        caller.print("Resume sweep started for " .. helpers.team_tag_with_leader(force_name)
            .. ". Entities will be re-activated over the next few ticks.")
    end)

    commands.add_command("mts-pause", "Pause a team's entities (admin only). Stops production AND defenses. Usage: /mts-pause <team-N>", function(cmd)
        local caller = cmd.player_index and game.get_player(cmd.player_index)
        if not caller then
            game.print("This command can only be used by a player.")
            return
        end

        if not caller.admin then
            caller.print("Only admins can force-pause teams.")
            return
        end

        local param = cmd.parameter
        if not param or param == "" then
            caller.print("Usage: /mts-pause <team-N>  (e.g. /mts-pause team-11)")
            return
        end
        param = param:match("^%s*(.-)%s*$")

        local force_name = param:match("^team%-%d+$") and param
            or tonumber(param) and ("team-" .. param)
        if not force_name or not game.forces[force_name] then
            caller.print("Team '" .. param .. "' does not exist.")
            return
        end

        if not force_pause.pause(force_name) then
            caller.print("Could not pause " .. force_name .. " (not a team force).")
            return
        end

        caller.print("Pause sweep started for " .. helpers.team_tag_with_leader(force_name)
            .. ". Entities will be deactivated over the next few ticks."
            .. " Run /mts-resume " .. force_name .. " to undo.")
    end)

    commands.add_command("mts-trim", "Trim unused chunks on team nauvis surfaces (admin only). Usage: /mts-trim [team-N] [entity_buffer] [player_buffer]  (defaults: 12, 8)", function(cmd)
        local caller = cmd.player_index and game.get_player(cmd.player_index)
        if not caller then
            game.print("This command can only be used by a player.")
            return
        end
        if not caller.admin then
            caller.print("Only admins can trim chunks.")
            return
        end

        local tokens = {}
        for tok in (cmd.parameter or ""):gmatch("%S+") do tokens[#tokens + 1] = tok end

        local team_force, i = nil, 1
        if tokens[1] and tokens[1]:match("^team%-%d+$") then
            team_force = tokens[1]
            i = 2
        end

        local entity_buffer, player_buffer
        if tokens[i] then
            entity_buffer = tonumber(tokens[i])
            if not entity_buffer or entity_buffer < 0 or entity_buffer > 100 then
                caller.print("entity_buffer must be a number between 0 and 100.")
                return
            end
        end
        if tokens[i + 1] then
            player_buffer = tonumber(tokens[i + 1])
            if not player_buffer or player_buffer < 0 or player_buffer > 100 then
                caller.print("player_buffer must be a number between 0 and 100.")
                return
            end
        end

        if team_force and not game.forces[team_force] then
            caller.print("Team '" .. team_force .. "' does not exist.")
            return
        end

        local ok, count, err = chunk_trim.start{
            team_force    = team_force,
            entity_buffer = entity_buffer,
            player_buffer = player_buffer,
            caller_idx    = caller.index,
        }
        if not ok then
            caller.print(err or "Could not start trim.")
            return
        end

        caller.print(("Chunk trim queued for %d surface(s). Processing one surface every ~0.5s.")
            :format(count))
    end)

    commands.add_command("mts-replay", "Re-fire surface/chunk events on team surfaces so a newly-installed mod can apply its setup retroactively (admin only). Usage: /mts-replay [--chunks]", function(cmd)
        local caller = cmd.player_index and game.get_player(cmd.player_index)
        if not caller then
            game.print("This command can only be used by a player.")
            return
        end
        if not caller.admin then
            caller.print("Only admins can run event replay.")
            return
        end

        local with_chunks = false
        for tok in (cmd.parameter or ""):gmatch("%S+") do
            if tok == "--chunks" then with_chunks = true end
        end

        local stats = event_replay.replay_all({chunks = with_chunks})
        caller.print(("Replayed lifecycle on %d team surface(s)%s.")
            :format(stats.surfaces,
                    with_chunks
                        and (", plus " .. stats.chunks .. " chunk events")
                        or ""))
    end)

    -- ─── /mts-debug ───────────────────────────────────────────────────
    -- Admin-only scheduling sandbox. Subcommands:
    --   research <tech> [--players a,b,c] [--delay N]
    --   stop <id|all>
    --   list
    --   help

    local DEBUG_HELP = table.concat({
        "/mts-debug research <tech> [--players a,b,c] [--delay N]",
        "    Run tech:research_recursive() on each player's force.",
        "    --players defaults to caller. --delay N inserts N ticks between each (default 0).",
        "/mts-debug stop <id|all>",
        "/mts-debug list",
        "/mts-debug help",
    }, "\n")

    --- Parse "--name value" flags out of a token list, returning positionals
    --- and a flags table. Any token not preceded by a recognized --flag is
    --- positional.
    local function split_flags(tokens, start_idx, flag_names)
        local positional, flags = {}, {}
        local i = start_idx
        while i <= #tokens do
            local t = tokens[i]
            local name = t:match("^%-%-(.+)$")
            if name and flag_names[name] then
                flags[name] = tokens[i + 1]
                i = i + 2
            else
                positional[#positional + 1] = t
                i = i + 1
            end
        end
        return positional, flags
    end

    --- Resolve a comma-separated player-name list to player objects. If the
    --- list is empty/nil, falls back to {caller}. Prints a per-name error
    --- and returns nil on any unknown name.
    local function resolve_players(list_str, caller)
        if not list_str or list_str == "" then
            return caller and {caller} or nil
        end
        local players = {}
        for name in list_str:gmatch("[^,%s]+") do
            local p = game.get_player(name)
            if not p then
                caller.print("Player '" .. name .. "' not found.")
                return nil
            end
            players[#players + 1] = p
        end
        return players
    end

    commands.add_command("mts-debug",
        "Schedule debug actions (admin only). Use /mts-debug help for usage.",
        function(cmd)
            local caller = cmd.player_index and game.get_player(cmd.player_index)
            if not caller then
                game.print("This command can only be used by a player.")
                return
            end
            if not caller.admin then
                caller.print("Only admins can use /mts-debug.")
                return
            end

            local tokens = {}
            for tok in (cmd.parameter or ""):gmatch("%S+") do
                tokens[#tokens + 1] = tok
            end

            local sub = tokens[1]
            if not sub or sub == "help" then
                caller.print(DEBUG_HELP)
                return
            end

            if sub == "list" then
                local rows = debug_engine.list()
                if #rows == 0 then
                    caller.print("[mts-debug] No tasks queued.")
                    return
                end
                local lines = {"[mts-debug] Tasks:"}
                for _, r in ipairs(rows) do
                    lines[#lines + 1] = string.format("  #%d  %s  %s  (%s)",
                        r.id, r.kind, r.label, r.detail)
                end
                caller.print(table.concat(lines, "\n"))
                return
            end

            if sub == "stop" then
                local arg = tokens[2]
                if not arg then
                    caller.print("Usage: /mts-debug stop <id|all>")
                    return
                end
                if arg == "all" then
                    local n = debug_engine.stop_all()
                    caller.print("[mts-debug] Stopped " .. n .. " task(s).")
                else
                    local id = tonumber(arg)
                    if not id then
                        caller.print("Invalid task id: " .. arg)
                        return
                    end
                    if debug_engine.stop(id) then
                        caller.print("[mts-debug] Stopped task #" .. id .. ".")
                    else
                        caller.print("[mts-debug] No such task: #" .. id .. ".")
                    end
                end
                return
            end

            if sub == "research" then
                local positional, flags = split_flags(tokens, 2,
                    {players = true, delay = true})
                local tech_name = positional[1]
                if not tech_name then
                    caller.print("Usage: /mts-debug research <tech> [--players a,b,c] [--delay N]")
                    return
                end
                local players = resolve_players(flags.players, caller)
                if not players then return end
                local delay = tonumber(flags.delay or "0")
                if not delay or delay < 0 then
                    caller.print("--delay must be a non-negative integer (ticks).")
                    return
                end

                -- Resolve to force names, dedupe while preserving order.
                local force_names, seen = {}, {}
                for _, p in ipairs(players) do
                    local fn = p.force.name
                    if not seen[fn] then
                        seen[fn] = true
                        force_names[#force_names + 1] = fn
                    end
                end

                -- Sanity check: tech must exist on at least one resolved force.
                local found_on
                for _, fn in ipairs(force_names) do
                    local f = game.forces[fn]
                    if f and f.technologies[tech_name] then
                        found_on = fn
                        break
                    end
                end
                if not found_on then
                    caller.print("Technology '" .. tech_name
                        .. "' not found on any of the target forces.")
                    return
                end

                local id = debug_engine.schedule_research(force_names, tech_name, delay)
                local plan = {}
                for i, fn in ipairs(force_names) do
                    plan[#plan + 1] = string.format("  +%d ticks: %s", (i - 1) * delay, fn)
                end
                caller.print(string.format(
                    "[mts-debug] Scheduled task #%d: research %s on %d force(s):\n%s",
                    id, tech_name, #force_names, table.concat(plan, "\n")))
                return
            end

            caller.print("Unknown subcommand: " .. sub .. "\n" .. DEBUG_HELP)
        end)
end

return commands_mod
