-- events/chat.lua
-- Channel-aware cross-force chat routing with spectator prefix tagging.
--
-- The engine delivers every chat message to the sender's CURRENT force before
-- any mod runs — that native delivery IS team chat, and no mod can cancel or
-- edit it. This handler adds everything else:
--   global channel (default): relay to every other force + bridge emit.
--   team-only channel: nothing to add — unless the sender is force-swapped
--     spectating, where the native copy went to the spectator force instead
--     of their team; the team copy is relayed here, tagged [spectating]. The
--     native copy remains visible to co-spectators (engine-imposed; disclosed
--     to the sender on entering spectate and via a soft sound per message).
--
-- MTS disables the bridge's baseline chat capture (remote_api.register_with_
-- bridge), so Discord only ever receives what this file explicitly emits:
-- global-channel messages, shouts, spectator/server chatter. Team-only
-- messages never leave the game.

local spectator    = require("scripts.spectator")
local chat_channel = require("scripts.chat_channel")
local helpers      = require("scripts.helpers")
local remote_api   = require("scripts.remote_api")

local M = {}

function M.register()
    script.on_event(defines.events.on_console_chat, function(event)
        local message = event.message
        if type(message) ~= "string" or message == "" then return end

        -- Server-console (stdin) messages have no player. The engine already
        -- shows them to everyone; only the bridge copy is owed here.
        if not event.player_index then
            remote_api.emit_chat("Server", message, nil)
            return
        end
        local author = game.get_player(event.player_index)
        if not author then return end

        local effective = spectator.get_effective_force(author)
        local is_team   = helpers.is_team_force(effective)
        -- "!" shouts one message globally from a team-only channel.
        local shout     = message:find("^!") ~= nil
        local go_global = shout or not is_team
            or not chat_channel.is_local_for(author)

        if go_global then
            local prefix = spectator.get_chat_prefix(author)
            for _, player in pairs(game.connected_players) do
                if player.force ~= author.force then
                    player.print(prefix .. author.name .. ": " .. message,
                                 {color = author.color})
                end
            end
            remote_api.emit_chat(author.name, message,
                is_team and effective or nil)
            return
        end

        -- Team-only. Anyone sharing the author's ACTUAL force already has the
        -- native line; every other member of the effective team is reached
        -- here. That covers both directions of force-swapped spectating:
        -- a spectating author's line reaches the team (tagged, since their
        -- native copy went to the spectator force instead), and a spectating
        -- TEAMMATE still receives team chat sent from home.
        local author_swapped = author.force.name ~= effective
        local tag = author_swapped and "[spectating] " or ""
        for _, player in pairs(game.connected_players) do
            if player.index ~= author.index
               and player.force ~= author.force
               and spectator.get_effective_force(player) == effective then
                player.print(tag .. author.name .. ": " .. message,
                             {color = author.color})
            end
        end
        -- Soft cue: the author's native copy was visible to co-spectators.
        if author_swapped then
            author.play_sound{path = chat_channel.SOUND_EXPOSURE}
        end
    end)
end

return M
