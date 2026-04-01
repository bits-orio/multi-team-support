-- Solo Teams - control.lua
-- Author: bits-orio
-- License: MIT
--
-- Main control script. Creates per-player forces, syncs tech/quality,
-- and handles cross-force chat.

local platforms_gui     = require("platforms_gui")
local stats_gui         = require("stats_gui")
local landing_pen       = require("landing_pen")
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
---   every tick:              flush deferred teleports (landing pen + Platformer)
local function init_events()
    script.on_nth_tick(30, sync_quality_all_forces)
    script.on_nth_tick(300, platforms_gui.update_all)
    script.on_event(defines.events.on_tick, function()
        landing_pen.process_pending_teleports()
        if platformer_compat.is_active() then
            platformer_compat.process_pending_teleports()
        end
    end)
end

-- First-time map creation: initialize persistent storage tables
script.on_init(function()
    log("[solo-teams] on_init fired")
    storage.gui_collapsed         = {}   -- per-player GUI collapsed state
    storage.gui_location          = {}   -- per-player GUI window position
    storage.stats_gui_state       = {}   -- per-player stats window state
    storage.stats_gui_location    = {}   -- per-player stats window position
    storage.stats_category_items  = {}   -- global per-category item overrides
    storage.spawned_players       = {}   -- players who have left the landing pen
    storage.pen_slots             = {}   -- landing pen spawn slot per player
    storage.pen_gui_location      = {}   -- landing pen GUI position per player
    storage.pending_pen_tp        = {}   -- deferred landing pen teleports
    commands_mod.register()
    init_events()
end)

-- Subsequent loads (savegame resume): ensure storage tables exist
script.on_load(function()
    storage.gui_collapsed        = storage.gui_collapsed        or {}
    storage.gui_location         = storage.gui_location         or {}
    storage.stats_gui_state      = storage.stats_gui_state      or {}
    storage.stats_gui_location   = storage.stats_gui_location   or {}
    storage.stats_category_items = storage.stats_category_items or {}
    storage.spawned_players      = storage.spawned_players      or {}
    storage.pen_slots            = storage.pen_slots            or {}
    storage.pen_gui_location     = storage.pen_gui_location     or {}
    storage.pending_pen_tp       = storage.pending_pen_tp       or {}
    commands_mod.register()
    init_events()
end)

-- Re-register tick handlers when mod configuration changes.
-- Also discard the prototype category cache so it is rebuilt from the new
-- prototype set the next time a player opens the stats window.
-- When upgrading from a pre-Landing-Pen version all existing players are
-- pre-marked as spawned so they are not placed back in the pen.
script.on_configuration_changed(function()
    log("[solo-teams] on_configuration_changed fired")
    storage.spawned_players = storage.spawned_players or {}
    for _, player in pairs(game.players) do
        if not storage.spawned_players[player.index] then
            storage.spawned_players[player.index] = true
        end
    end
    stats_gui.invalidate_categories()
    init_events()
end)

-- When a new player first joins: create their solo force and place them in
-- the Landing Pen to wait before spawning into the actual game.
-- Platform creation (Platformer compat) is deferred until they click Spawn.
script.on_event(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    create_player_force(player)
    landing_pen.place_player(player)
    platforms_gui.update_all()
end)

-- Delegate GUI click events to the appropriate module.
-- sb_spawn_btn: finish landing pen spawn, then set up platform/world entry.
-- sb_stats_open: toggle the stats window.
-- All other clicks go to stats_gui then platforms_gui.
script.on_event(defines.events.on_gui_click, function(event)
    local el = event.element
    if not el or not el.valid then return end

    if el.name == "sb_spawn_btn" then
        local player = game.get_player(event.player_index)
        if player then
            landing_pen.finish_spawn(player)
            if platformer_compat.is_active() then
                platformer_compat.on_player_created(player)
            else
                -- Without Platformer, teleport to Nauvis spawn point
                local nauvis = game.surfaces["nauvis"]
                if nauvis then
                    player.teleport({x = 0, y = 0}, nauvis)
                end
            end
            platforms_gui.update_all()
        end
        return
    end

    if el.name == "sb_stats_open" then
        local player = game.get_player(event.player_index)
        if player then stats_gui.toggle(player) end
        return
    end
    if stats_gui.on_gui_click(event) then return end
    platforms_gui.on_gui_click(event)
end)

-- Item chooser selections in the stats window
script.on_event(defines.events.on_gui_elem_changed, function(event)
    stats_gui.on_gui_elem_changed(event)
end)

-- Rebuild all GUIs instantly when any player connects or disconnects.
-- leaving_index is passed to stats_gui so it can mark the leaving player as
-- offline even if player.connected hasn't updated yet at event fire time.
local function rebuild_for_connectivity(leaving_index)
    platforms_gui.update_all()
    landing_pen.update_pen_gui_all()
    for _, player in pairs(game.players) do
        if player.connected and player.gui.screen.sb_stats_frame then
            stats_gui.build_stats_gui(player, leaving_index)
        end
    end
end
script.on_event(defines.events.on_player_joined_game, function(event)
    -- If this player hasn't spawned yet, ensure they're shown the pen GUI.
    -- For brand-new players on_player_created already queued the teleport;
    -- for reconnecting unspawned players we just rebuild the GUI (they're
    -- already on the landing-pen surface).
    local player = game.get_player(event.player_index)
    if player and landing_pen.is_in_pen(player) then
        landing_pen.place_player(player)
    end
    rebuild_for_connectivity(nil)
end)
script.on_event(defines.events.on_player_left_game, function(event)
    rebuild_for_connectivity(event.player_index)
end)

-- Delegate friend checkbox toggle events
script.on_event(defines.events.on_gui_checked_state_changed, function(event)
    platforms_gui.on_friend_toggle(event)
end)

-- Rebuild the platforms GUI immediately when a player changes surface so the
-- "Return to my base" button appears/disappears without delay.
-- Skip players still in the landing pen (they have no platforms frame).
script.on_event(defines.events.on_player_changed_surface, function(event)
    local player = game.get_player(event.player_index)
    if player and player.connected then
        if player.surface and player.surface.name ~= "landing-pen" then
            platforms_gui.build_platforms_gui(player)
        end
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

