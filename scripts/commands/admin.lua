-- scripts/commands/admin.lua
-- Admin-only commands: disband, pause, resume, trim.

local teams_gui    = require("gui.teams")
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
        admin_player.print("Team no longer exists."); return
    end
    local slot = helpers.team_slot(force_name)
    if not slot or (storage.team_pool or {})[slot] ~= "occupied" then
        admin_player.print("That team slot is no longer occupied."); return
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
            member.print("Your team " .. team_tag .. " has been disbanded by an admin.")
        else
            -- Offline players can't teleport. Clear spawned flag so they land
            -- in the pen on reconnect.
            storage.spawned_players = storage.spawned_players or {}
            storage.spawned_players[member.index] = nil
        end
    end

    force_utils.cleanup_force_surfaces(force_name)
    force_utils.release_team_slot(force_name)

    helpers.broadcast("[Team] " .. team_tag .. " has been disbanded by an admin.")
    teams_gui.update_all()
    landing_pen.update_pen_gui_all()
    admin_player.print("Disbanded " .. team_tag .. ".")
end

confirm.register("disband", perform_disband)

-- ─── Commands ─────────────────────────────────────────────────────────

function M.register()
    commands.add_command("mts-disband",
        "Disband a team and free the slot (admin only). Usage: /mts-disband <team-N>",
        function(cmd)
            local caller = cmd.player_index and game.get_player(cmd.player_index)
            if not caller then game.print("This command can only be used by a player."); return end
            if not caller.admin then caller.print("Only admins can disband teams."); return end

            local param = cmd.parameter
            if not param or param == "" then
                caller.print("Usage: /mts-disband <team-N>  (e.g. /mts-disband team-3)"); return
            end
            param = param:match("^%s*(.-)%s*$")
            local force_name = param:match("^team%-%d+$") and param
                or tonumber(param) and ("team-" .. param)
            if not force_name then
                caller.print("Invalid team. Use team name (team-3) or slot number (3)."); return
            end
            local slot = helpers.team_slot(force_name)
            if not slot or not game.forces[force_name] then
                caller.print("Team '" .. force_name .. "' does not exist."); return
            end
            if (storage.team_pool or {})[slot] ~= "occupied" then
                caller.print("Team slot " .. slot .. " is not occupied."); return
            end

            local force = game.forces[force_name]
            local count = force_utils.force_member_count(force)
            confirm.show(caller, {
                title        = "Disband " .. helpers.team_tag(force_name) .. "?",
                message      = "Are you sure you want to disband " .. helpers.team_tag(force_name) .. "?\n\n"
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

    commands.add_command("mts-resume",
        "Resume a team's entities after /mts-pause (admin only). Usage: /mts-resume <team-N>",
        function(cmd)
            local caller = cmd.player_index and game.get_player(cmd.player_index)
            if not caller then game.print("This command can only be used by a player."); return end
            if not caller.admin then caller.print("Only admins can force-resume teams."); return end

            local param = cmd.parameter
            if not param or param == "" then
                caller.print("Usage: /mts-resume <team-N>  (e.g. /mts-resume team-11)"); return
            end
            param = param:match("^%s*(.-)%s*$")
            local force_name = param:match("^team%-%d+$") and param
                or tonumber(param) and ("team-" .. param)
            if not force_name or not game.forces[force_name] then
                caller.print("Team '" .. param .. "' does not exist."); return
            end
            if not pause_control.unpause_team(force_name, owned_surface_names(force_name)) then
                caller.print("Could not resume " .. force_name .. " (not a team force)."); return
            end
            caller.print("Resume sweep started for " .. helpers.team_tag_with_leader(force_name)
                .. ". Entities will be re-activated over the next few ticks.")
        end)

    commands.add_command("mts-pause",
        "Pause a team's entities (admin only). Stops production AND defenses. Usage: /mts-pause <team-N>",
        function(cmd)
            local caller = cmd.player_index and game.get_player(cmd.player_index)
            if not caller then game.print("This command can only be used by a player."); return end
            if not caller.admin then caller.print("Only admins can force-pause teams."); return end

            local param = cmd.parameter
            if not param or param == "" then
                caller.print("Usage: /mts-pause <team-N>  (e.g. /mts-pause team-11)"); return
            end
            param = param:match("^%s*(.-)%s*$")
            local force_name = param:match("^team%-%d+$") and param
                or tonumber(param) and ("team-" .. param)
            if not force_name or not game.forces[force_name] then
                caller.print("Team '" .. param .. "' does not exist."); return
            end
            if not pause_control.pause_team(force_name, owned_surface_names(force_name)) then
                caller.print("Could not pause " .. force_name .. " (not a team force)."); return
            end
            caller.print("Pause sweep started for " .. helpers.team_tag_with_leader(force_name)
                .. ". Entities will be deactivated over the next few ticks."
                .. " Run /mts-resume " .. force_name .. " to undo.")
        end)

    commands.add_command("mts-trim",
        "Trim unused chunks on all team surfaces, every planet (admin only). Usage: /mts-trim [team-N] [entity_buffer] [player_buffer]  (defaults: 12, 8)",
        function(cmd)
            local caller = cmd.player_index and game.get_player(cmd.player_index)
            if not caller then game.print("This command can only be used by a player."); return end
            if not caller.admin then caller.print("Only admins can trim chunks."); return end

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
                    caller.print("entity_buffer must be a number between 0 and 100."); return
                end
            end
            if tokens[i + 1] then
                player_buffer = tonumber(tokens[i + 1])
                if not player_buffer or player_buffer < 0 or player_buffer > 100 then
                    caller.print("player_buffer must be a number between 0 and 100."); return
                end
            end

            if team_force and not game.forces[team_force] then
                caller.print("Team '" .. team_force .. "' does not exist."); return
            end

            local ok, count, err = chunk_trim.start{
                team_force    = team_force,
                entity_buffer = entity_buffer,
                player_buffer = player_buffer,
                caller_idx    = caller.index,
            }
            if not ok then caller.print(err or "Could not start trim."); return end
            caller.print(("Chunk trim queued for %d surface(s). Processing one surface every ~0.5s."):format(count))
        end)

    commands.add_command("mts-fixcolors",
        "Brighten unreadable (too dark) player name colours now (admin only). Runs automatically on join + on colour change.",
        function(cmd)
            local caller = cmd.player_index and game.get_player(cmd.player_index)
            if not caller then game.print("This command can only be used by a player."); return end
            if not caller.admin then caller.print("Only admins can fix player colours."); return end
            color_fix.fix_all(caller)
        end)
end

return M
