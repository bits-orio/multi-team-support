-- Solo Teams - control.lua
-- Author: bits-orio
-- License: MIT
--
-- Main control script. Creates per-player forces, syncs tech/quality,
-- handles cross-force chat, records research timestamps, and manages
-- the top-left nav bar button strip.

local nav               = require("nav")
local platforms_gui     = require("platforms_gui")
local stats_gui         = require("stats_gui")
local landing_pen       = require("landing_pen")
local commands_mod      = require("commands")
local platformer_compat = require("platformer_compat")
local vanilla_compat    = require("vanilla_compat")
local admin_gui         = require("admin_gui")
local welcome_gui       = require("welcome_gui")
local research_gui      = require("research_gui")

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

--- Mark a player's clock as started (called when they first land on a real surface).
local function start_player_clock(player)
    storage.player_clock_start = storage.player_clock_start or {}
    if not storage.player_clock_start[player.index] then
        storage.player_clock_start[player.index] = game.tick
        log("[solo-teams] clock started for " .. player.name .. " at tick " .. game.tick)
    end
end

--- Check whether the player is on another player's private surface.
--- Covers both vanilla solo surfaces ("player-<index>") and other forces'
--- space platform surfaces.
local function on_foreign_surface(player)
    local surface = player.surface
    if not surface then return false end
    -- Vanilla solo surfaces are named "player-<player_index>"
    local owner_idx = tonumber(surface.name:match("^player%-(%d+)$"))
    if owner_idx and owner_idx ~= player.index then return true end
    -- Space platform surfaces: check all other forces' platforms
    for _, force in pairs(game.forces) do
        if force ~= player.force and force.name ~= "enemy" and force.name ~= "neutral" then
            for _, plat in pairs(force.platforms) do
                if plat.surface and plat.surface.valid
                   and plat.surface.index == surface.index then
                    return true
                end
            end
        end
    end
    return false
end

--- Find the player's home surface: first space platform, then vanilla surface.
local function get_home_surface(player)
    for _, plat in pairs(player.force.platforms) do
        if plat.surface and plat.surface.valid then return plat.surface end
    end
    local ps = storage.player_surfaces and storage.player_surfaces[player.index]
    if ps then
        local s = game.surfaces[ps.name]
        if s and s.valid then return s end
    end
    return nil
end

--- If a player is physically on someone else's surface (and not merely
--- inspecting it via remote view), send them back where they belong:
--- spawned players go to their home surface, landing-pen players go back
--- to the pen.
local function bounce_if_foreign(player)
    if not player or not player.connected then return end
    if player.controller_type == defines.controllers.remote then return end
    if not on_foreign_surface(player) then return end
    local spawned = storage.spawned_players and storage.spawned_players[player.index]
    if spawned then
        local home = get_home_surface(player)
        if not home then
            log("[solo-teams] " .. player.name .. " on foreign surface "
                .. (player.surface and player.surface.name or "nil")
                .. " but no home surface found")
            return
        end
        log("[solo-teams] bouncing " .. player.name .. " from "
            .. player.surface.name .. " → " .. home.name)
        player.teleport({x = 0, y = 0}, home)
    else
        -- Player is still in the landing pen — send them back there.
        local pen = game.surfaces["landing-pen"]
        if pen and pen.valid and player.surface.name ~= "landing-pen" then
            log("[solo-teams] bouncing " .. player.name .. " from "
                .. player.surface.name .. " → landing-pen")
            player.teleport({x = 0, y = 0}, pen)
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

