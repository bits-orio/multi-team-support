-- Multi-Team Support - scripts/pause/state.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- Single source of truth for per-team paused state.
--
-- This module is the single read/write facade for storage.paused_forces,
-- shared by the mts-v1 pause API and the pause/* freeze modules, so the marker
-- is never poked from more than one shape of code.
--
-- Storage:
--   storage.paused_forces[force_name] = true | nil   -- nil means running

local pause_state = {}

function pause_state.init_storage()
    storage.paused_forces = storage.paused_forces or {}
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

return pause_state
