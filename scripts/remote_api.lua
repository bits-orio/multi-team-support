-- Multi-Team Support - scripts/remote_api.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
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
local team_clock    = require("scripts.team_clock")
local spawn_labels  = require("scripts.spawn_labels")

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

    -- Raised once per registered custom tab each time a player's Team Settings
    -- panel is (re)built. Payload: { player_index, tab_name, element }, where
    -- `element` is the empty content frame the registering mod should populate.
    on_team_tab_built        = script.generate_event_name(),

    -- Raised once per registered welcome tab each time the welcome screen is
    -- (re)built. Payload: { player_index, tab_name, element }, where `element`
    -- is the empty content frame the registering mod should populate. Registered
    -- (downstream-mod) tabs are shown FIRST, before MTS's own About/Discord, and
    -- the first one is selected by default -- so a scenario like Expanse leads.
    on_welcome_tab_built     = script.generate_event_name(),

    -- Raised once per registered widget each time a player opens a space
    -- platform hub. Payload: { player_index, widget_name, element, entity },
    -- where `element` is the empty content frame anchored into the hub GUI for
    -- the registering mod to fill, and `entity` is the platform hub being
    -- opened (use entity.surface.platform for the platform / its location).
    on_platform_hub_gui_built = script.generate_event_name(),

    -- Raised when an admin adds entries to the starter-items list while a
    -- delivery override is registered (see register_starter_item_delivery).
    -- Payload: { items = { {name=, count=}, ... } }. The registering mod is then
    -- responsible for delivering them (e.g. into team logistic chests) since MTS
    -- skips the default character-inventory grant while an override is active.
    on_starter_items_added    = script.generate_event_name(),

    -- Raised when a team is renamed. Payload: { force_name, new_name }. (Not
    -- `name` -- that key is reserved in event tables for the event id.) Lets a
    -- mod refresh anything that shows the team name.
    on_team_renamed           = script.generate_event_name(),

    -- ── v2 candidates (uncomment to enable) ──────────────────────────
    -- on_team_leader_changed   = script.generate_event_name(),
    -- on_team_paused           = script.generate_event_name(),
    -- on_team_resumed          = script.generate_event_name(),
    -- on_friendship_activated  = script.generate_event_name(),
    -- on_friendship_broken     = script.generate_event_name(),
    -- on_team_surfaces_cleaned = script.generate_event_name(),
}

-- ═══ Custom Team Settings tabs ════════════════════════════════════════
--
-- Other mods can add their own tab to the Team Settings panel. They register
-- ONCE, in their on_init / on_configuration_changed (where remote.call is
-- legal) via:
--     remote.call("mts-v1", "register_team_tab",
--         { name = "my-mod", caption = "My Mod", order = "z" })
-- and listen to the on_team_tab_built event to populate the content frame they
-- are handed.
--
-- The registry lives in `storage` so it survives save/load and is identical on
-- every peer. This is what makes the API multiplayer-safe: a client joining
-- mid-game (or any reload) can't remote.call in on_load to re-register, so a
-- session-scoped registry would be empty on the joiner while populated on the
-- host -- a handler-identity mismatch / desync risk. Persisting it sidesteps
-- that: the spec is plain data and rides along in the save.
local function tab_registry()
    storage.mts_custom_tabs = storage.mts_custom_tabs or {}
    return storage.mts_custom_tabs
end

function remote_api.register_team_tab(spec)
    if type(spec) ~= "table" or type(spec.name) ~= "string" then return end
    tab_registry()[spec.name] = {
        name    = spec.name,
        caption = spec.caption or spec.name,
        order   = spec.order or spec.name,
    }
end