--- Register event-driven tick handlers:
---   every tick: flush deferred teleports (landing pen + Platformer + vanilla)
--- Quality sync is handled in on_research_finished; admin, platforms, and
--- research GUIs are rebuilt by their respective events.
local function init_events()
    script.on_event(defines.events.on_chunk_generated, landing_pen.on_chunk_generated)
    script.on_event(defines.events.on_tick, function()
        landing_pen.process_pending_teleports()
        if platformer_compat.is_active() then
            platformer_compat.process_pending_teleports()
        else
            vanilla_compat.process_pending_teleports()
        end
        -- Deferred admin panel creation after player join
        if storage.pending_admin_check and next(storage.pending_admin_check) then
            local done = {}
            for idx, target_tick in pairs(storage.pending_admin_check) do
                if game.tick >= target_tick then
                    done[#done + 1] = idx
                    local p = game.get_player(idx)
                    if p and p.connected and p.admin and not p.gui.screen.sb_admin_frame then
                        admin_gui.build_admin_gui(p)
                    end
                end
            end
            for _, idx in ipairs(done) do
                storage.pending_admin_check[idx] = nil
            end
        end
    end)
end

--- Register nav buttons for a player across all modules.
--- Idempotent — safe to call on reconnect.
local function register_nav_buttons(player)
    welcome_gui.on_player_created(player)
    platforms_gui.on_player_created(player)
    stats_gui.on_player_created(player)
    research_gui.on_player_created(player)
    admin_gui.on_player_created(player)   -- no-op for non-admins
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
    storage.buddy_requests        = {}   -- pending buddy requests {[requester_index] = target_index}
    storage.player_surfaces       = {}   -- vanilla surfaces {[player_index] = {name, planet}}
    storage.pending_vanilla_tp    = {}   -- deferred vanilla surface teleports
    storage.admin_flags           = {}   -- runtime feature flags set via admin panel
    storage.pending_admin_check   = {}   -- deferred admin panel creation after join
    storage.admin_gui_collapsed   = {}   -- per-admin panel collapsed state
    storage.admin_gui_location    = {}   -- per-admin panel position
    storage.player_clock_start    = {}   -- per-player tick when they first spawned on a real surface
    storage.tech_research_ticks   = {}   -- {[force_name] = {[tech_name] = game.tick}}
    storage.research_gui_location = {}   -- per-player research panel position
    storage.research_gui_expanded = {}  -- per-player expanded state {[viewer_idx] = {[owner] = bool}}
    storage.research_gui_diff_target = {} -- per-player diff target {[viewer_idx] = owner_name}
    admin_gui.get_flags()               -- initialise flag defaults
    commands_mod.register()
    init_events()
end)

-- Subsequent loads (savegame resume): ensure storage tables exist
script.on_load(function()
    storage.gui_collapsed         = storage.gui_collapsed         or {}
    storage.gui_location          = storage.gui_location          or {}
    storage.stats_gui_state       = storage.stats_gui_state       or {}
    storage.stats_gui_location    = storage.stats_gui_location    or {}
    storage.stats_category_items  = storage.stats_category_items  or {}
    storage.spawned_players       = storage.spawned_players       or {}
    storage.pen_slots             = storage.pen_slots             or {}
    storage.pen_gui_location      = storage.pen_gui_location      or {}
    storage.pending_pen_tp        = storage.pending_pen_tp        or {}
    storage.buddy_requests        = storage.buddy_requests        or {}
    storage.player_surfaces       = storage.player_surfaces       or {}
    storage.pending_vanilla_tp    = storage.pending_vanilla_tp    or {}
    storage.admin_flags           = storage.admin_flags           or {}
    storage.pending_admin_check   = storage.pending_admin_check   or {}
    storage.admin_gui_collapsed   = storage.admin_gui_collapsed   or {}
    storage.admin_gui_location    = storage.admin_gui_location    or {}
    storage.player_clock_start    = storage.player_clock_start    or {}
    storage.tech_research_ticks   = storage.tech_research_ticks   or {}
    storage.research_gui_location    = storage.research_gui_location    or {}
    storage.research_gui_expanded    = storage.research_gui_expanded    or {}
    storage.research_gui_diff_target = storage.research_gui_diff_target or {}
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
    storage.spawned_players       = storage.spawned_players       or {}
    storage.player_clock_start    = storage.player_clock_start    or {}
    storage.tech_research_ticks   = storage.tech_research_ticks   or {}
    storage.research_gui_location    = storage.research_gui_location    or {}
    storage.research_gui_expanded    = storage.research_gui_expanded    or {}
    storage.research_gui_diff_target = storage.research_gui_diff_target or {}
    for _, player in pairs(game.players) do
        if not storage.spawned_players[player.index] then
            storage.spawned_players[player.index] = true
        end
    end
    stats_gui.invalidate_categories()
    init_events()
end)

