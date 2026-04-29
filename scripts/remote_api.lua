-- Multi-Team Support - scripts/remote_api.lua
-- Author: bits-orio
-- License: MIT
--
-- Public remote interface ("mts-v1") + custom events for third-party mods
-- that need to integrate with multi-team-support (e.g. chunk-gen mods like
-- dangOreus, VoidBlock that need to know about team surfaces).
--
-- Stability contract: the interface name "mts-v1" and every function /
-- event listed below is frozen for the v1 lifetime. Adding new
-- functions/events is safe; renaming/removing is not. When breaking
-- changes are needed, register a new "mts-v2" interface alongside.
--
-- ─── Subscribing as a third-party mod ─────────────────────────────────
--
--   -- in your control.lua, AFTER on_init/on_load have run:
--   if remote.interfaces["mts-v1"] then
--       local id = remote.call("mts-v1", "get_event_id", "on_team_surface_created")
--       script.on_event(id, function(event)
--           -- event.surface_name, event.force_name
--       end)
--   end
--
-- ─── Querying state ───────────────────────────────────────────────────
--
--   if remote.interfaces["mts-v1"] then
--       local owner = remote.call("mts-v1", "get_surface_owner", "team-3-nauvis")
--       -- → "team-3" or nil
--   end

local surface_utils = require("scripts.surface_utils")

local remote_api = {}

-- ═══ Custom event IDs ═════════════════════════════════════════════════
--
-- Generated at module load — Factorio re-runs this file every session
-- (both on first init and on save load), so the IDs are stable for the
-- duration of each session. Third-party mods retrieve them via
-- remote.call("mts-v1", "get_event_id", "<name>") rather than hard-coding
-- numeric values, since the integers themselves may differ across
-- sessions.

remote_api.events = {
    on_team_created          = script.generate_event_name(),
    on_team_released         = script.generate_event_name(),
    on_player_joined_team    = script.generate_event_name(),
    on_player_left_team      = script.generate_event_name(),
    on_team_surface_created  = script.generate_event_name(),

    -- ── v2 candidates (uncomment to enable) ──────────────────────────
    -- on_team_leader_changed   = script.generate_event_name(),
    -- on_team_paused           = script.generate_event_name(),
    -- on_team_resumed          = script.generate_event_name(),
    -- on_friendship_activated  = script.generate_event_name(),
    -- on_friendship_broken     = script.generate_event_name(),
    -- on_team_surfaces_cleaned = script.generate_event_name(),
}

-- ═══ Internal raise helpers ═══════════════════════════════════════════
--
-- Called from mts code at the points where the corresponding state
-- transition completes. Guarded against missing IDs so commenting an
-- event out of `remote_api.events` doesn't crash the callers.

local function raise(name, payload)
    local id = remote_api.events[name]
    if id then script.raise_event(id, payload or {}) end
end

function remote_api.raise_team_created(force_name, leader_player_index)
    raise("on_team_created", {
        force_name   = force_name,
        player_index = leader_player_index,
    })
end

function remote_api.raise_team_released(force_name)
    raise("on_team_released", { force_name = force_name })
end

function remote_api.raise_player_joined_team(player_index, force_name)
    raise("on_player_joined_team", {
        player_index = player_index,
        force_name   = force_name,
    })
end

function remote_api.raise_player_left_team(player_index, force_name)
    raise("on_player_left_team", {
        player_index = player_index,
        force_name   = force_name,
    })
end

function remote_api.raise_team_surface_created(surface_name, force_name)
    raise("on_team_surface_created", {
        surface_name = surface_name,
        force_name   = force_name,
    })
end

-- ── v2 candidates (uncomment alongside the matching event ID) ────────
-- function remote_api.raise_team_leader_changed(force_name, old_player_index, new_player_index)
--     raise("on_team_leader_changed", {
--         force_name           = force_name,
--         old_leader_player_index = old_player_index,
--         new_leader_player_index = new_player_index,
--     })
-- end
--
-- function remote_api.raise_team_paused(force_name)
--     raise("on_team_paused", { force_name = force_name })
-- end
--
-- function remote_api.raise_team_resumed(force_name)
--     raise("on_team_resumed", { force_name = force_name })
-- end
--
-- function remote_api.raise_friendship_activated(force_name_a, force_name_b)
--     raise("on_friendship_activated", {
--         force_name_a = force_name_a,
--         force_name_b = force_name_b,
--     })
-- end
--
-- function remote_api.raise_friendship_broken(force_name_a, force_name_b)
--     raise("on_friendship_broken", {
--         force_name_a = force_name_a,
--         force_name_b = force_name_b,
--     })
-- end
--
-- function remote_api.raise_team_surfaces_cleaned(force_name, surface_names)
--     raise("on_team_surfaces_cleaned", {
--         force_name    = force_name,
--         surface_names = surface_names,
--     })
-- end

-- ═══ on_player_changed_force adapter ══════════════════════════════════
--
-- Called from control.lua's on_player_changed_force handler. Translates
-- a single Factorio event into the appropriate join/leave raises so the
-- buddy-join flow, /mts-rejoin, and admin force moves are all covered
-- automatically — callers don't have to remember to fire these.

local function is_team_force_name(name)
    return name and name:find("^team%-") ~= nil
end

function remote_api.on_player_changed_force(event)
    local old_name = event.force and event.force.name
    local player   = game.get_player(event.player_index)
    local new_name = player and player.force and player.force.name
    if is_team_force_name(old_name) then
        remote_api.raise_player_left_team(event.player_index, old_name)
    end
    if is_team_force_name(new_name) then
        remote_api.raise_player_joined_team(event.player_index, new_name)
    end
end

