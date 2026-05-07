-- scripts/team_slots.lua
-- Team slot lifecycle: create pool, claim, release, remove player from team.
-- Avoids requiring force_utils to prevent circular deps — trivial helpers
-- (max_teams, force_member_count) are inlined as private functions.

local helpers     = require("scripts.helpers")
local spectator   = require("scripts.spectator")
local planet_map  = require("scripts.planet_map")
local friendship  = require("gui.friendship")
local remote_api  = require("scripts.remote_api")
local spawn_labels = require("scripts.spawn_labels")

local M = {}

-- ─── Private Helpers ──────────────────────────────────────────────────

local function max_teams()
    return settings.startup["mts_max_teams"].value
end

local function force_member_count(force)
    local n = 0
    for _ in pairs(force.players) do n = n + 1 end
    return n
end

local function copy_force_state(source, target)
    for name, tech in pairs(source.technologies) do
        if tech.researched then
            local t = target.technologies[name]
            if t and not t.researched then t.researched = true end
        end
    end
    for _, quality in pairs({"uncommon", "rare", "epic", "legendary"}) do
        pcall(function()
            if source.is_quality_unlocked(quality) then target.unlock_quality(quality) end
        end)
    end
    if source.is_space_platforms_unlocked() then
        pcall(target.unlock_space_platforms)
    end
end

--- Reset a force's tech tree back to a clean state.
--- force.reset() zeroes engine-level trigger progress and tech modifiers;
--- diplomacy is re-applied afterwards since reset() wipes it.
local function reset_force_state(force)
    force.reset()
    for _, other in pairs(game.forces) do
        if other.name ~= "enemy" and other ~= force then
            force.set_cease_fire(other, true)
            other.set_cease_fire(force, true)
        end
    end
    spectator.setup_force(force)
end

local function pick_new_leader(force, exclude_index)
    local fallback = nil
    for _, member in pairs(force.players) do
        if member.valid and member.index ~= exclude_index then
            if member.connected then return member end
            if not fallback then fallback = member end
        end
    end
    return fallback
end

local function strip_team_from_records(records_table, team)
    if not records_table then return end
    for key, entry in pairs(records_table) do
        local fi = entry.first   and entry.first.team   == team
        local fai = entry.fastest and entry.fastest.team == team
        if fi and fai then
            records_table[key] = nil
        elseif fi then
            entry.first = entry.fastest
        elseif fai then
            entry.fastest = entry.first
        end
    end
end

-- ─── Pool Init ────────────────────────────────────────────────────────

function M.create_team_pool()
    local max = max_teams()
    storage.team_pool        = {}
    storage.team_names       = {}
    storage.team_leader      = {}
    storage.team_clock_start = {}

    for i = 1, max do
        local force_name = "team-" .. i
        local ok, new_force = pcall(game.create_force, force_name)
        if not ok then
            log("[multi-team-support] WARNING: Could not create " .. force_name
                .. " (64 force limit reached)")
            break
        end
        copy_force_state(game.forces.player, new_force)
        for _, other_force in pairs(game.forces) do
            if other_force.name ~= "enemy" and other_force ~= new_force then
                new_force.set_cease_fire(other_force, true)
                other_force.set_cease_fire(new_force, true)
            end
        end
        spectator.setup_force(new_force)
        storage.team_pool[i]           = "available"
        storage.team_names[force_name] = string.format("Team %02d", i)
        log("[multi-team-support] created team slot: " .. force_name)
    end
end

-- ─── Claim ────────────────────────────────────────────────────────────

function M.claim_team_slot(player)
    storage.team_pool = storage.team_pool or {}
    local slot = nil
    for i = 1, max_teams() do
        if storage.team_pool[i] == "available" then slot = i; break end
    end
    if not slot then
        player.print("No team slots available. All " .. max_teams() .. " teams are occupied.")
        return nil
    end

    local force_name = "team-" .. slot
    local force = game.forces[force_name]
    if not force then return nil end

    reset_force_state(force)
    copy_force_state(game.forces.player, force)
    player.force    = force
    force.custom_color = player.color

    storage.team_leader = storage.team_leader or {}
    storage.team_leader[force_name] = player.index
    storage.team_pool[slot] = "occupied"

    storage.team_clock_start = storage.team_clock_start or {}
    if not storage.team_clock_start[force_name] then
        storage.team_clock_start[force_name] = game.tick
        log("[multi-team-support] team clock started for " .. force_name
            .. " at tick " .. game.tick)
    end

    planet_map.apply_force_locks(force)
    log("[multi-team-support] " .. player.name .. " claimed slot " .. slot
        .. " (" .. force_name .. ")")
    remote_api.raise_team_created(force_name, player.index)
    return force_name
end

