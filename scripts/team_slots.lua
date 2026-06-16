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
local team_clock  = require("scripts.team_clock")

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

-- Forces that script-spawned turrets / triggers belong to (e.g. K2's
-- planetary teleporter and tesla coil). They MUST stay at war with team
-- forces or the trigger-based mechanics (teleporter "standing on" detection,
-- tesla coil targeting) silently break.
local INTERNAL_TURRET_FORCES = {
    ["kr-internal-turrets"] = true,
}

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
        if other.name ~= "enemy" and other ~= force and not INTERNAL_TURRET_FORCES[other.name] then
            force.set_cease_fire(other, true)
            other.set_cease_fire(force, true)
        end
    end
    -- Restore chart sharing with the built-in player force (no active members
    -- in MTS, but sharing its chart is desirable). reset() wipes this.
    force.set_friend(game.forces.player, true)
    game.forces.player.set_friend(force, true)
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
    storage.team_pool              = {}
    storage.team_names             = {}
    storage.team_leader            = {}
    storage.team_clock_start       = {}
    storage.team_looking_for_more  = {}

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
            if other_force.name ~= "enemy" and other_force ~= new_force
               and not INTERNAL_TURRET_FORCES[other_force.name] then
                new_force.set_cease_fire(other_force, true)
                other_force.set_cease_fire(new_force, true)
            end
        end
        -- Share chart data with the built-in player force (no active members
        -- in MTS, but sharing its chart is desirable). Also set by
        -- reset_force_state on every claim/release cycle.
        new_force.set_friend(game.forces.player, true)
        game.forces.player.set_friend(new_force, true)
        spectator.setup_force(new_force)
        storage.team_pool[i]           = "available"
        storage.team_names[force_name] = string.format("Team %02d", i)
        log("[multi-team-support] created team slot: " .. force_name)
    end
end

-- ─── Claim ────────────────────────────────────────────────────────────

-- opts.skip_clock = true defers team_clock_start + team_clock.on_claim until
-- the leader clicks "Start Playing" (used by the staged-start feature).
function M.claim_team_slot(player, opts)
    opts = opts or {}
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

    -- Track whether THIS claim is the call that starts the clock, so we raise
    -- on_team_clock_started exactly once (after raise_team_created below). A
    -- staged start defers the clock (skip_clock) and fires the event from
    -- pre_start.commit instead.
    local clock_started_now = false
    if not opts.skip_clock then
        storage.team_clock_start = storage.team_clock_start or {}
        if not storage.team_clock_start[force_name] then
            storage.team_clock_start[force_name] = game.tick
            clock_started_now = true
            log("[multi-team-support] team clock started for " .. force_name
                .. " at tick " .. game.tick)
        end
        team_clock.on_claim(force_name)
    end

    planet_map.apply_force_locks(force)
    log("[multi-team-support] " .. player.name .. " claimed slot " .. slot
        .. " (" .. force_name .. ")")
    remote_api.raise_team_created(force_name, player.index)
    if clock_started_now then
        remote_api.raise_team_clock_started(force_name, storage.team_clock_start[force_name])
    end
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

    storage.team_looking_for_more = storage.team_looking_for_more or {}
    storage.team_looking_for_more[force_name] = nil
    storage.lfm_ever_recruited = storage.lfm_ever_recruited or {}
    storage.lfm_ever_recruited[force_name] = nil
    storage.pre_start_pending = storage.pre_start_pending or {}
    storage.pre_start_pending[force_name] = nil

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
    team_clock.on_release(force_name)

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
    local seen    = {}

    -- Legacy / non-Space-Age cloned surfaces are named "team-N-<planet>".
    for _, surface in pairs(game.surfaces) do
        if surface.valid and surface.name:find("^" .. force_name:gsub("%-", "%%-") .. "%-") then
            if not seen[surface.name] then
                seen[surface.name] = true
                deleted[#deleted + 1] = surface.name
                game.delete_surface(surface)
            end
        end
    end

    -- Space Age variants are named "mts-<planet>-N" and don't match the
    -- "team-N-" prefix above. Look them up via planet_map's force→variant
    -- map so they get deleted too; otherwise the next team that recycles
    -- this slot inherits the previous occupants' explored terrain.
    local variants = (storage.map_force_to_planets or {})[force_name] or {}
    for _, variant_name in pairs(variants) do
        local surface = game.surfaces[variant_name]
        if surface and surface.valid and not seen[surface.name] then
            seen[surface.name] = true
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

    -- If the team was in pre-start staging, restore the leaving player's permissions
    -- before changing their force (release_team_slot clears pre_start_pending via
    -- wipe_slot_state, so check it now while the flag is still set).
    if (storage.pre_start_pending or {})[old_force_name] then
        local default = game.permissions.get_group("Default")
        if default then default.add_player(player) end
    end

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