-- ═══ Query implementations ════════════════════════════════════════════

local function team_slot_status(force_name)
    local slot = tonumber(force_name:match("^team%-(%d+)$"))
    if not slot then return nil end
    return (storage.team_pool or {})[slot]
end

local function team_member_count(force)
    if not (force and force.valid) then return 0 end
    local n = 0
    for _ in pairs(force.players) do n = n + 1 end
    return n
end

local function get_team_info_impl(force_name)
    if not is_team_force_name(force_name) then return nil end
    local force = game.forces[force_name]
    if not force or not force.valid then return nil end

    local status       = team_slot_status(force_name)
    local leader_index = (storage.team_leader or {})[force_name]
    local clock_start  = (storage.team_clock_start or {})[force_name]
    local display_name = (storage.team_names or {})[force_name] or force_name
    local is_paused    = (storage.paused_forces or {})[force_name] and true or false

    return {
        force_name     = force_name,
        display_name   = display_name,
        status         = status,
        is_occupied    = status == "occupied",
        leader_player_index = leader_index,
        member_count   = team_member_count(force),
        is_paused      = is_paused,
        clock_start_tick = clock_start,
    }
end

local function get_team_list_impl()
    local list = {}
    local pool = storage.team_pool or {}
    -- Iterate slot indices in order so output is deterministic.
    local n = 0
    for slot in pairs(pool) do if slot > n then n = slot end end
    for slot = 1, n do
        local force_name = "team-" .. slot
        local info = get_team_info_impl(force_name)
        if info then list[#list + 1] = info end
    end
    return list
end

local function is_team_surface_impl(surface_name)
    if type(surface_name) ~= "string" then return false end
    local surface = game.surfaces[surface_name]
    if not surface then return false end
    return surface_utils.get_owner(surface) ~= nil
end

local function get_surface_owner_impl(surface_name)
    if type(surface_name) ~= "string" then return nil end
    local surface = game.surfaces[surface_name]
    if not surface then return nil end
    return surface_utils.get_owner(surface)
end

local function list_team_surfaces_impl(force_name)
    if not is_team_force_name(force_name) then return {} end
    local out = {}
    for _, surface in pairs(game.surfaces) do
        if surface.valid and surface_utils.get_owner(surface) == force_name then
            out[#out + 1] = surface.name
        end
    end
    return out
end

-- ── v2 candidates (uncomment to enable) ──────────────────────────────
-- local function get_team_home_surface_impl(force_name)
--     if not is_team_force_name(force_name) then return nil end
--     local force = game.forces[force_name]
--     if not force then return nil end
--     local s = surface_utils.get_home_surface(force, nil)
--     return s and s.valid and s.name or nil
-- end
--
-- local function is_team_paused_impl(force_name)
--     return (storage.paused_forces or {})[force_name] and true or false
-- end
--
-- local function are_teams_friends_impl(a, b)
--     local fa, fb = game.forces[a], game.forces[b]
--     if not (fa and fb) then return false end
--     return fa.get_friend(fb) and fb.get_friend(fa) or false
-- end
--
-- local function get_team_members_impl(force_name)
--     local force = game.forces[force_name]
--     if not (force and force.valid) then return {} end
--     local leader_idx = (storage.team_leader or {})[force_name]
--     local out = {}
--     for _, p in pairs(force.players) do
--         out[#out + 1] = {
--             player_index = p.index,
--             player_name  = p.name,
--             is_leader    = p.index == leader_idx,
--             is_connected = p.connected,
--         }
--     end
--     return out
-- end
--
-- local function get_landing_pen_count_impl()
--     local n = 0
--     local pen = game.surfaces["landing-pen"]
--     if not pen then return 0 end
--     for _, p in pairs(game.players) do
--         if p.connected and p.surface and p.surface.index == pen.index then
--             n = n + 1
--         end
--     end
--     return n
-- end

-- ═══ Remote interface registration ════════════════════════════════════

function remote_api.register()
    if remote.interfaces["mts-v1"] then
        remote.remove_interface("mts-v1")
    end
    remote.add_interface("mts-v1", {
        -- Event ID lookup
        get_event_id = function(name)
            return remote_api.events[name]
        end,

        -- Queries
        get_team_list      = get_team_list_impl,
        get_team_info      = get_team_info_impl,
        is_team_surface    = is_team_surface_impl,
        get_surface_owner  = get_surface_owner_impl,
        list_team_surfaces = list_team_surfaces_impl,

        -- ── v2 candidates (uncomment alongside the matching impl) ────
        -- get_team_home_surface = get_team_home_surface_impl,
        -- is_team_paused        = is_team_paused_impl,
        -- are_teams_friends     = are_teams_friends_impl,
        -- get_team_members      = get_team_members_impl,
        -- get_landing_pen_count = get_landing_pen_count_impl,

        -- ── Action functions (v2 candidates) ─────────────────────────
        -- notify_surface_generated: third-party mods call this to tell
        -- mts they generated chunks on a surface, so mts can rerun any
        -- per-team setup that depends on chunks existing.
        --
        -- notify_surface_generated = function(surface_name)
        --     -- TODO: dispatch to compat shims if we keep any.
        -- end,
        --
        -- request_planet_variant: Space Age — return the variant
        -- surface name for a base planet under a given team force.
        --
        -- request_planet_variant = function(force_name, base_planet)
        --     local m = (storage.map_force_to_planets or {})[force_name]
        --     return m and m[base_planet] or nil
        -- end,
    })
end

-- Register at module load so the interface is live before any event
-- handler runs. Factorio re-loads this file every session, which is why
-- the registration is idempotent (remove_interface guard above).
remote_api.register()

return remote_api
