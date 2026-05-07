-- events/chat.lua
-- Cross-force chat routing with spectator prefix tagging.

local spectator = require("scripts.spectator")

local M = {}

function M.register()
    script.on_event(defines.events.on_console_chat, function(event)
        if not event.player_index then return end
        local author = game.get_player(event.player_index)
        if not author then return end
        local prefix = spectator.get_chat_prefix(author)
        for _, player in pairs(game.players) do
            if player.force ~= author.force then
                player.print(prefix .. author.name .. ": " .. event.message,
                             {color = author.color})
            end
        end
    end)
end

return M
