-- Multi-Team Support - force_utils.lua
-- Author: bits-orio
-- License: MIT
--
-- Team pool management, force creation, tech syncing, surface ownership
-- checks, and bounce-home logic.
--
-- Forces are pre-created as "team-1" through "team-N" in on_init.
-- Players claim a team slot on spawn and release it when leaving.
-- Force names never change — only the display name and leader can change.

local helpers       = require("scripts.helpers")
local spectator     = require("scripts.spectator")
local surface_utils = require("scripts.surface_utils")
local planet_map    = require("scripts.planet_map")
local friendship    = require("gui.friendship")
local remote_api    = require("scripts.remote_api")
local spawn_labels  = require("scripts.spawn_labels")

local force_utils = {}

-- ─── Force State Helpers ──────────────────────────────────────────────

--- Copy all researched technologies, quality unlocks, and space platform
--- unlock from one force to another.
local function copy_force_state(source, target)
    for name, tech in pairs(source.technologies) do
        if tech.researched then
            local t = target.technologies[name]
            -- Guard against re-writing an already-researched flag in case
            -- Factorio ever fires on_research_finished on a redundant set.
            if t and not t.researched then t.researched = true end
        end
    end
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

--- Reset a force's tech tree back to unresearched state.
--- Used when recycling a team slot so stale research doesn't leak
--- to the next occupant.
---
--- Team forces are pre-created ("team-1"..."team-N") and the same
--- LuaForce object is recycled across occupants. Engine-level state on
--- that object — including per-force research-trigger progress (e.g.
--- "craft 50 iron plates toward steam-power") and tech modifiers —
--- survives a naive `tech.researched = false` loop. `LuaForce.reset()`
--- is the nuclear reset that zeroes all of it.
---
--- `reset()` also wipes diplomacy, so we re-apply the baseline cease-fire
--- with all non-enemy forces and restore spectator-force integration.
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

-- ─── Team Pool Management ─────────────────────────────────────────────

--- Return the max teams setting value.
function force_utils.max_teams()
    return settings.startup["mts_max_teams"].value
end

--- Check if a force name belongs to the team pool (matches "team-N" pattern).
function force_utils.is_team_force(force_name)
    return force_name:find("^team%-") ~= nil
end

--- Pre-create all team forces during on_init.
--- Sets up diplomacy (cease-fire with all non-enemy forces) and
--- spectator integration for each team force.
function force_utils.create_team_pool()
    local max = force_utils.max_teams()
    storage.team_pool       = {}
    storage.team_names      = {}
    storage.team_leader     = {}
    storage.team_clock_start = {}

    for i = 1, max do
        local force_name = "team-" .. i
        local ok, new_force = pcall(game.create_force, force_name)
        if not ok then
            log("[multi-team-support] WARNING: Could not create " .. force_name
                .. " (64 force limit reached)")
            break
        end

        -- Copy baseline research from the default player force
        copy_force_state(game.forces.player, new_force)

        -- Set up diplomacy: cease-fire with all non-enemy forces
        for _, other_force in pairs(game.forces) do
            if other_force.name ~= "enemy" and other_force ~= new_force then
                new_force.set_cease_fire(other_force, true)
                other_force.set_cease_fire(new_force, true)
            end
        end

        -- Integrate with spectator system
        spectator.setup_force(new_force)

        -- Mark slot as available, set default display name
        storage.team_pool[i]  = "available"
        storage.team_names[force_name] = string.format("Team %02d", i)

        log("[multi-team-support] created team slot: " .. force_name)
    end
end