-- When a new player first joins: create their solo force, register nav buttons,
-- then either place them in the Landing Pen (when enabled) or spawn directly.
script.on_event(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    create_player_force(player)

    -- Register nav bar buttons (welcome_gui auto-opens for new players here)
    register_nav_buttons(player)

    if admin_gui.flag("landing_pen_enabled") then
        landing_pen.place_player(player)
        -- Clock NOT started here; pen players haven't reached the game world yet.
    else
        -- Pre-mark as spawned so all pen logic is skipped everywhere
        storage.spawned_players = storage.spawned_players or {}
        storage.spawned_players[player.index] = true
        if platformer_compat.is_active() then
            platformer_compat.on_player_created(player)
        else
            vanilla_compat.setup_player_surface(player)
        end
        -- Clock starts now — player is going directly to the game world
        start_player_clock(player)
    end
    platforms_gui.update_all()
end)

-- Record game-tick when a technology finishes researching, and sync quality
-- unlocks across all per-player forces (replaces the old on_nth_tick poll).
script.on_event(defines.events.on_research_finished, function(event)
    local tech  = event.research
    local force = tech.force
    storage.tech_research_ticks             = storage.tech_research_ticks or {}
    storage.tech_research_ticks[force.name] = storage.tech_research_ticks[force.name] or {}
    storage.tech_research_ticks[force.name][tech.name] = game.tick
    sync_quality_all_forces()
    research_gui.update_all()
end)

-- Delegate GUI click events to the nav dispatcher first, then module fallbacks.
script.on_event(defines.events.on_gui_click, function(event)
    local el = event.element
    if not el or not el.valid then return end

    -- Nav bar buttons (platforms, stats, admin, welcome, research) and all
    -- module-registered click handlers are dispatched here.
    if nav.dispatch_click(event) then return end

    -- Landing pen: spawn button
    if el.name == "sb_spawn_btn" then
        local player = game.get_player(event.player_index)
        if player and landing_pen.is_in_pen(player) then
            landing_pen.finish_spawn(player)
            if platformer_compat.is_active() then
                platformer_compat.on_player_created(player)
            else
                vanilla_compat.setup_player_surface(player)
            end
            -- Clock starts when player leaves the pen
            start_player_clock(player)
            platforms_gui.update_all()
            research_gui.update_all()
        end
        return
    end

    if el.name == "sb_buddy_request" then
        local player = game.get_player(event.player_index)
        if player and landing_pen.is_in_pen(player) and el.tags and el.tags.sb_target_index then
            local target = game.get_player(el.tags.sb_target_index)
            if target and target.connected and not landing_pen.is_in_pen(target) then
                landing_pen.send_buddy_request(player, target)
            end
        end
        return
    end

    if el.name == "sb_buddy_accept" then
        local player = game.get_player(event.player_index)
        if player and el.tags and el.tags.sb_requester_index then
            landing_pen.accept_buddy_request(player, el.tags.sb_requester_index)
            -- Clock start for the buddy is set inside landing_pen.accept_buddy_request
            platforms_gui.update_all()
            research_gui.update_all()
        end
        return
    end

    if el.name == "sb_buddy_reject" then
        local player = game.get_player(event.player_index)
        if player and el.tags and el.tags.sb_requester_index then
            landing_pen.reject_buddy_request(player, el.tags.sb_requester_index)
        end
        return
    end

    -- Research panel click-throughs (diff/back buttons, close)
    if research_gui.on_gui_click(event) then return end
    if admin_gui.on_gui_click(event) then return end
    if stats_gui.on_gui_click(event) then return end
    platforms_gui.on_gui_click(event)
end)

-- Item chooser selections in the stats window
script.on_event(defines.events.on_gui_elem_changed, function(event)
    stats_gui.on_gui_elem_changed(event)
end)

-- Esc key: research panel navigates back before closing; welcome screen closes.
script.on_event(defines.events.on_gui_closed, function(event)
    if research_gui.on_gui_closed(event) then return end
    welcome_gui.on_gui_closed(event)
end)

