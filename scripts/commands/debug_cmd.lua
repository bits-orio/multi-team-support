-- scripts/commands/debug_cmd.lua
-- /mts-debug: admin scheduling sandbox (research, stop, list).

local debug_engine = require("scripts.debug")

local M = {}

local DEBUG_HELP = table.concat({
    "/mts-debug research <tech> [--players a,b,c] [--delay N]",
    "    Run tech:research_recursive() on each player's force.",
    "    --players defaults to caller. --delay N inserts N ticks between each (default 0).",
    "/mts-debug stop <id|all>",
    "/mts-debug list",
    "/mts-debug help",
}, "\n")

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

function M.register()
    commands.add_command("mts-debug",
        "Schedule debug actions (admin only). Use /mts-debug help for usage.",
        function(cmd)
            local caller = cmd.player_index and game.get_player(cmd.player_index)
            if not caller then game.print("This command can only be used by a player."); return end
            if not caller.admin then caller.print("Only admins can use /mts-debug."); return end

            local tokens = {}
            for tok in (cmd.parameter or ""):gmatch("%S+") do tokens[#tokens + 1] = tok end

            local sub = tokens[1]
            if not sub or sub == "help" then caller.print(DEBUG_HELP); return end

            if sub == "list" then
                local rows = debug_engine.list()
                if #rows == 0 then caller.print("[mts-debug] No tasks queued."); return end
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
                if not arg then caller.print("Usage: /mts-debug stop <id|all>"); return end
                if arg == "all" then
                    local n = debug_engine.stop_all()
                    caller.print("[mts-debug] Stopped " .. n .. " task(s).")
                else
                    local id = tonumber(arg)
                    if not id then caller.print("Invalid task id: " .. arg); return end
                    if debug_engine.stop(id) then
                        caller.print("[mts-debug] Stopped task #" .. id .. ".")
                    else
                        caller.print("[mts-debug] No such task: #" .. id .. ".")
                    end
                end
                return
            end

            if sub == "research" then
                local positional, flags = split_flags(tokens, 2, {players = true, delay = true})
                local tech_name = positional[1]
                if not tech_name then
                    caller.print("Usage: /mts-debug research <tech> [--players a,b,c] [--delay N]")
                    return
                end
                local players = resolve_players(flags.players, caller)
                if not players then return end
                local delay = tonumber(flags.delay or "0")
                if not delay or delay < 0 then
                    caller.print("--delay must be a non-negative integer (ticks)."); return
                end

                local force_names, seen = {}, {}
                for _, p in ipairs(players) do
                    local fn = p.force.name
                    if not seen[fn] then seen[fn] = true; force_names[#force_names + 1] = fn end
                end

                local found_on
                for _, fn in ipairs(force_names) do
                    local f = game.forces[fn]
                    if f and f.technologies[tech_name] then found_on = fn; break end
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

return M
