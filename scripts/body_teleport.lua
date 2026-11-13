-- scripts/body_teleport.lua
-- Teleport a player's BODY, whatever view they are in.
--
-- LuaPlayer.teleport on a player in remote view (the map) moves only the
-- camera: it returns true and the character stays where it stood (measured on
-- 2.1.23). Every "put this player on their team surface" path goes through
-- here, so a player who is looking at the map when a team member accepts their
-- request still lands with the team instead of staying in the landing pen.
--
-- Dependency-free on purpose: compat and gui modules both require it.

local M = {}

local function body_is_on(player, surface)
    return player.physical_surface_index == surface.index
end

--- Move the player's body to `position` on `surface`.
--- Returns true only when the body is on `surface` afterwards.
function M.to(player, position, surface)
    if player.controller_type == defines.controllers.remote then
        player.exit_remote_view()
    end
    if player.teleport(position, surface) and body_is_on(player, surface) then
        return true
    end
    -- Still in a view that keeps the body behind (a remote view the engine
    -- will not leave): move the character entity itself.
    local character = player.character
    if character and character.valid then
        character.teleport(position, surface)
    end
    return body_is_on(player, surface)
end

return M