--- Claim the next available team slot for a player.
--- Resets the force's tech tree, copies baseline research, assigns the
--- player, sets force color, and starts the team clock.
--- Returns the force name, or nil if no slots available.
function force_utils.claim_team_slot(player)
    storage.team_pool = storage.team_pool or {}

    -- Find first available slot
    local slot = nil
    for i = 1, force_utils.max_teams() do
        if storage.team_pool[i] == "available" then
            slot = i
            break
        end
    end

    if not slot then
        player.print("No team slots available. All " .. force_utils.max_teams()
            .. " teams are occupied.")
        return nil
    end

    local force_name = "team-" .. slot
    local force = game.forces[force_name]
    if not force then return nil end

    -- Reset and copy baseline research (prevents stale tech from previous occupant)
    reset_force_state(force)
    copy_force_state(game.forces.player, force)

    -- Assign player to the team force
    player.force = force

    -- Set force display color to the leader's (this player's) color
    -- Note: force.color is read-only; use custom_color to override
    force.custom_color = player.color

    -- Track team leader and mark slot as occupied
    storage.team_leader = storage.team_leader or {}
    storage.team_leader[force_name] = player.index
    storage.team_pool[slot] = "occupied"

    -- Start team clock on first claim (reset when slot is released)
    storage.team_clock_start = storage.team_clock_start or {}
    if not storage.team_clock_start[force_name] then
        storage.team_clock_start[force_name] = game.tick
        log("[multi-team-support] team clock started for " .. force_name
            .. " at tick " .. game.tick)
    end

    -- Space Age: reapply locks so only their home variant is unlocked.
    -- Safe to call when Space Age isn't active (no-op inside).
    planet_map.apply_force_locks(force)

    log("[multi-team-support] " .. player.name .. " claimed slot " .. slot
        .. " (" .. force_name .. ")")

    -- Public event: a team transitioned available → occupied. Fired AFTER
    -- the slot is fully wired so subscribers see consistent state. The
    -- companion on_player_joined_team event fires automatically via
    -- on_player_changed_force when player.force was set above.
    remote_api.raise_team_created(force_name, player.index)

    return force_name
end

--- Strip a released team from a records table.
--- Records are keyed by tech/milestone, each with first/fastest holders.
--- When the released team held both positions, the entry is deleted.
--- When they held only one position, the remaining other team is promoted
--- into both slots so a fresh team doesn't immediately "beat its own
--- ghost" after reclaiming the slot.
local function strip_team_from_records(records_table, team)
    if not records_table then return end
    for key, entry in pairs(records_table) do
        local first_is_mine   = entry.first   and entry.first.team   == team
        local fastest_is_mine = entry.fastest and entry.fastest.team == team
        if first_is_mine and fastest_is_mine then
            records_table[key] = nil
        elseif first_is_mine then
            entry.first = entry.fastest
        elseif fastest_is_mine then
            entry.fastest = entry.first
        end
    end
end

--- Clear every per-slot storage entry + break engine friendship ties for
--- a team slot. Shared between `release_team_slot` (full release flow)
--- and the `on_configuration_changed` migration, which retroactively
--- cleans slots that were left "available" under pre-0.3.7 code.
---
--- Does NOT touch the force object's tech state, the slot pool entry,
--- the leader, or the team clock — those are lifecycle concerns handled
--- by the caller.
function force_utils.wipe_slot_state(force_name)
    local slot = tonumber(force_name:match("^team%-(%d+)$"))
    if not slot then return end

    -- Reset display name in case a previous occupant used /mts-rename
    storage.team_names = storage.team_names or {}
    storage.team_names[force_name] = string.format("Team %02d", slot)

    -- Strip this team from record holders so a fresh clock on reclaim
    -- doesn't produce tiny elapsed values that instantly beat the
    -- previous incarnation's records.
    strip_team_from_records(storage.tech_records,      force_name)
    strip_team_from_records(storage.milestone_records, force_name)

    -- Clear per-force milestone-threshold gate and research timeline
    if storage.milestone_reached   then storage.milestone_reached[force_name]   = nil end
    if storage.tech_research_ticks then storage.tech_research_ticks[force_name] = nil end

    -- Drop "player previously left this team" markers so former members
    -- aren't treated as rejoiners (stripped of inventory) when the slot's
    -- next occupant invites them.
    if storage.left_teams then
        for _, teams in pairs(storage.left_teams) do
            teams[force_name] = nil
        end
    end

    -- Break engine friendship and clear friend_intents to/from this
    -- team. Must run BEFORE reset_force_state: break_pair consults
    -- engine `get_friend` flags to decide whether to notify the
    -- spectator + visibility subsystems, and `force.reset()` wipes those
    -- flags silently.
    friendship.break_all_for(force_name)
