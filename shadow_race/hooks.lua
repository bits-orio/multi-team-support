-- Multi-Team Support - shadow_race/hooks.lua
-- Author: bits-orio
-- License: MIT
--
-- The few places MTS's team lifecycle calls into Shadow Race. Kept in one
-- file so the seam between the two stays narrow and easy to see.

local recorder = require("shadow_race.recorder")
local archive  = require("shadow_race.archive")
local rivals   = require("shadow_race.rivals")
local announcer = require("shadow_race.announcer")
local standings = require("shadow_race.standings")
local helpers   = require("scripts.helpers")
local space_age = require("scripts.space_age")

recorder.set_mark_hook(announcer.on_mark)

local M = {}

--- Under Staged Start the members already stand on the team's planet when
--- the clock starts, so the run learns its home here; a direct claim puts
--- the leader on the planet a moment later, which the recorder sees then.
local function note_home(force_name)
    local force = game.forces[force_name]
    for _, player in pairs(force and force.players or {}) do
        local planet = player.physical_surface and player.physical_surface.planet
        if planet and planet.valid then
            recorder.arrive(force_name, space_age.parse_variant(planet.name) or planet.name)
            return
        end
    end
end

--- on_team_clock_started: the team's run begins, chasing what its leader
--- pinned or chased last. An auto-chase carried over gets its first target
--- at once, so the display never claims a lead it has not checked.
function M.on_clock_started(event)
    local force_name = event.force_name
    recorder.open(force_name, event.start_tick)
    note_home(force_name)
    rivals.on_run_opened(force_name)
    if rivals.is_auto(force_name) then standings.retarget(force_name) end
    announcer.reset(force_name)
end

--- on_player_joined_team.
function M.on_player_joined(event)
    recorder.add_member(event.force_name, event.player_index)
end

--- The slot is about to be released and wiped: the run goes to its
--- members, and teams chasing it live now chase the archived run.
function M.on_release(force_name)
    local run = recorder.run_of(force_name)
    if not run then return end
    local start, members = run.start, run.members
    local id = archive.close(force_name)
    rivals.on_run_closed(force_name, start, id)
    if not (id and rivals.enabled()) then return end
    -- Tell everyone who was on the run where it went.
    for player_index in pairs(members) do
        local player = game.get_player(player_index)
        if player and player.connected then
            player.print({"mts-chat.shadow-archived", helpers.ls_duration(run.ended)})
        end
    end
end

--- The player was removed from the game; their index can be reused.
function M.on_player_removed(player_index)
    archive.forget_player(player_index)
    rivals.forget_player(player_index)
end

return M
