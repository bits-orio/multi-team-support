-- Multi-Team Support - scripts/team_rename.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- Single source of truth for the team-rename rule, shared by the /mts-rename
-- command (scripts/commands/team.lua) and the Team Settings GUI
-- (gui/team_settings.lua). The two used to carry diverged copies -- most
-- importantly the GUI path never raised on_team_renamed, so mts-v1 consumer
-- mods missed every GUI-initiated rename.
--
-- Require note: gui.team_settings does a RUNTIME require of this module inside
-- its click/confirm handlers (not at top level), so this module CAN require
-- gui.team_settings at top level (for update_all_for_force + MAX_TEAM_NAME_LEN)
-- without forming a load-time cycle.

local helpers       = require("scripts.helpers")
local force_utils   = require("scripts.force_utils")
local remote_api    = require("scripts.remote_api")
local spawn_labels  = require("scripts.spawn_labels")
local teams_gui     = require("gui.teams")
local awards_gui    = require("gui.awards")
local pen_gui       = require("gui.pen_gui")
local team_settings = require("gui.team_settings")

local rename = {}

--- Apply the whole rename rule once. Returns ok:boolean, err:string|nil.
--- ok=true, err=nil means the rename was applied OR was a no-op (name unchanged).
--- ok=false, err=<message> means it was rejected; the caller prints the message.
function rename.attempt(player, raw_text)
    if not (player and player.valid) then return false, nil end
    local force_name = player.force and player.force.name
    if not (force_name and force_name:find("^team%-")) then
        return false, "You are not on a team yet."
    end
    if not force_utils.is_team_leader(player) then
        return false, "Only the team leader can rename the team."
    end

    local new_name = (raw_text or ""):match("^%s*(.-)%s*$")
    if new_name == "" then
        return false, "Team name cannot be empty."
    end
    local max_len = team_settings.MAX_TEAM_NAME_LEN or 16
    if #new_name > max_len then
        return false, "Team name is too long (max " .. max_len .. " characters)."
    end
    if new_name == helpers.display_name(force_name) then
        return true  -- unchanged: no-op, no broadcast/event
    end

    storage.team_names = storage.team_names or {}
    for fn, nm in pairs(storage.team_names) do
        if fn ~= force_name and nm == new_name then
            return false, "Another team already uses that name."
        end
    end

    storage.team_names[force_name] = new_name
    helpers.broadcast("[Team] " .. helpers.colored_name(player.name, player.chat_color)
        .. " renamed their team to " .. helpers.team_tag_with_leader(force_name) .. ".")
    remote_api.raise_team_renamed(force_name, new_name)

    -- Full refresh fan-out (the superset of what the two old paths each did):
    -- spawn labels, teams panel, awards panel, team-settings panels, and the
    -- landing-pen recruiting list all cache the team name.
    spawn_labels.refresh_for_force(force_name)
    teams_gui.update_all()
    awards_gui.update_all()
    team_settings.update_all_for_force(force_name)
    pen_gui.update_pen_gui_all()
    return true
end

return rename
