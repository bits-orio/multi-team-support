-- Multi-Team Support - scripts/pause/state.lua
-- Author: bits-orio
-- License: MIT
--
-- Single source of truth for per-team paused state.
--
-- This module is the single read/write facade for storage.paused_forces,
-- shared by the mts-v1 pause API and the pause/* freeze modules, so the marker
-- is never poked from more than one shape of code.
--
-- Storage:
--   storage.paused_forces[force_name] = true | nil   -- nil means running
--   storage.pause_holders[force_name] = { [holder] = true }
--       who holds the pause ("admin", "script" or a consumer's own name); the
--       team thaws when the last holder lets go

local pause_state = {}

function pause_state.init_storage()
    storage.paused_forces = storage.paused_forces or {}
    storage.pause_holders = storage.pause_holders or {}
    -- Saves from before holders: a paused team was held by whoever paused it.
    for force_name in pairs(storage.paused_forces) do
        storage.pause_holders[force_name] = storage.pause_holders[force_name] or { script = true }
    end
end

--- Is this team currently marked paused?
function pause_state.is_paused(force_name)
    return (storage.paused_forces or {})[force_name] and true or false
end

--- Mark a team paused (paused=true) or running (paused=false). Stored as
--- true|nil so a running team leaves no entry, keeping the table sparse.
function pause_state.set_paused(force_name, paused)
    storage.paused_forces = storage.paused_forces or {}
    storage.paused_forces[force_name] = paused and true or nil
end

--- Add a holder to a team's pause.
function pause_state.add_holder(force_name, holder)
    storage.pause_holders = storage.pause_holders or {}
    storage.pause_holders[force_name] = storage.pause_holders[force_name] or {}
    storage.pause_holders[force_name][holder] = true
end

--- Remove one holder, or every holder when holder is nil. Returns true when no
--- holder is left.
function pause_state.release_holder(force_name, holder)
    local held = (storage.pause_holders or {})[force_name]
    if held and holder then held[holder] = nil end
    if holder and held and next(held) then return false end
    if storage.pause_holders then storage.pause_holders[force_name] = nil end
    return true
end

--- The holders of a team's pause, as a list of names.
function pause_state.holders(force_name)
    local out = {}
    for holder in pairs((storage.pause_holders or {})[force_name] or {}) do out[#out + 1] = holder end
    table.sort(out)
    return out
end

return pause_state
