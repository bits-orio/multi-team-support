-- Solo Teams - control.lua
-- Author: bits-orio
-- License: MIT
--
-- Main control script. Creates per-player forces, syncs tech/quality,
-- and handles cross-force chat.

local platforms_gui     = require("platforms_gui")
local commands_mod      = require("commands")
local platformer_compat = require("platformer_compat")

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
---   every tick:              flush deferred platform teleports (Platformer only)
local function init_events()
    script.on_nth_tick(30, sync_quality_all_forces)
    script.on_nth_tick(300, platforms_gui.update_all)
    if platformer_compat.is_active() then
        script.on_event(defines.events.on_tick, platformer_compat.process_pending_teleports)
    end
end

-- First-time map creation: initialize persistent storage tables
script.on_init(function()
    log("[solo-teams] on_init fired")
    storage.gui_collapsed = {}         -- per-player GUI collapsed state
    storage.gui_location = {}          -- per-player GUI window position
    commands_mod.register()
    init_events()
end)

-- Subsequent loads (savegame resume): ensure storage tables exist
script.on_load(function()
    storage.gui_collapsed = storage.gui_collapsed or {}
    storage.gui_location = storage.gui_location or {}
    commands_mod.register()
    init_events()
end)

-- Re-register tick handlers when mod configuration changes.
script.on_configuration_changed(function()
    log("[solo-teams] on_configuration_changed fired")
    init_events()
end)

-- When a new player joins, create their solo force, and if Platformer is
-- active create a personal space platform overriding Base One.
script.on_event(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    create_player_force(player)
    if platformer_compat.is_active() then
        platformer_compat.on_player_created(player)
    end
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

-- Rebuild the GUI immediately when a player changes surface so the
-- "Return to my base" button appears/disappears without delay.
script.on_event(defines.events.on_player_changed_surface, function(event)
    local player = game.get_player(event.player_index)
    if player and player.connected then
        platforms_gui.build_platforms_gui(player)
    end
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

