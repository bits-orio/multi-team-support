-- scripts/team_teardown.lua
-- The single implementation of "destroy this team and free its slot".
--
-- Extracted from scripts/commands/admin.lua so the /mts-disband command, the
-- bulk Cleanup GUI and the auto-reaper all tear a team down the same way. The
-- rules about what happens to members (spectator force, pen return, spawned
-- flag) are knowledge, not text: a second copy would drift.

local helpers      = require("scripts.helpers")
local force_utils  = require("scripts.force_utils")
local landing_pen  = require("gui.landing_pen")
local spectator    = require("scripts.spectator")
local teams_gui    = require("gui.teams")

local M = {}

-- Refusal reasons, returned rather than printed so each caller phrases its own
-- feedback (one line in chat, a row in a bulk report).
M.GONE     = "gone"
M.FREED    = "freed"
M.RECYCLED = "recycled"

--- Verify the team still matches what the caller decided to disband.
--- `expected_generation` (optional) detects a slot recycled by a NEW team while
--- a confirm dialog or a queued bulk selection was pending.
function M.check(force_name, expected_generation)
    local force = force_name and game.forces[force_name]
    if not force or not force.valid then return false, M.GONE end

    local slot = helpers.team_slot(force_name)
    if not slot or (storage.team_pool or {})[slot] ~= "occupied" then
        return false, M.FREED
    end

    local current = (storage.team_slot_generation or {})[slot] or 0
    if expected_generation ~= nil and expected_generation ~= current then
        return false, M.RECYCLED
    end
    return true
end

--- Every player currently on the team, including anyone spectating away.
--- exit_all_for_force restores spectators onto their own force first, so
--- force.players is complete by the time it is read.
local function collect_members(force_name, force)
    spectator.exit_all_for_force(force_name)
    local members = {}
    for _, member in pairs(force.players) do members[#members + 1] = member end
    return members
end

--- Move one member off the team. Online members go back to the pen; offline
--- ones have their spawned flag cleared so they land there on reconnect.
local function evict(member, force_name, team_tag, opts)
    if spectator.is_spectating(member) then spectator.exit(member) end

    storage.left_teams = storage.left_teams or {}
    storage.left_teams[member.index] = storage.left_teams[member.index] or {}
    storage.left_teams[member.index][force_name] = true

    local spec_force = game.forces["spectator"]
    if spec_force then member.force = spec_force end

    if member.connected then
        landing_pen.return_to_pen(member)
        member.print(opts.inactive
            and {"mts-chat.team-disbanded-inactive"}
            or  {"mts-chat.team-disbanded-member", team_tag})
        return
    end

    storage.spawned_players = storage.spawned_players or {}
    storage.spawned_players[member.index] = nil

    -- Offline members can't be told now. Queue the notice for their next join;
    -- events/player_lifecycle.lua drains it.
    if opts.inactive then
        storage.reaper_notice = storage.reaper_notice or {}
        storage.reaper_notice[member.index] = true
    end
end

-- The same rule for anyone still on a slot when it is released, whatever
-- released it: control.lua hands this to team_slots.set_evict_hook.
M.evict = evict

--- Tear the team down. Returns (true, team_tag) or (false, reason).
--- opts.expected_generation - recycle guard (see M.check)
--- opts.silent              - suppress the per-team broadcast (bulk sends one
---                            summary instead of N separate lines)
--- opts.inactive            - members are told the team was deemed inactive,
---                            with no mention of how activity is measured
function M.teardown(force_name, opts)
    opts = opts or {}
    local ok, reason = M.check(force_name, opts.expected_generation)
    if not ok then return false, reason end

    local force    = game.forces[force_name]
    local team_tag = helpers.team_tag_with_leader(force_name)

    for _, member in ipairs(collect_members(force_name, force)) do
        evict(member, force_name, team_tag, opts)
    end

    force_utils.cleanup_force_surfaces(force_name)
    force_utils.release_team_slot(force_name)

    if not opts.silent then
        helpers.broadcast({"mts-chat.team-disbanded-broadcast", team_tag})
    end
    teams_gui.update_all()
    landing_pen.update_pen_gui_all()
    return true, team_tag
end

return M
