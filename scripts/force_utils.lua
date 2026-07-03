-- scripts/force_utils.lua
-- Force utilities: team-force queries, quality sync, surface ownership,
-- bounce-home logic, and player clock.
-- Team lifecycle operations live in scripts/team_slots and are re-exported
-- here so all callers keep the same require path.

local helpers       = require("scripts.helpers")
local spectator     = require("scripts.spectator")
local surface_utils = require("scripts.surface_utils")
local team_slots    = require("scripts.team_slots")

local force_utils = {}

-- ─── Re-exports from team_slots ───────────────────────────────────────

force_utils.create_team_pool      = team_slots.create_team_pool
force_utils.claim_team_slot       = team_slots.claim_team_slot
force_utils.wipe_slot_state       = team_slots.wipe_slot_state
force_utils.release_team_slot     = team_slots.release_team_slot
force_utils.is_team_leader        = team_slots.is_team_leader
force_utils.cleanup_force_surfaces = team_slots.cleanup_force_surfaces
force_utils.remove_from_team      = team_slots.remove_from_team

-- ─── Force Queries ────────────────────────────────────────────────────

function force_utils.max_teams()
    return settings.startup["mts_max_teams"].value
end

function force_utils.is_team_force(force_name)
    return force_name:find("^team%-") ~= nil
end

function force_utils.force_member_count(force)
    local n = 0
    for _ in pairs(force.players) do n = n + 1 end
    return n
end

-- ─── Quality Sync ─────────────────────────────────────────────────────

function force_utils.sync_quality_all_forces()
    for _, force in pairs(game.forces) do
        if force_utils.is_team_force(force.name) then
            pcall(function() force.unlock_quality("uncommon") end)
        end
    end
end

-- ─── Foreign Surface Detection ────────────────────────────────────────

local function effective_force(player)
    local real_fn = spectator.get_effective_force(player)
    return game.forces[real_fn]
end

function force_utils.on_foreign_surface(player)
    local surface = player.surface
    if not surface then return false end
    local my_force = effective_force(player)
    if not my_force then return false end
    -- Derive from the single ownership resolver instead of re-implementing it.
    -- This also covers mts-v1 ephemeral surfaces (surface_owner_overrides), which
    -- the old hand-rolled checks missed -- so a player standing on another team's
    -- ephemeral (e.g. MDW) surface now bounces. Unowned surfaces (landing-pen,
    -- default nauvis, spectator) return nil -> not foreign, as before.
    local owner = surface_utils.get_owner(surface)
    return owner ~= nil and owner ~= my_force.name
end

-- ─── Home Surface ─────────────────────────────────────────────────────

function force_utils.get_home_surface(player)
    local force = effective_force(player)
    if not force then return nil end
    return surface_utils.get_home_surface(force, player.index)
end

-- Land at ORIGIN, nudged to a non-colliding position when the player has a
-- character, so a bounce can't wedge them in water/cliffs on an outer-planet
-- variant. Falls back to raw ORIGIN for a characterless controller (god/pen).
local function safe_origin(surface, player)
    if player.character then
        return surface.find_non_colliding_position(player.character.name, helpers.ORIGIN, 8, 0.5)
            or helpers.ORIGIN
    end
    return helpers.ORIGIN
end

function force_utils.bounce_if_foreign(player)
    if not player or not player.connected then return end
    local ct = player.controller_type
    -- Remote view and the map editor let an admin observe another team's surface
    -- without physically being there -- don't yank them home.
    if ct == defines.controllers.remote or ct == defines.controllers.editor then return end
    if not force_utils.on_foreign_surface(player) then return end

    local spawned = storage.spawned_players and storage.spawned_players[player.index]
    local home    = spawned and force_utils.get_home_surface(player) or nil
    if spawned and home then
        helpers.diag("bounce_if_foreign: TELEPORT → " .. home.name .. " (home)", player)
        player.teleport(safe_origin(home, player), home)
    else
        -- Unspawned, OR spawned but the home surface is gone (own team disbanded
        -- while standing elsewhere): fall back to the pen rather than stranding
        -- the player on a rival surface.
        local pen = game.surfaces["landing-pen"]
        if pen and pen.valid and player.surface.name ~= "landing-pen" then
            helpers.diag("bounce_if_foreign: TELEPORT → landing-pen (fallback)", player)
            player.teleport(safe_origin(pen, player), pen)
        end
    end
end

-- ─── Player Clock ─────────────────────────────────────────────────────

function force_utils.start_player_clock(player)
    storage.player_clock_start = storage.player_clock_start or {}
    if not storage.player_clock_start[player.index] then
        storage.player_clock_start[player.index] = game.tick
        log("[multi-team-support] clock started for " .. player.name .. " at tick " .. game.tick)
    end
end

return force_utils
