-- Solo Teams - control.lua
-- Author: bits-orio
-- License: MIT
--
-- Main control script. Creates per-player forces, syncs tech/quality,
-- handles cross-force chat, and fixes platform spawn collisions.

local platforms_gui = require("platforms_gui")
local commands_mod = require("commands")

--- Copy all researched technologies, quality unlocks, and space platform
--- unlock from one force to another. This is generic and works regardless
--- of which mods are active — it mirrors whatever the source force has.
local function copy_force_state(source, target)
    for name, tech in pairs(source.technologies) do
        if tech.researched then
            local t = target.technologies[name]
            if t then t.researched = true end
        end
    end
    -- pcall each quality tier in case the tier doesn't exist in the current mod set
    for _, quality in pairs({"uncommon", "rare", "epic", "legendary"}) do
        pcall(function()
            if source.is_quality_unlocked(quality) then
                target.unlock_quality(quality)
            end
        end)
    end
    if source.is_space_platforms_unlocked() then
        pcall(target.unlock_space_platforms)
    end
end

--- Create a dedicated force for a player and set up diplomacy.
--- Force name follows the pattern "player-<name>" (e.g. "player-bob").
--- Factorio has a hard limit of 64 forces; exceeding it falls back to the
--- default "player" force.
--- Diplomacy: cease-fire with all non-enemy forces (neutral relationship).
--- Players can opt into friendship per-player via the GUI checkbox.
local function create_player_force(player)
    local force_name = "player-" .. player.name
    local ok, new_force = pcall(game.create_force, force_name)
    if not ok then
        player.print("Could not create separate force (64 force limit reached). Joining default team.")
        return
    end
    copy_force_state(game.forces.player, new_force)
    player.force = new_force

    -- Set cease-fire with every existing non-enemy force (both directions)
    for _, other_force in pairs(game.forces) do
        if other_force.name ~= "enemy" and other_force ~= new_force then
            new_force.set_cease_fire(other_force, true)
            other_force.set_cease_fire(new_force, true)
        end
    end
end

--- Periodically unlock "uncommon" quality for all player forces.
--- Some mods (e.g. space-block) only do this for game.forces.player;
--- this ensures custom per-player forces stay in sync.
local function sync_quality_all_forces()
    for _, force in pairs(game.forces) do
        if force.name ~= "enemy" and force.name ~= "neutral" then
            pcall(function() force.unlock_quality("uncommon") end)
        end
    end
end

--- Register periodic tick handlers:
---   every  30 ticks (~0.5s): sync quality unlocks across all forces
---   every 300 ticks (~5s):   refresh the platforms GUI for all players
local function init_events()
    script.on_nth_tick(30, sync_quality_all_forces)
    script.on_nth_tick(300, platforms_gui.update_all)
end

-- First-time map creation: initialize persistent storage tables
script.on_init(function()
    storage.gui_collapsed = {}         -- per-player GUI collapsed state
    storage.gui_location = {}          -- per-player GUI window position
    storage.pending_collision_fix = {} -- players needing spawn collision fix
    commands_mod.register()
    init_events()
end)

-- Subsequent loads (savegame resume): ensure storage tables exist
script.on_load(function()
    storage.gui_collapsed = storage.gui_collapsed or {}
    storage.gui_location = storage.gui_location or {}
    storage.pending_collision_fix = storage.pending_collision_fix or {}
    commands_mod.register()
    init_events()
end)

-- Re-register tick handlers when mod configuration changes
script.on_configuration_changed(function()
    init_events()
end)

-- When a new player joins, create their solo force and refresh the GUI
script.on_event(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    create_player_force(player)
    platforms_gui.update_all()
end)

-- Delegate GUI click events (toggle collapse, GPS ping buttons)
script.on_event(defines.events.on_gui_click, function(event)
    platforms_gui.on_gui_click(event)
end)

-- Delegate friend checkbox toggle events
script.on_event(defines.events.on_gui_checked_state_changed, function(event)
    platforms_gui.on_friend_toggle(event)
end)

-- Broadcast chat messages across all forces so players on separate teams
-- can still communicate without needing /shout. The sender's name and
-- color are preserved in the forwarded message.
script.on_event(defines.events.on_console_chat, function(event)
    if not event.player_index then return end
    local author = game.get_player(event.player_index)
    if not author then return end
    for _, player in pairs(game.players) do
        if player.force ~= author.force then
            player.print(author.name .. ": " .. event.message, {color = author.color})
        end
    end
end)

-- Spawn collision fix (two-part):
-- Part 1: When a player's physical body arrives on a platform surface, flag
-- them for a position correction on the next tick.
--
-- on_player_changed_surface fires for BOTH physical moves and remote view
-- changes. We distinguish them by comparing player.physical_surface.index
-- (where the body is now) against event.surface_index (where it was before).
-- If they are equal the body didn't move — only the camera did — so we skip.
script.on_event(defines.events.on_player_changed_surface, function(event)
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end
    if not player.physical_surface then return end
    -- Remote-view change: physical body stays on the same surface it was on.
    if player.physical_surface.index == event.surface_index then return end
    if not player.physical_surface.platform then return end
    local hub = player.physical_surface.platform.hub
    if hub and hub.valid then
        storage.pending_collision_fix[event.player_index] = hub
    end
end)

-- Part 2: On the next tick, find a non-colliding position near the player
-- and re-teleport them there. This prevents players from getting stuck
-- inside the 10x10 platform hub entity.
-- We use the stored hub entity (not player.surface) to find the correct
-- surface, since player.surface changes when the player is remotely viewing
-- another surface.
script.on_event(defines.events.on_tick, function()
    for player_index, hub in pairs(storage.pending_collision_fix) do
        local player = game.get_player(player_index)
        if player and player.valid and player.character and player.character.valid then
            if hub and hub.valid then
                local surface = hub.surface
                local safe_pos = surface.find_non_colliding_position("character", player.physical_position, 20, 0.5)
                if safe_pos then
                    player.teleport(safe_pos, surface)
                end
            end
        end
        storage.pending_collision_fix[player_index] = nil
    end
end)
