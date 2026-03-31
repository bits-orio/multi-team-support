-- Solo Teams - platformer_compat.lua
-- Author: bits-orio
-- License: MIT
--
-- Optional integration with the "Platformer" mod.
-- When Platformer is active every player spawns on their own dedicated
-- space platform instead of sharing the single "Base One" platform that
-- Platformer creates for the default "player" force.
--
-- Call on_init() from on_init and on_player_created(player) from
-- on_player_created, both guarded by is_active().

local M = {}

--- Starting items placed into each player's hub.
--- Mirrors Platformer's own set_starting_items() so every solo platform
--- begins with the same loadout.
local STARTING_ITEMS = {
    { name = "crusher",                   count = 1   },
    { name = "asteroid-collector",        count = 1   },
    { name = "assembling-machine-1",      count = 2   },
    { name = "inserter",                  count = 10  },
    { name = "solar-panel",               count = 10  },
    { name = "space-platform-foundation", count = 100 },
    { name = "electric-furnace",          count = 4   },
}

--- Returns true when the Platformer mod is loaded in the current game.
function M.is_active()
    return script.active_mods["platformer"] ~= nil
end

--- Create a personal space platform for `player` on their solo force,
--- populate it with starting items, add a visible name label, and
--- teleport the player onto it.
---
--- Expected call site: on_player_created(), internal use.
function M.setup_player_platform(player)
    local platform_name = player.name .. "'s hub"
    local force = player.force

    -- Ensure the force has space-platform capability (copied from the
    -- default force in create_player_force, but unlock explicitly just
    -- in case the copy ran before Platformer finished its own init).
    pcall(function() force.unlock_space_platforms() end)

    local platform = force.create_space_platform({
        name         = platform_name,
        planet       = "nauvis",
        starter_pack = "space-platform-starter-pack",
    })

    if not platform then
        player.print("[solo-teams] Could not create personal space platform.")
        return
    end

    platform.apply_starter_pack()

    -- Populate hub inventory
    local hub = platform.hub
    if hub then
        for _, item in pairs(STARTING_ITEMS) do
            hub.insert(item)
        end

        -- Draw a persistent name label anchored to the hub entity so it is
        -- identifiable at a glance in-world and on the minimap.
        rendering.draw_text({
            text             = platform_name,
            surface          = platform.surface,
            target           = hub,
            target_offset    = { x = 0, y = -2 },
            color            = { r = 1, g = 1, b = 1, a = 1 },
            scale            = 3,
            alignment        = "center",
        })
    end

    -- Queue the teleport for the next tick.  Teleporting a characterless
    -- player to a freshly created platform surface fails silently when
    -- attempted inside on_player_created (the surface isn't ready yet).
    if platform.surface then
        storage.pending_platform_tp = storage.pending_platform_tp or {}
        storage.pending_platform_tp[player.index] = platform.surface
    end
end

--- Process any queued platform teleports.  Must be called from an on_tick
--- handler so it runs after on_player_created has fully completed.
function M.process_pending_teleports()
    if not storage.pending_platform_tp then return end
    if not next(storage.pending_platform_tp) then return end
    for player_index, surface in pairs(storage.pending_platform_tp) do
        local player = game.get_player(player_index)
        if player and player.valid and surface and surface.valid then
            player.teleport({ x = 0, y = 0 }, surface)
        end
    end
    storage.pending_platform_tp = {}
end

--- Handle on_player_created for Platformer compatibility.
--- Platformer's own handler runs first (due to optional-dep ordering) and
--- teleports the player to its shared "Base One" platform; this overrides
--- that by creating each player's personal platform and teleporting them
--- there.  Base One is intentionally left alive on the "player" force so
--- Platformer's internal storage.platform reference stays valid for all
--- future player-join events.  It is hidden from the GUI instead.
--- Expected call site: on_player_created (guarded by is_active()).
function M.on_player_created(player)
    M.setup_player_platform(player)
end

return M
