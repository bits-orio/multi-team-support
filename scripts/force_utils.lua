-- scripts/force_utils.lua
-- Force utilities: team-force queries, quality sync, surface ownership,
-- bounce-home logic, and player clock.
-- Team lifecycle operations live in scripts/team_slots and are re-exported
-- here so all callers keep the same require path.

local helpers       = require("scripts.helpers")
local spectator     = require("scripts.spectator")
local surface_utils = require("scripts.surface_utils")
local planet_map    = require("scripts.planet_map")
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
    local my_force_name = my_force.name

    local owner_force = surface.name:match("^(team%-%d+)%-%w+$")
    if owner_force and owner_force ~= my_force_name then return true end

    local variant_owner = planet_map.get_force_by_planet(surface.name)
    if variant_owner and variant_owner ~= my_force_name then return true end

    for _, force in pairs(game.forces) do
        if force ~= my_force and force_utils.is_team_force(force.name) then
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

-- ─── Home Surface ─────────────────────────────────────────────────────

function force_utils.get_home_surface(player)
    local force = effective_force(player)
    if not force then return nil end
    return surface_utils.get_home_surface(force, player.index)
end

function force_utils.bounce_if_foreign(player)
    if not player or not player.connected then return end
    if player.controller_type == defines.controllers.remote then return end
    if not force_utils.on_foreign_surface(player) then return end
    local spawned = storage.spawned_players and storage.spawned_players[player.index]
    if spawned then
        local home = force_utils.get_home_surface(player)
        if not home then
            helpers.diag("bounce_if_foreign: no home found (spawned)", player)
            return
        end
        helpers.diag("bounce_if_foreign: TELEPORT → " .. home.name
            .. " (spawned branch)", player)
        player.teleport(helpers.ORIGIN, home)
    else
        local pen = game.surfaces["landing-pen"]
        if pen and pen.valid and player.surface.name ~= "landing-pen" then
            helpers.diag("bounce_if_foreign: TELEPORT → landing-pen"
                .. " (UNSPAWNED branch)", player)
            player.teleport(helpers.ORIGIN, pen)
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
