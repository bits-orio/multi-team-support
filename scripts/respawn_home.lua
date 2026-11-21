-- Multi-Team Support - scripts/respawn_home.lua
-- Author: bits-orio
-- License: MIT
--
-- A team player who respawns on a shared base planet is sent home.
--
-- The engine respawns a player on the surface they died on. A team player dies
-- on a surface their team owns, so that is where they come back. The exception
-- is a player who dies with the space platform they were riding (the hub is
-- destroyed in flight): the platform's surface is gone, and the engine respawns
-- them on the default Nauvis. No team owns that surface, it is hidden from team
-- forces, and nothing there leads back to the team (measured on 2.1.25 with
-- Nomad: both riders of a destroyed ship stayed on "nauvis").
--
-- Only that case is handled: the respawn surface is a base planet (or the
-- default nauvis) that no team owns. Every other respawn is left alone.

local helpers       = require("scripts.helpers")
local surface_utils = require("scripts.surface_utils")
local body_teleport = require("scripts.body_teleport")

local respawn_home = {}

--- True for a surface that stands for a shared base planet no team owns.
local function is_shared_planet(surface)
    if surface.platform then return false end
    if not (surface.planet or surface.name == "nauvis") then return false end
    return surface_utils.get_owner(surface) == nil
end

function respawn_home.on_player_respawned(event)
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end
    local force = player.force
    if not helpers.is_team_force(force.name) then return end
    local surface = player.physical_surface
    if not (surface and surface.valid and is_shared_planet(surface)) then return end

    local home = surface_utils.get_home_surface(force, player.index)
    if not (home and home.valid) or home == surface then return end
    local origin = force.get_spawn_position(home)
    local position = home.find_non_colliding_position("character", origin, 32, 1) or origin
    helpers.diag("respawn_home: " .. surface.name .. " -> " .. home.name, player)
    body_teleport.to(player, position, home)
end

return respawn_home