-- ─── Wipe & Release ───────────────────────────────────────────────────

--- Clear per-slot storage and break engine friendship ties.
--- Does NOT touch force tech state, slot pool, leader, or clock.
function M.wipe_slot_state(force_name)
    local slot = tonumber(force_name:match("^team%-(%d+)$"))
    if not slot then return end

    storage.team_names = storage.team_names or {}
    storage.team_names[force_name] = string.format("Team %02d", slot)

    strip_team_from_records(storage.tech_records,      force_name)
    strip_team_from_records(storage.milestone_records, force_name)

    if storage.milestone_reached   then storage.milestone_reached[force_name]   = nil end
    if storage.tech_research_ticks then storage.tech_research_ticks[force_name] = nil end

    if storage.left_teams then
        for _, teams in pairs(storage.left_teams) do teams[force_name] = nil end
    end

    -- Must run BEFORE reset_force_state: break_pair checks engine friendship
    -- flags that force.reset() would wipe silently.
    friendship.break_all_for(force_name)
end

function M.release_team_slot(force_name)
    local slot = tonumber(force_name:match("^team%-(%d+)$"))
    if not slot then return end

    storage.team_pool = storage.team_pool or {}
    storage.team_pool[slot] = "available"
    storage.team_leader = storage.team_leader or {}
    storage.team_leader[force_name] = nil
    storage.team_clock_start = storage.team_clock_start or {}
    storage.team_clock_start[force_name] = nil

    M.wipe_slot_state(force_name)

    local force = game.forces[force_name]
    if force then
        reset_force_state(force)
        copy_force_state(game.forces.player, force)
        planet_map.apply_force_locks(force)
    end

    log("[multi-team-support] released team slot: " .. force_name)
    remote_api.raise_team_released(force_name)
end

-- ─── Leader ───────────────────────────────────────────────────────────

function M.is_team_leader(player)
    storage.team_leader = storage.team_leader or {}
    return storage.team_leader[player.force.name] == player.index
end

-- ─── Surface Cleanup ──────────────────────────────────────────────────

function M.cleanup_force_surfaces(force_name)
    local deleted = {}
    for _, surface in pairs(game.surfaces) do
        if surface.valid and surface.name:find("^" .. force_name:gsub("%-", "%%-") .. "%-") then
            deleted[#deleted + 1] = surface.name
            game.delete_surface(surface)
        end
    end
    local force = game.forces[force_name]
    if force then
        for _, platform in pairs(force.platforms) do
            if platform.valid then
                deleted[#deleted + 1] = platform.name
                platform.destroy()
            end
        end
    end
    storage.player_surfaces = storage.player_surfaces or {}
    for idx, ps in pairs(storage.player_surfaces) do
        for _, name in pairs(deleted) do
            if ps.name == name then storage.player_surfaces[idx] = nil; break end
        end
    end
    return deleted
end

-- ─── Remove from Team ─────────────────────────────────────────────────

function M.remove_from_team(player)
    local old_force      = player.force
    local old_force_name = old_force.name
    local member_count   = force_member_count(old_force)

    storage.left_teams = storage.left_teams or {}
    storage.left_teams[player.index] = storage.left_teams[player.index] or {}
    storage.left_teams[player.index][old_force_name] = true

    storage.team_leader = storage.team_leader or {}
    local is_leader = (storage.team_leader[old_force_name] == player.index)
    local cn_player = helpers.colored_name(player.name, player.chat_color)
    local team_tag  = helpers.team_tag_with_leader(old_force_name)

    if member_count <= 1 then
        local deleted  = M.cleanup_force_surfaces(old_force_name)
        local spec_force = game.forces["spectator"]
        if spec_force then player.force = spec_force end
        M.release_team_slot(old_force_name)
        local msg = "[Team] " .. team_tag .. " has been disbanded."
        if #deleted > 0 then msg = msg .. " Their base has been cleaned up." end
        helpers.broadcast(msg)
    else
        local spec_force = game.forces["spectator"]
        if spec_force then player.force = spec_force end
        helpers.broadcast("[Team] " .. cn_player .. " has left " .. team_tag .. ".")

        if is_leader then
            local new_leader = pick_new_leader(old_force, player.index)
            if new_leader then
                storage.team_leader[old_force_name] = new_leader.index
                old_force.custom_color = new_leader.color
                spawn_labels.refresh_for_force(old_force_name)
                local cn_leader = helpers.colored_name(new_leader.name, new_leader.chat_color)
                for _, member in pairs(old_force.players) do
                    if member.connected then
                        member.print(cn_leader .. " is now the leader of " .. team_tag .. ".")
                    end
                end
                helpers.broadcast("[Team] " .. cn_leader .. " now leads " .. team_tag .. ".")
            end
        end
    end

    return true
end

return M
