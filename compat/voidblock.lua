-- Multi-Team Support - compat/voidblock.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- Support for the VoidBlock mod. Each team spawns on their own copy of
-- Nauvis with VoidBlock's void-island terrain (small grass island at
-- origin, void ocean everywhere else).
--
-- Architecture
-- ────────────
-- Chunk-gen is handled generically by compat/clone_mirror.lua: VoidBlock
-- runs on the real nauvis surface (where its `surface.name == "nauvis"`
-- filter accepts), and clone_mirror copies each chunk to team-N-nauvis.
-- We don't re-implement VoidBlock's tile generator anymore.
--
-- This module retains:
--   • setup_player_surface — creates each team's nauvis with autoplace
--     disabled (saves the cost of generating vanilla terrain that
--     clone_mirror would just overwrite anyway) and pre-generates the
--     spawn-area chunks so the player teleports onto cloned terrain.
--   • Starting-items config and is_active probe.
--
-- Surface storage continues to follow vanilla compat conventions:
--   storage.player_surfaces[player_index] = {name = surface_name, planet = "nauvis"}

local compat_utils = require("compat.compat_utils")

local voidblock = {}

--- Character starting items for VoidBlock mode.
--- Edit this list to match VoidBlock's intended starting loadout.
voidblock.CHARACTER_STARTING_ITEMS = {
    {name = "iron-plate",          count = 8},
    {name = "wood",                count = 1},
    {name = "stone-furnace",       count = 1},
    {name = "burner-mining-drill", count = 1},
}

--- Returns true when VoidBlock compat should be used.
--- Active when VoidBlock is loaded and Platformer is NOT loaded.
function voidblock.is_active()
    return script.active_mods["VoidBlock"] ~= nil
       and script.active_mods["platformer"] == nil
end

voidblock.planet_display_name    = compat_utils.planet_display_name
voidblock.process_pending_teleports = compat_utils.process_pending_teleports

--- Create a personal Nauvis surface for `player` with no auto-generated
--- terrain. All tiles are placed by on_chunk_generated (void ocean + island)
--- so the player never sees pre-generated Nauvis terrain.
---
--- Teleport is deferred to the next tick via storage.pending_vanilla_tp.
function voidblock.setup_player_surface(player)
    compat_utils.setup_player_surface(player, function(surf_name)
        local surface = game.create_surface(surf_name, {
            default_enable_all_autoplace_controls = false,
            autoplace_settings = {
                entity     = { treat_missing_as_default = false, settings = {} },
                tile       = { treat_missing_as_default = false, settings = {} },
                decorative = { treat_missing_as_default = false, settings = {} },
            },
        })
        -- Pre-generate chunks around spawn so on_chunk_generated applies
        -- void-island terrain before the player arrives (next tick).
        surface.request_to_generate_chunks({0, 0}, 3)
        surface.force_generate_chunk_requests()

        return surface
    end)
end

return voidblock
