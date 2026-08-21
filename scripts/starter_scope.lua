-- Multi-Team Support - scripts/starter_scope.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- Per-item scope for the starter-items list.
--
--   player  every member who spawns gets their own copy
--   team    granted ONCE, to whichever member of a team spawns first
--
-- Why this exists: the pen grant runs per player, so a two-person team used to
-- receive two full copies of the map's starting kit and raced a solo team with
-- double the resources. Personal equipment (armor, gun, a mod's construction
-- robots) is meant to be per-player; bulk resources are not. Scope lives on each
-- entry, so the split is data an admin can edit rather than a hardcoded list.
--
-- Absent scope reads as "player", so saves written before this existed -- and
-- rows an admin adds by hand -- keep the previous behaviour until someone says
-- otherwise.
--
-- Storage:
--   storage.team_kit_granted[force_name] = true  -- team already took its one kit

local seablock = require("compat.seablock")

local starter_scope = {}

starter_scope.TEAM   = "team"
starter_scope.PLAYER = "player"

function starter_scope.init_storage()
    storage.team_kit_granted = storage.team_kit_granted or {}
end

--- True when this entry is granted once per team rather than per player.
function starter_scope.is_team(item)
    return item ~= nil and item.scope == starter_scope.TEAM
end

--- Normalised scope of an entry: anything that isn't TEAM is player-scoped.
function starter_scope.of(item)
    return starter_scope.is_team(item) and starter_scope.TEAM or starter_scope.PLAYER
end

--- Flip one entry between the two scopes. Player scope is stored as nil rather
--- than the string so the common case adds nothing to the save.
function starter_scope.toggle(item)
    if not item then return starter_scope.PLAYER end
    item.scope = starter_scope.is_team(item) and nil or starter_scope.TEAM
    return starter_scope.of(item)
end

-- ─── Per-team ledger ──────────────────────────────────────────────────

function starter_scope.team_has_kit(force_name)
    starter_scope.init_storage()
    return storage.team_kit_granted[force_name] == true
end

function starter_scope.mark_team_kit(force_name)
    starter_scope.init_storage()
    storage.team_kit_granted[force_name] = true
end

--- Forget that a team took its kit. Called from team_slots.wipe_slot_state, so a
--- recycled team-N slot hands the next team to occupy it their own copy instead
--- of inheriting the previous occupant's "already paid" mark.
function starter_scope.clear_team_kit(force_name)
    if storage.team_kit_granted then
        storage.team_kit_granted[force_name] = nil
    end
end

-- ─── Defaults ─────────────────────────────────────────────────────────

--- Seed scopes on a freshly captured list. A compat module that knows which of
--- its mod's items are bulk map resources claims them here; whatever no module
--- claims stays player-scoped.
---
--- Only ever called where the list is being (re)built from a character -- the
--- auto-capture and the admin's "copy from my inventory" -- so it never fights an
--- admin's per-row edits, which are made against an already-seeded list.
function starter_scope.seed_defaults(items)
    if type(items) ~= "table" then return end
    seablock.mark_team_items(items)
end

return starter_scope
