-- Multi-Team Support - deep_core_ops.lua
-- Author: bits-orio
-- License: MIT
--
-- Optional integration with the "Deep_Core_Operations" mod.
-- DCO gives each force its own space platform and a ship-interior surface.
-- When DCO is active, players should spawn on ship.surfaces[1] (the ship
-- interior) rather than the vanilla mts-nauvis-* team planet.
--
-- Call on_player_created(player) from spawn_into_world, guarded by is_active().

local dco = {}

--- Starting items given to each player character when spawning into DCO.
--- DCO uses a mission/ship economy rather than vanilla crafting, so the
--- freeplay defaults (stone furnace, burner drill, etc.) are inappropriate.
dco.CHARACTER_STARTING_ITEMS = {
    {name = "pistol",            count = 1},
    {name = "firearm-magazine",  count = 10},
}

function dco.is_active()
    return script.active_mods["Deep_Core_Operations"] ~= nil
end

--- Ensure DCO has a ship for `force_name`, then queue the player's spawn
--- teleport to that ship's interior surface.
function dco.on_player_created(player)
    local force_name = player.force.name

    -- Create the ship for this team force if DCO doesn't know about it yet.
    if not remote.call("DeepCoreOperations", "get_force_platform", force_name) then
        remote.call("DeepCoreOperations", "add_player_force", force_name)
    end

    local platform_data = remote.call("DeepCoreOperations", "get_force_platform", force_name)
    local ship    = platform_data and platform_data.ship
    local surface = ship and ship.surfaces[1]

    if surface and surface.valid then
        storage.pending_vanilla_tp = storage.pending_vanilla_tp or {}
        storage.pending_vanilla_tp[player.index] = surface
    end
end

return dco
