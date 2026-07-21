-- Multi-Team Support - scripts/pause/notify.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- Player-facing pause notification: a persistent force alert while a team is
-- paused (ADR-0004: alerts carry persistent team state, chat carries events).
-- Wording is source-distinct -- an admin pause says so, a scripted pause
-- (the pause_team remote; e.g. a docking mod's routine cycles) uses neutral
-- wording, so the alert never claims an admin action that didn't happen.
--
-- The anchor entity is ENSURE-ON-USE, never create-on-claim: no team surface
-- exists at claim time, and no anchor survives contact with the consumer
-- ecosystem (cave-collapse mods die() entities regardless of protected /
-- destructible, BNM clears entity footprints near spawn, MDW retires the
-- claim-time home surface on a team's first warp). It is found-or-recreated
-- immediately before every use and dies naturally with its surface.
--
-- Callers reach this from inside pause_team / unpause_team, which consumers
-- invoke via unprotected remote.call from tick handlers -- the call sites
-- pcall every entry point here, and nothing in this module may be expensive.

local pause_state   = require("scripts.pause.state")
local admin_flags   = require("scripts.admin_flags")
local surface_utils = require("scripts.surface_utils")

local notify = {}

local ANCHOR_NAME = "mts-alert-anchor"
local ALERT_ICON  = { type = "item", name = "power-switch" }

local MESSAGES = {
    admin  = { "mts-alerts.team-paused-admin" },
    script = { "mts-alerts.team-paused-script" },
}

-- Find (radius-matched, like ensure_passive_radar -- the anchor has a zero
-- collision box, so find_entity is unreliable) or create the anchor on a
-- currently-valid owned surface, home first. Tolerates clone-duplicated
-- anchors by taking the first match. Returns nil when the team owns no valid
-- surface at all -- then there is nowhere sensible to point an alert anyway.
local function ensure_anchor(force)
    -- Degrade gracefully when the anchor prototype isn't loaded (a save reload
    -- picks up new control code immediately, but prototypes only load at full
    -- game launch) -- the pause itself must still work, just without the alert.
    if not prototypes.entity[ANCHOR_NAME] then return nil end

    local surface = surface_utils.get_home_surface(force)
    if not (surface and surface.valid) then
        surface = nil
        for _, s in pairs(game.surfaces) do
            if s.valid and surface_utils.get_owner(s) == force.name then
                surface = s
                break
            end
        end
    end
    if not surface then return nil end

    local pos = force.get_spawn_position(surface)
    local anchor = surface.find_entities_filtered{
        name = ANCHOR_NAME, position = pos, radius = 1,
    }[1]
    if not (anchor and anchor.valid) then
        anchor = surface.create_entity{ name = ANCHOR_NAME, position = pos, force = force }
    end
    if anchor and anchor.valid then
        anchor.destructible = false
        anchor.protected    = true
        if anchor.force ~= force then anchor.force = force end
    end
    return anchor
end

--- Raise the paused alert for every connected member. source: "admin"|"script".
function notify.show(force_name, source)
    if not admin_flags.flag("team_alerts_enabled") then return end
    local force = game.forces[force_name]
    if not (force and force.valid) then return end
    local anchor = ensure_anchor(force)
    if not anchor then return end
    source = MESSAGES[source] and source or "script"
    -- Remember the wording for members who join mid-pause.
    storage.pause_alert_source = storage.pause_alert_source or {}
    storage.pause_alert_source[force_name] = source
    force.add_custom_alert(anchor, ALERT_ICON, MESSAGES[source], true)
end

--- Remove the paused alert on resume. The anchor may have died mid-pause.
function notify.clear(force_name)
    local force = game.forces[force_name]
    if not (force and force.valid) then return end
    if storage.pause_alert_source then storage.pause_alert_source[force_name] = nil end
    -- No prototype loaded -> no anchors and no alerts were ever raised.
    if not prototypes.entity[ANCHOR_NAME] then return end
    local anchor
    for _, s in pairs(game.surfaces) do
        if s.valid and surface_utils.get_owner(s) == force.name then
            local found = s.find_entities_filtered{ name = ANCHOR_NAME }[1]
            if found and found.valid then anchor = found break end
        end
    end
    if anchor then
        force.remove_alert{ entity = anchor }
    else
        -- Anchor died mid-pause (its alerts die with it engine-side); scoped
        -- fallback only -- NEVER the empty filter, which clears the whole tray.
        pcall(force.remove_alert, { type = defines.alert_type.custom, icon = ALERT_ICON })
    end
end

--- Re-raise for a member who joins while their team is paused (a force alert
--- only reaches players connected at raise time).
function notify.on_player_joined(player)
    if not admin_flags.flag("team_alerts_enabled") then return end
    if not (player and player.valid) then return end
    local force_name = player.force.name
    if not pause_state.is_paused(force_name) then return end
    local anchor = ensure_anchor(player.force)
    if not anchor then return end
    local source = (storage.pause_alert_source or {})[force_name] or "script"
    pcall(function() player.add_custom_alert(anchor, ALERT_ICON, MESSAGES[source], true) end)
end

return notify
