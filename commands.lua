-- Multi-Team Support - commands.lua
-- Author: bits-orio
-- License: MIT
--
-- Registers console commands:
--   /st-players  - list all players and their surfaces with GPS pings

local surfaces_gui = require("gui.surfaces")
local helpers       = require("helpers")

local commands_mod = {}

--- Register the /players command.
--- Output is grouped by player, with player names in their chat color
--- and base/platform names in grey. Both include GPS ping tags.
function commands_mod.register()
    commands.add_command("st-players", "List all players, their bases, and platform locations", function(cmd)
        local caller = cmd.player_index and game.get_player(cmd.player_index)
        local owners, order, owner_info = surfaces_gui.get_platforms_by_owner()
        local lines = {"[All Players]"}
        for _, owner in ipairs(order) do
            lines[#lines + 1] = helpers.colored_name(owner, owner_info[owner].color) .. ":"
            for _, info in ipairs(owners[owner]) do
                lines[#lines + 1] = "  [color=0.7,0.7,0.7]" .. info.name .. "[/color] " .. info.gps .. "  @  " .. info.location
            end
        end
        if #order == 0 then
            lines[#lines + 1] = "  No players found."
        end
        local msg = table.concat(lines, "\n")
        if caller then
            caller.print(msg)
        else
            game.print(msg)
        end
    end)
end

return commands_mod
