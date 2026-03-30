-- Solo Teams - commands.lua
-- Author: bits-orio
-- License: MIT
--
-- Registers console commands:
--   /platforms  - list all players and their platforms with GPS pings

local platforms_gui = require("platforms_gui")

local M = {}

--- Register the /platforms command.
--- Output is grouped by player, with player names in their chat color
--- and platform names in grey. Both include GPS ping tags.
function M.register()
    commands.add_command("platforms", "List all players' platforms and locations", function(cmd)
        local caller = cmd.player_index and game.get_player(cmd.player_index)
        local owners, order, owner_info = platforms_gui.get_platforms_by_owner()
        local lines = {"[All Platforms]"}
        for _, owner in ipairs(order) do
            local c = owner_info[owner].color
            local color_tag = string.format("[color=%.2f,%.2f,%.2f]", c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1)
            lines[#lines + 1] = color_tag .. owner .. "[/color]:"
            for _, info in ipairs(owners[owner]) do
                lines[#lines + 1] = "  [color=0.7,0.7,0.7]" .. info.name .. "[/color] " .. info.gps .. "  @  " .. info.location
            end
        end
        if #order == 0 then
            lines[#lines + 1] = "  No platforms found."
        end
        local msg = table.concat(lines, "\n")
        if caller then
            caller.print(msg)
        else
            game.print(msg)
        end
    end)
end

return M