end

--- Release a team slot back to the pool.
--- Wipes every per-force/per-slot storage entry and resets the force
--- object so the next occupant starts on a clean slate with no state
--- leaking from the previous incarnation.
function force_utils.release_team_slot(force_name)
    local slot = tonumber(force_name:match("^team%-(%d+)$"))
    if not slot then return end

    -- Slot lifecycle state
    storage.team_pool = storage.team_pool or {}
    storage.team_pool[slot] = "available"
    storage.team_leader = storage.team_leader or {}
    storage.team_leader[force_name] = nil
    storage.team_clock_start = storage.team_clock_start or {}
    storage.team_clock_start[force_name] = nil

    -- Per-slot storage + engine-friendship cleanup (shared with migration)
    force_utils.wipe_slot_state(force_name)

    -- Reset the force object itself. force.reset() clears researched
    -- flags, trigger-progress counters, tech modifiers, and the research
    -- queue — everything keyed inside the engine on the force object,
    -- which is reused across release/reclaim because team forces are
    -- pre-created and recycled. Diplomacy is re-applied inside.
    local force = game.forces[force_name]
    if force then
        reset_force_state(force)
        copy_force_state(game.forces.player, force)
        planet_map.apply_force_locks(force)
    end

    log("[multi-team-support] released team slot: " .. force_name)

    -- Public event: slot is back in the pool. Fired last so subscribers
    -- querying mts-v1 see the cleared state.
    remote_api.raise_team_released(force_name)
end

-- ─── Team Leader ──────────────────────────────────────────────────────

--- Return true if the player is the team leader of their current force.
function force_utils.is_team_leader(player)
    storage.team_leader = storage.team_leader or {}
    return storage.team_leader[player.force.name] == player.index
end

--- Return the number of players on a force.
function force_utils.force_member_count(force)
    local n = 0
    for _ in pairs(force.players) do n = n + 1 end
    return n
end

--- Pick the best new leader from a force, preferring connected players.
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

-- ─── Surface Cleanup ──────────────────────────────────────────────────

