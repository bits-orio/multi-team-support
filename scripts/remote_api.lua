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
local helpers       = require("scripts.helpers")

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

-- ═══ Open Discord Bridge forwarding ═══════════════════════════════════
--
-- Mirror MTS events to the Open Discord Bridge (interface open-discord-bridge-v1)
-- when it is installed. The remote.interfaces guard keeps the bridge an OPTIONAL
-- dependency of MTS — nothing breaks if it isn't present.

local BRIDGE_INTERFACE = "open-discord-bridge-v1"

-- Emoji shown in the bridge's "[mts → …]" category tag, keyed by mts.* event suffix.
-- Applied by emit_to_bridge unless the caller passes its own data.label. Emoji rules
-- (the bridge sends these to Discord verbatim from a bot):
--   • Unicode emoji (🔬, 🚀, …) always render — simplest, no setup.
--   • A bare :shortcode: does NOT render from a bot; it shows literally.
--   • A CUSTOM emoji must be its raw form <:name:id> AND live on a server the bot is in
--     (your own). Other servers' emoji (e.g. the official Factorio server's) won't render,
--     regardless of bot permissions — it's server membership, not a permission. Same-server
--     custom emoji need no special permission.
--   • Get the raw <:name:id>: type "\:lab:" (backslash first) in Discord and send it.
local BRIDGE_LABELS = {
    research_finished    = "<:lab:1507982217102753962>", -- a :lab: uploaded to our own server
    player_joined        = "📥",
    player_left          = "📤",
    player_joined_team   = "➕",
    player_left_team     = "➖",
    player_switched_team = "🔀",
    team_created         = "🏁",
    team_released        = "🏳️",
    team_surface_created = "🌎",
    milestone_first      = "🥇",
    milestone_record     = "⏱️",
}

--- Emit an arbitrary event to the bridge (no-op if the bridge isn't installed). Fills in
--- the category-tag emoji from BRIDGE_LABELS unless the caller already set data.label.
function remote_api.emit_to_bridge(event, data)
    if remote.interfaces[BRIDGE_INTERFACE] then
        data = data or {}
        if data.label == nil then
            data.label = BRIDGE_LABELS[(event:gsub("^mts%.", ""))]
        end
        remote.call(BRIDGE_INTERFACE, "emit", { event = event, data = data })
    end
end

--- Declare the mts.* event catalog so the bridge / control plane can offer
--- routable toggles without hardcoding MTS. Mutates the bridge's storage, so
--- call only from on_init / on_configuration_changed (never from on_load).
function remote_api.register_with_bridge()
    if not remote.interfaces[BRIDGE_INTERFACE] then return end
    remote.call(BRIDGE_INTERFACE, "register_source", {
        namespace = "mts",
        events = {
            { key = "team_created",         description = "A team was created" },
            { key = "team_released",        description = "A team was released" },
            { key = "player_joined_team",   description = "A player joined a team" },
            { key = "player_left_team",     description = "A player left a team" },
            { key = "team_surface_created", description = "A team surface was created" },
            { key = "milestone_first",      description = "A team set a first-to-produce record" },
            { key = "milestone_record",     description = "A team set a production speed record" },
            { key = "research_finished",    description = "A team finished a technology" },
            { key = "player_joined",        description = "A player joined the game (team-aware)" },
            { key = "player_left",          description = "A player left the game (team-aware)" },
            { key = "player_switched_team", description = "A player switched teams mid-game" },
        },
    })
    -- We announce these ourselves with team info, so turn off the bridge's team-less
    -- baseline versions. The bridge only suppresses a baseline event while we're loaded.
    for _, key in ipairs({ "research_finished", "player_joined", "player_left" }) do
        remote.call(BRIDGE_INTERFACE, "set_baseline", { event = key, enabled = false })
    end
end

-- ensure_bridge_registered re-applies register_with_bridge once per session. on_init /
-- on_configuration_changed don't fire on a plain save reload (no version/mod-list change),
-- so a save that was running before the bridge existed — or a content-only mod edit during
-- development — would otherwise never (re)disable the baselines. Driving it from on_tick
-- (storage mutation is allowed there) makes the registration self-healing every session.
-- The flag is a module-load local, so it resets to false on each load.
local bridge_registered_this_session = false
function remote_api.ensure_bridge_registered()
    if bridge_registered_this_session then return end
    bridge_registered_this_session = true
    remote_api.register_with_bridge()
end

--- Enrich a raise payload with Discord-friendly names (player + team display name)
--- without mutating the original event payload.
local function bridge_payload(payload)
    local data = {}
    for k, v in pairs(payload) do data[k] = v end
    if payload.player_index then
        local p = game.get_player(payload.player_index)
        if p then data.player = p.name end
    end
    if payload.force_name then
        data.team = (storage.team_names or {})[payload.force_name] or payload.force_name
    end
    return data
end

--- Build a human-readable sentence for the bridge to show. MTS owns this phrasing;
--- the bridge just displays the `text` field. Returns nil for unknown events (the
--- bridge then falls back to a key=value summary).
local function bridge_text(name, d)
    local team = d.team or d.force_name
    local who  = d.player or (d.player_index and ("player " .. d.player_index))
    if name == "on_team_created" then
        return who and string.format("%s created %s", who, team)
            or  string.format("%s was created", team)
    elseif name == "on_team_released" then
        return string.format("%s was released", team)
    elseif name == "on_player_joined_team" then
        return string.format("%s joined %s", who or "A player", team)
    elseif name == "on_player_left_team" then
        return string.format("%s left %s", who or "A player", team)
    elseif name == "on_team_surface_created" then
        return string.format("Surface %s was created for %s", d.surface_name, team)
    end
    return nil
end

-- ═══ Internal raise helpers ═══════════════════════════════════════════
--
-- Called from mts code at the points where the corresponding state
-- transition completes. Guarded against missing IDs so commenting an
-- event out of `remote_api.events` doesn't crash the callers. Each raise also
-- mirrors to the bridge under the mts.* namespace (with the on_ prefix stripped).

-- raise() fires the frozen mts-v1 script event for third-party mods and (unless
-- opts.no_bridge) mirrors it to the Open Discord Bridge. The force-change events set
-- no_bridge because their bridge presentation is handled specially in
-- on_player_changed_force (deduped against the connect/disconnect messages).
local function raise(name, payload, opts)
    opts = opts or {}
    payload = payload or {}
    local id = remote_api.events[name]
    if id then script.raise_event(id, payload) end
    if opts.no_bridge then return end
    local data = bridge_payload(payload)
    data.text = bridge_text(name, data)
    remote_api.emit_to_bridge("mts." .. name:gsub("^on_", ""), data)
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
    }, { no_bridge = true })
