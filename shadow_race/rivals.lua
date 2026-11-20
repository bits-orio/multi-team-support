-- Multi-Team Support - shadow_race/rivals.lua
-- Author: bits-orio
-- License: MIT
--
-- Which shadow a team is chasing, and how far ahead or behind it is.
--
-- The rival belongs to the team: any member sets it and it changes for
-- every member. What a player carries from one team to the next is their
-- pin (shadow_race/archive.lua) and the last rival their team had.
--
-- Storage:
--   storage.shadow_race.rival[force_name] = choice
--   storage.shadow_race.pref[player_index] = { last = choice, hidden = true, splits_open = true }
--   storage.shadow_race.last_shadow[force_name] = choice
--       the run the team's splits were last shown against. It outlives
--       an auto-chase that has passed every run, so the splits window
--       keeps something to show.
--   choice = { kind = "run",  id = n }                  an archived run
--          | { kind = "team", force = "team-4", start = tick }
--                a team playing now; `start` tells it from the next team in
--                the same slot
--          | { kind = "auto", target = choice or nil }
--                auto-chase: always the nearest run ahead. The target is
--                picked by shadow_race/standings.lua; nil means the team
--                leads every run there is.
--
-- Flags (scripts/admin_flags.lua): shadow_race_enabled shows or hides the
-- whole race; shadow_race_individual_hud lets a player hide their own HUD.

local recorder    = require("shadow_race.recorder")
local archive     = require("shadow_race.archive")
local compare     = require("shadow_race.compare")
local admin_flags = require("scripts.admin_flags")
local helpers     = require("scripts.helpers")

local M = {}

local function state()
    local s = recorder.init_storage()
    s.rival = s.rival or {}
    s.pref  = s.pref  or {}
    s.last_shadow = s.last_shadow or {}
    return s
end

local function pref_of(s, player_index)
    local pref = s.pref[player_index]
    if not pref then
        pref = {}
        s.pref[player_index] = pref
    end
    return pref
end

function M.enabled()
    return admin_flags.flag("shadow_race_enabled") == true
end

function M.individual_hud()
    return admin_flags.flag("shadow_race_individual_hud") == true
end

-- ─── Resolving a choice ───────────────────────────────────────────────

--- The run a choice names, and whether it is being played now. nil when
--- the run is gone: deleted by retention, or a team that has since left.
--- Auto-chase names its target of the moment.
local function run_of(s, choice)
    if choice.kind == "auto" then
        if not choice.target then return nil end
        return run_of(s, choice.target)
    end
    if choice.kind == "run" then return s.runs[choice.id], false end
    local run = s.live[choice.force]
    if run and run.start == choice.start then return run, true end
    return nil
end

--- Whether two choices name the same run.
function M.same(a, b)
    return a ~= nil and b ~= nil and a.kind == b.kind and a.id == b.id
        and a.force == b.force and a.start == b.start
end

--- The run a choice names: run, live; or nil.
function M.run_of_choice(choice)
    return run_of(state(), choice)
end

--- The team's stored choice, or nil.
function M.choice_of(force_name)
    return state().rival[force_name]
end

function M.is_auto(force_name)
    local choice = state().rival[force_name]
    return choice ~= nil and choice.kind == "auto"
end

--- What to call a run: the team's name while it plays; once archived,
--- "<leader>'s run (2h 41m)". The length tells one leader's runs apart.
function M.label(run, live)
    if live then return helpers.team_tag(run.force) end
    local leader = run.leader or run.label or "?"
    if run.leader_color then leader = helpers.colored_name(leader, run.leader_color) end
    return {"mts-gui.shadow-run-of", leader, helpers.ls_duration_coarse(run.ended or 0)}
end

--- Print to the team's connected members. Race news skips a member who
--- hid their own display; `everyone` is for what changes the team's state.
function M.tell(force_name, message, everyone)
    local force = game.forces[force_name]
    if not force then return end
    for _, member in pairs(force.players) do
        if member.connected and (everyone or not M.is_hidden(member.index)) then member.print(message) end
    end
end

--- The team's rival: run, live; or nil. A rival that no longer exists is
--- cleared here, so nothing downstream sees a dangling choice.
function M.rival_of(force_name)
    local s = state()
    local choice = s.rival[force_name]
    if not choice then return nil end
    local run, live = run_of(s, choice)
    if not run then
        -- Auto-chase outlives its target: the next retarget finds another.
        if choice.kind == "auto" then choice.target = nil else s.rival[force_name] = nil end
        return nil
    end
    s.last_shadow[force_name] = choice.kind == "auto" and choice.target or choice
    return run, live
end