--- Delete all surfaces owned by a force and clean up related storage.
function force_utils.cleanup_force_surfaces(force_name)
    local deleted = {}
    -- Delete surfaces matching "{force_name}-{planet}" pattern
    for _, surface in pairs(game.surfaces) do
        if surface.valid and surface.name:find("^" .. force_name:gsub("%-", "%%-") .. "%-") then
            deleted[#deleted + 1] = surface.name
            game.delete_surface(surface)
        end
    end
    -- Also delete platforms owned by this force
    local force = game.forces[force_name]
    if force then
        for _, platform in pairs(force.platforms) do
            if platform.valid then
                deleted[#deleted + 1] = platform.name
                platform.destroy()
            end
        end
    end
    -- Clean up player_surfaces entries pointing to deleted surfaces
    storage.player_surfaces = storage.player_surfaces or {}
    for idx, ps in pairs(storage.player_surfaces) do
        for _, name in pairs(deleted) do
            if ps.name == name then
                storage.player_surfaces[idx] = nil
                break
            end
        end
    end
    return deleted
end

-- ─── Remove from Team ─────────────────────────────────────────────────

--- Remove a player from their current team.
--- With numbered forces, this is much simpler than the old system:
---   - The team's force name never changes (it's always "team-N").
---   - No force swapping is needed when the leader leaves.
---   - Departing player gets a fresh team slot with baseline research.
---
--- Three cases:
---   1. Solo player (last member): release team slot, clean up surfaces.
---   2. Leader leaving a multi-player team: elect new leader, player leaves.
---   3. Non-leader leaving: player simply leaves.
---
--- The caller is responsible for placing the player back in the landing pen.
function force_utils.remove_from_team(player)
    local old_force = player.force
    local old_force_name = old_force.name
    local member_count = force_utils.force_member_count(old_force)

    -- Track that this player has left this team (used for anti-abuse on rejoin)
    storage.left_teams = storage.left_teams or {}
    storage.left_teams[player.index] = storage.left_teams[player.index] or {}
    storage.left_teams[player.index][old_force_name] = true

    storage.team_leader = storage.team_leader or {}
    local is_leader = (storage.team_leader[old_force_name] == player.index)
    local cn_player = helpers.colored_name(player.name, player.chat_color)
    local team_tag  = helpers.team_tag(old_force_name)

    if member_count <= 1 then
        -- Solo player leaving: clean up surfaces and release the team slot.
        local deleted = force_utils.cleanup_force_surfaces(old_force_name)

        -- Move player to spectator force (they'll be placed in pen by caller)
        local spec_force = game.forces["spectator"]
        if spec_force then player.force = spec_force end

        -- Release the team slot back to the pool
        force_utils.release_team_slot(old_force_name)

        if #deleted > 0 then
            helpers.broadcast("[Team] " .. team_tag .. "'s base has been cleaned up.")
        end
    else
        -- Multi-player team: player leaves, team stays.
        -- Move player to spectator force (they'll be placed in pen by caller)
        local spec_force = game.forces["spectator"]
        if spec_force then player.force = spec_force end

        -- Notify remaining team members
        for _, member in pairs(old_force.players) do
            if member.connected then
                member.print(cn_player .. " has left " .. team_tag .. ".")
            end
        end

        -- Elect new leader if the departing player was the leader
        if is_leader then
            local new_leader = pick_new_leader(old_force, player.index)
            if new_leader then
                storage.team_leader[old_force_name] = new_leader.index
                -- Update force display color to new leader's color
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

-- ─── Quality Sync ─────────────────────────────────────────────────────

--- Periodically unlock "uncommon" quality for all team forces.
function force_utils.sync_quality_all_forces()
    for _, force in pairs(game.forces) do
        if force_utils.is_team_force(force.name) then
            pcall(function() force.unlock_quality("uncommon") end)
        end
    end
end

-- ─── Foreign Surface Detection ────────────────────────────────────────

--- Get the player's real force (accounts for spectator mode).
local function effective_force(player)
    local real_fn = spectator.get_effective_force(player)
    return game.forces[real_fn]
end

--- Check whether the player is on another team's private surface.
--- Uses effective force (real force when spectating).
function force_utils.on_foreign_surface(player)
    local surface = player.surface
    if not surface then return false end
    local my_force = effective_force(player)
    if not my_force then return false end
    local my_force_name = my_force.name

    -- Surface naming scheme #1 (non-Space-Age): "team-N-planet" cloned
    -- surface. Owning force is the prefix.
    local owner_force = surface.name:match("^(team%-%d+)%-%w+$")
    if owner_force and owner_force ~= my_force_name then return true end

    -- Surface naming scheme #2 (Space Age): "mts-{planet}-{slot}" per-team
    -- planet variant. Ownership is keyed by the slot, not the surface name —
    -- planet_map maintains the variant→force mapping. This case used to
    -- be missed; players who ended up on someone else's mts-nauvis-N
    -- (typically by exiting spectator from editor mode, where the
    -- exit returns them to their pre-spectator position) were not
    -- bounced home. They'd appear stuck on the foreign team's
    -- surface until they manually used "return to base".
    local variant_owner = planet_map.get_force_by_planet(surface.name)
    if variant_owner and variant_owner ~= my_force_name then return true end

    -- Check space platforms owned by other team forces
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

--- Find the player's home surface (uses effective force for spectator compat).
function force_utils.get_home_surface(player)
    local force = effective_force(player)
    if not force then return nil end
    return surface_utils.get_home_surface(force, player.index)
end

--- Bounce a player back to their home surface if they're on a foreign one.
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

--- Mark a player's clock as started.
function force_utils.start_player_clock(player)
    storage.player_clock_start = storage.player_clock_start or {}
    if not storage.player_clock_start[player.index] then
        storage.player_clock_start[player.index] = game.tick
        log("[multi-team-support] clock started for " .. player.name .. " at tick " .. game.tick)
    end
end

return force_utils