end

function remote_api.raise_player_left_team(player_index, force_name)
    raise("on_player_left_team", {
        player_index = player_index,
        force_name   = force_name,
    }, { no_bridge = true })
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
    local old_team = is_team_force_name(old_name)
    local new_team = is_team_force_name(new_name)

    -- Always fire the frozen mts-v1 script events for third-party mods (both halves of a
    -- switch). These no longer auto-bridge; the bridge presentation is decided below.
    if old_team then remote_api.raise_player_left_team(event.player_index, old_name) end
    if new_team then remote_api.raise_player_joined_team(event.player_index, new_name) end

    -- Bridge presentation: one deduped sentence per force change.
    local who = player and player.name or ("player " .. event.player_index)
    if old_team and new_team then
        -- Mid-game switch between two teams → a single "switched" line.
        remote_api.emit_to_bridge("mts.player_switched_team", {
            player = who,
            from   = helpers.team_display(old_name),
            to     = helpers.team_display(new_name),
            text   = string.format("%s switched to %s", who, helpers.team_display(new_name)),
        })
    elseif new_team then
        -- Joined a team from a non-team force. The initial auto-claim on connect
        -- coincides with the mts.player_joined connect message, so it's suppressed
        -- (flag set by the lifecycle handler); deliberate later joins still announce.
        local suppress = storage.odb_suppress_claim
        if suppress and suppress[event.player_index] then
            suppress[event.player_index] = nil
        else
            remote_api.emit_to_bridge("mts.player_joined_team", {
                player = who,
                team   = helpers.team_display(new_name),
                text   = string.format("%s joined %s", who, helpers.team_display(new_name)),
            })
        end
    elseif old_team then
        -- Left a team to a non-team force (e.g. spectator). Disconnects don't reach
        -- here (disconnecting doesn't change force) — those go through mts.player_left.
        remote_api.emit_to_bridge("mts.player_left_team", {
            player = who,
            team   = helpers.team_display(old_name),
            text   = string.format("%s left %s", who, helpers.team_display(old_name)),
        })
    end
end

-- ═══ Server connect/disconnect (team-aware) ═══════════════════════════
--
-- Called from the player-lifecycle handlers. These replace the bridge's team-less
-- baseline player_joined/player_left (which register_with_bridge disables), tagging the
-- player's current team when they're on one.

local function connection_text(verb, player)
    local fn = player.force and player.force.name
    if is_team_force_name(fn) then
        return string.format("%s %s — %s", player.name, verb, helpers.team_display(fn))
    end
    return string.format("%s %s", player.name, verb)
end

function remote_api.emit_player_joined(player)
    if not (player and player.valid) then return end
    local fn = player.force and player.force.name
    remote_api.emit_to_bridge("mts.player_joined", {
        player       = player.name,
        team         = is_team_force_name(fn) and helpers.team_display(fn) or nil,
        online_count = #game.connected_players,
        text         = connection_text("joined the game", player),
    })
end

function remote_api.emit_player_left(player)
    if not (player and player.valid) then return end
    local fn = player.force and player.force.name
    remote_api.emit_to_bridge("mts.player_left", {
        player       = player.name,
        team         = is_team_force_name(fn) and helpers.team_display(fn) or nil,
        online_count = #game.connected_players,
        text         = connection_text("left the game", player),
    })
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