--- The run the team's splits are shown against: its shadow, or else the
--- last one it had (auto-chase that has passed every run has no shadow of
--- the moment). run, live; or nil for a team that never chased anything.
function M.shown_of(force_name)
    local run, live = M.rival_of(force_name)
    if run then return run, live end
    local s = state()
    local last = s.last_shadow[force_name]
    if not last then return nil end
    return run_of(s, last)
end

-- ─── The gap ──────────────────────────────────────────────────────────

--- Where the team stands against its shadow, or nil when it is chasing
--- nothing: { gap, final, label, auto }.
---   gap, final  see compare.gap; gap is nil with nothing to compare yet
---   label       the shadow's name; nil under auto-chase when the team is
---               ahead of every run there is
function M.standing(force_name)
    local mine = recorder.run_of(force_name)
    if not (mine and state().rival[force_name]) then return nil end
    local auto = M.is_auto(force_name)
    local rival, live = M.rival_of(force_name)
    if not rival then return auto and { auto = true } or nil end
    local gap, final = compare.gap(mine, rival, live)
    return { gap = gap, final = final, label = M.label(rival, live), auto = auto }
end

-- ─── Choosing ─────────────────────────────────────────────────────────

function M.members_of(force_name)
    local run = recorder.run_of(force_name)
    local list = {}
    local force = game.forces[force_name]
    if not (run and force) then return list end
    for _, player in pairs(force.players) do list[#list + 1] = player end
    return list
end

--- Set the team's rival. Returns false for a choice that names nothing, or
--- the team itself.
function M.set(force_name, choice)
    local s = state()
    local mine = s.live[force_name]
    if not mine then return false end
    local stored
    if choice.kind == "auto" then
        stored = { kind = "auto" }
    else
        local run = run_of(s, choice)
        if not run or run == mine then return false end
        stored = { kind = choice.kind, id = choice.id, force = choice.force, start = choice.start }
    end
    s.rival[force_name] = stored
    -- What the members carry to their next team: the choice, never the
    -- auto-chase target of the moment.
    local carried = { kind = stored.kind, id = stored.id, force = stored.force, start = stored.start }
    for _, member in ipairs(M.members_of(force_name)) do
        pref_of(s, member.index).last = carried
    end
    return true
end

function M.clear(force_name)
    local s = state()
    s.rival[force_name] = nil
    s.last_shadow[force_name] = nil
    for _, member in ipairs(M.members_of(force_name)) do
        pref_of(s, member.index).last = nil
    end
end

--- A new run: it starts chasing its leader's pinned run, or else whatever
--- the leader's last team chased.
function M.on_run_opened(force_name)
    local s = state()
    local leader = (storage.team_leader or {})[force_name]
    if not leader then return end
    local kept = s.kept[leader]
    if kept and kept.pinned and M.set(force_name, { kind = "run", id = kept.pinned }) then return end
    local last = (s.pref[leader] or {}).last
    if last then M.set(force_name, last) end
end

--- A team's run was archived as run `id`, or dropped (id nil). Teams that
--- were chasing it live now chase the archived run.
function M.on_run_closed(force_name, start, id)
    local s = state()
    s.rival[force_name] = nil
    s.last_shadow[force_name] = nil
    local function moved(choice)
        if not (choice and choice.kind == "team" and choice.force == force_name
                and choice.start == start) then return choice end
        return id and { kind = "run", id = id } or nil
    end
    for chaser, choice in pairs(s.rival) do
        if choice.kind == "auto" then
            choice.target = moved(choice.target)
        else
            s.rival[chaser] = moved(choice)
        end
    end
    for _, pref in pairs(s.pref) do pref.last = moved(pref.last) end
    for chaser, choice in pairs(s.last_shadow) do s.last_shadow[chaser] = moved(choice) end
end

function M.forget_player(player_index)
    local s = storage.shadow_race
    if s and s.pref then s.pref[player_index] = nil end
end

-- ─── The player's own HUD ─────────────────────────────────────────────

function M.is_hidden(player_index)
    local s = state()
    return M.individual_hud() and (s.pref[player_index] or {}).hidden == true
end

function M.set_hidden(player_index, hidden)
    pref_of(state(), player_index).hidden = hidden and true or nil
end

--- Whether the player keeps the splits window open. It is closed until
--- they open it from the Shadow Race window, and their choice holds from
--- then on.
function M.wants_splits(player_index)
    return (state().pref[player_index] or {}).splits_open == true
end

function M.set_splits(player_index, wanted)
    pref_of(state(), player_index).splits_open = wanted and true or nil
end

M.pin   = archive.pin
M.unpin = archive.unpin

return M