--- Registered custom tabs, sorted by order then name.
function remote_api.get_team_tabs()
    local list = {}
    for _, def in pairs(tab_registry()) do list[#list + 1] = def end
    table.sort(list, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.name < b.name
    end)
    return list
end

-- ═══ Custom welcome-screen tabs ═══════════════════════════════════════
--
-- Same contract as the team tabs above, for the centered welcome screen. A
-- downstream mod (e.g. a scenario like Expanse) registers ONCE in its on_init /
-- on_configuration_changed via:
--     remote.call("mts-v1", "register_welcome_tab",
--         { name = "my-mod", caption = "My Mod", order = "a" })
-- and listens to on_welcome_tab_built to fill the content frame it is handed.
-- Registered tabs render BEFORE MTS's own About/Discord and the first is
-- selected by default, so the host scenario leads the welcome screen. Registry
-- lives in storage for the same multiplayer-safe reason as the team tabs.
local function welcome_tab_registry()
    storage.mts_welcome_tabs = storage.mts_welcome_tabs or {}
    return storage.mts_welcome_tabs
end

function remote_api.register_welcome_tab(spec)
    if type(spec) ~= "table" or type(spec.name) ~= "string" then return end
    welcome_tab_registry()[spec.name] = {
        name    = spec.name,
        caption = spec.caption or spec.name,
        order   = spec.order or spec.name,
    }
end

--- Registered welcome tabs, sorted by order then name.
function remote_api.get_welcome_tabs()
    local list = {}
    for _, def in pairs(welcome_tab_registry()) do list[#list + 1] = def end
    table.sort(list, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.name < b.name
    end)
    return list
end

-- Space platform hub widgets: any mod can anchor its own UI into the native
-- space-platform-hub GUI (e.g. an "establish base" action). Register ONCE in
-- on_init / on_configuration_changed; the registry persists in storage so it
-- survives reloads/joins and is identical on every peer (same multiplayer-safe
-- design as the team tabs above). Listen to on_platform_hub_gui_built to fill
-- the anchored frame each time a player opens a hub.
local function hub_widget_registry()
    storage.mts_hub_widgets = storage.mts_hub_widgets or {}
    return storage.mts_hub_widgets
end

function remote_api.register_platform_hub_widget(spec)
    if type(spec) ~= "table" or type(spec.name) ~= "string" then return end
    hub_widget_registry()[spec.name] = {
        name     = spec.name,
        caption  = spec.caption,              -- optional frame caption
        order    = spec.order or spec.name,
        position = spec.position or "right",  -- relative_gui_position key
    }
end

--- Registered platform-hub widgets, sorted by order then name.
function remote_api.get_platform_hub_widgets()
    local list = {}
    for _, def in pairs(hub_widget_registry()) do list[#list + 1] = def end
    table.sort(list, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.name < b.name
    end)
    return list
end

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

function remote_api.raise_starter_items_added(items)
    raise("on_starter_items_added", { items = items or {} }, { no_bridge = true })
end

function remote_api.raise_team_renamed(force_name, new_name)
    raise("on_team_renamed", { force_name = force_name, new_name = new_name }, { no_bridge = true })
end

-- ═══ Starter-item delivery override ═══════════════════════════════════
--
-- A consumer mod (e.g. Brave New MTS, whose teams have no player character to
-- receive items) can take over delivery of the admin-configured starter items.
-- While an override is registered, MTS stops inserting starter items into player
-- inventories and instead raises on_starter_items_added for live additions; the
-- consumer reads the persisted list via get_starter_items for teams that spawn
-- later. The registering mod name is stored so the override self-clears if that
-- mod is later removed (checked in on_configuration_changed).

function remote_api.register_starter_item_delivery(mod_name)
    storage.mts_starter_delivery = (type(mod_name) == "string") and mod_name or "unknown"
end

function remote_api.starter_delivery_override()
    return storage.mts_starter_delivery ~= nil
end

--- Drop a stale override if the mod that registered it is no longer loaded, so
--- removing the consumer restores the default character-inventory delivery.
function remote_api.validate_delivery_override()
    local mod = storage.mts_starter_delivery
    if mod and mod ~= "unknown" and not script.active_mods[mod] then
        storage.mts_starter_delivery = nil
    end
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
        online_ticks   = team_clock.online_ticks(force_name),
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

--- The admin-configured starter items ({name=, count=} list). Used by a
--- delivery-override consumer to seed teams that spawn after items were added.
local function get_starter_items_impl()
    return storage.starter_items or {}
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
        get_starter_items  = get_starter_items_impl,

        -- MTS-styled team label: the team's coloured tag plus its current leader in
        -- brackets (rich text, e.g. "[color]Team Pioneers[/color] [Alice]"). Lets a
        -- consumer draw a label consistent with MTS's colour/leader convention. Reflects
        -- live state, so re-fetch to pick up leader/rename/colour changes.
        get_team_label = function(force_name)
            if type(force_name) ~= "string" then return nil end
            return helpers.team_tag_with_leader(force_name)
        end,

        -- Suppress (or restore) MTS's default spawn label on a surface a consumer mod
        -- labels itself (e.g. Expanse draws a combined overlay on each cell world).
        -- enabled=false removes the MTS label and stops it being redrawn; =true restores it.
        set_spawn_label_enabled = function(surface_name, enabled)
            spawn_labels.set_enabled(surface_name, enabled and true or false)
        end,

        -- Take over starter-item delivery (see on_starter_items_added). Pass your
        -- mod name so the override self-clears if your mod is removed.
        register_starter_item_delivery =
            function(mod_name) remote_api.register_starter_item_delivery(mod_name) end,

        -- Team Settings tab registration (see on_team_tab_built event).
        register_team_tab  = function(spec) remote_api.register_team_tab(spec) end,

        -- Welcome-screen tab registration (see on_welcome_tab_built event).
        -- Registered tabs lead the welcome screen, before MTS's About/Discord.
        register_welcome_tab = function(spec) remote_api.register_welcome_tab(spec) end,

        -- Consumer-defined milestones. register_milestone({category, verb, noun,
        -- first_threshold, thresholds}) once (in on_init), then report_milestone(
        -- force_name, category, count) as a team's counter advances; MTS announces
        -- first/fastest via the same records + broadcast + Discord path as its built-in
        -- milestones. Impls live in milestones/engine.lua (injected, to avoid a
        -- circular require). No-op until the engine has injected them.
        register_milestone = function(spec)
            if remote_api.register_milestone_impl then remote_api.register_milestone_impl(spec) end
        end,
        report_milestone = function(force_name, category, count)
            if remote_api.report_milestone_impl then remote_api.report_milestone_impl(force_name, category, count) end
        end,

        -- Space platform hub widget registration (see on_platform_hub_gui_built).
        register_platform_hub_widget =
            function(spec) remote_api.register_platform_hub_widget(spec) end,

        -- Disband a team: move every member back to the landing pen, release
        -- the slot, and clean up the team's surfaces. Lets a mod implement a
        -- loss condition (e.g. a critical structure destroyed). The real work
        -- lives in scripts/team_disband.lua, which injects it here -- it needs
        -- team_slots + landing_pen, which would circular-require remote_api.
        disband_team = function(force_name)
            if remote_api.disband_impl then remote_api.disband_impl(force_name) end
        end,

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