-- Rebuild all GUIs instantly when any player connects or disconnects.
-- leaving_index is passed to stats_gui so it can mark the leaving player as
-- offline even if player.connected hasn't updated yet at event fire time.
local function rebuild_for_connectivity(leaving_index)
    platforms_gui.update_all()
    research_gui.update_all()
    landing_pen.update_pen_gui_all()
    landing_pen.rebuild_buddy_request_guis()
    admin_gui.update_all()
    for _, player in pairs(game.players) do
        if player.connected and player.gui.screen.sb_stats_frame then
            stats_gui.build_stats_gui(player, leaving_index)
        end
    end
end

script.on_event(defines.events.on_player_joined_game, function(event)
    -- If this player hasn't spawned yet, ensure they're shown the pen GUI.
    local player = game.get_player(event.player_index)
    if player and landing_pen.is_in_pen(player) then
        landing_pen.place_player(player)
    end
    -- Recreate nav buttons (mod_gui button flow is wiped on disconnect)
    -- Use register_nav_buttons instead of nav.rebuild_buttons so that
    -- btn_specs and click handlers are re-populated after a server restart.
    if player then
        register_nav_buttons(player)
    end
    -- Defer admin panel creation: player.admin may not be set yet at this point.
    -- Schedule a one-time check 30 ticks (~0.5s) later.
    storage.pending_admin_check = storage.pending_admin_check or {}
    storage.pending_admin_check[event.player_index] = game.tick + 30
    rebuild_for_connectivity(nil)
end)

script.on_event(defines.events.on_player_left_game, function(event)
    rebuild_for_connectivity(event.player_index)
end)

-- Show/hide admin panel when a player is promoted or demoted.
script.on_event(defines.events.on_player_promoted, function(event)
    local player = game.get_player(event.player_index)
    if player and player.connected then
        admin_gui.build_admin_gui(player)
    end
end)

script.on_event(defines.events.on_player_demoted, function(event)
    local player = game.get_player(event.player_index)
    if player and player.gui.screen.sb_admin_frame then
        player.gui.screen.sb_admin_frame.destroy()
    end
end)

-- Delegate checkbox events: admin flags first, then friend toggles.
-- When an admin flag changes, apply immediate side effects here.
script.on_event(defines.events.on_gui_checked_state_changed, function(event)
    local changed_flag = admin_gui.on_gui_checked_state_changed(event)
    if changed_flag then
        -- When landing pen is disabled mid-session, immediately spawn every
        -- player still waiting in the pen so they aren't left stranded.
        if changed_flag == "buddy_join_enabled" then
            landing_pen.update_pen_gui_all()
        end
        if changed_flag == "landing_pen_enabled" and not admin_gui.flag("landing_pen_enabled") then
            for _, player in pairs(game.players) do
                if landing_pen.is_in_pen(player) then
                    landing_pen.finish_spawn(player)
                    if platformer_compat.is_active() then
                        platformer_compat.on_player_created(player)
                    else
                        vanilla_compat.setup_player_surface(player)
                    end
                    -- Clock starts when forced out of pen by admin
                    start_player_clock(player)
                end
            end
            platforms_gui.update_all()
            research_gui.update_all()
        end
        return
    end
    platforms_gui.on_friend_toggle(event)
end)

-- Log and rebuild the platforms GUI immediately when a player changes surface.
-- Also bounce the player home if they ended up on a foreign surface (e.g. after
-- Factorio exits remote view from a cross-surface GPS tag click).
script.on_event(defines.events.on_player_changed_surface, function(event)
    local player = game.get_player(event.player_index)
    if player and player.connected then
        log("[solo-teams] surface_change: " .. player.name
            .. " → " .. (player.surface and player.surface.name or "nil"))
        bounce_if_foreign(player)
        platforms_gui.build_platforms_gui(player)
    end
end)

-- When a player exits remote view, ensure they land on their own surface
-- rather than being stranded on the foreign surface they were inspecting.
script.on_event(defines.events.on_player_controller_changed, function(event)
    local player = game.get_player(event.player_index)
    if player and player.connected then
        bounce_if_foreign(player)
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
