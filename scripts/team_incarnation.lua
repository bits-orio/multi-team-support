-- Multi-Team Support - scripts/team_incarnation.lua
-- Author: bits-orio
-- License: MIT
--
-- Which team holds a slot now. MTS recycles slots: once team-4 is released,
-- the next team to claim a slot can be team-4 again, other people under the
-- same force name. Anything that must keep one team's things from the next
-- team in its slot keys them by incarnation, not by force name.
--
-- The one reader is the AI Agent Bridge chat scope (chat_scope_v1 in
-- remote_api.lua). The bridge keeps chat history longer than a team lasts,
-- and longer than a map, so a private key that was only the force name
-- would let the next team in the slot read this team's private chat.
--
-- Storage:
--   storage.team_claimed_tick[force_name] = { tick = n, generation = g }
--       The tick the current team claimed the slot, and the slot's
--       generation then. Written by team_slots.claim_team_slot, cleared by
--       team_slots.release_team_slot.
--   An entry made on an update for a team that claimed its slot before this
--   table existed also has legacy = true, and its tick is the update's.
--
-- An entry counts only while its generation is the slot's current one.
-- release_team_slot has bumped the generation on every release since
-- 0.4.61, in versions that never kept this table as well. So an entry a
-- downgrade left behind for a team that has since gone is never read for
-- the team after it.

local helpers = require("scripts.helpers")

local M = {}

--- The slot's generation now. Unset reads 0, as release_team_slot reads it.
local function generation(force_name)
    local slot = helpers.team_slot(force_name)
    return slot and (storage.team_slot_generation or {})[slot] or 0
end

local function is_occupied(force_name)
    local slot = helpers.team_slot(force_name)
    return slot ~= nil and (storage.team_pool or {})[slot] == "occupied"
end

--- The entry of the team holding the slot now, or nil. One from an older
--- generation names a team that has left. A bare tick, from a build before
--- generations were kept, cannot say which team it names, so it fails closed.
local function current(force_name)
    local entry = (storage.team_claimed_tick or {})[force_name]
    if type(entry) ~= "table" or entry.generation ~= generation(force_name) then return nil end
    return entry
end

--- Called from on_init, and lazily on a claim, because a dev build reloaded
--- without a version change never runs on_configuration_changed.
function M.init_storage()
    storage.team_claimed_tick = storage.team_claimed_tick or {}
end

--- A new team in the slot. The tick is the claim's, never the clock's: under
--- Staged Start the clock waits for Start Playing, but the team is already
--- there and already chatting.
function M.on_claim(force_name)
    M.init_storage()
    storage.team_claimed_tick[force_name] = { tick = game.tick, generation = generation(force_name) }
end

--- The team is gone from the slot.
function M.on_release(force_name)
    if storage.team_claimed_tick then storage.team_claimed_tick[force_name] = nil end
end

--- On an update. Drops every entry that no longer names the team in its
--- slot, then gives each claimed slot left without one a legacy entry for
--- this save at this tick. A constant would not do: two saves of one map,
--- each with a different team in the slot from before claims were recorded,
--- would share a key, and the bridge keeps one history across every save of
--- a map.
function M.on_configuration_changed()
    M.init_storage()
    local entries = storage.team_claimed_tick
    for force_name in pairs(entries) do
        if not (current(force_name) and is_occupied(force_name)) then entries[force_name] = nil end
    end
    for slot, status in pairs(storage.team_pool or {}) do
        local force_name = "team-" .. slot
        if status == "occupied" and not entries[force_name] then
            entries[force_name] = { tick = game.tick, generation = generation(force_name), legacy = true }
        end
    end
end

--- The current team's incarnation: the tick it claimed the slot, "81234";
--- "legacy-g2-t90000" for one that held its slot when the save updated (its
--- slot's generation, and the update's tick); or "legacy-g2" for a claimed
--- slot with no entry that counts, which only a dev build reloaded without
--- a version change can see: every update gives such a slot an entry.
function M.of(force_name)
    local entry = current(force_name)
    if not entry then return string.format("legacy-g%d", generation(force_name)) end
    if entry.legacy then return string.format("legacy-g%d-t%d", entry.generation, entry.tick) end
    return tostring(entry.tick)
end

--- A key no earlier or later team in the same slot shares: "team-4@81234",
--- or "team-4@legacy-g2-t90000" for the team that held the slot when the
--- save updated.
function M.key(force_name)
    return force_name .. "@" .. M.of(force_name)
end

return M
