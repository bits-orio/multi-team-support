-- Multi-Team Support - compat/remote_safe.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- Dependency-free helper for calling another mod's remote interface defensively.
-- Knowing a mod is ACTIVE (script.active_mods) is NOT enough: the interface name
-- or a specific function can be renamed/removed between versions, and a bare
-- remote.call then hard-errors (often on every player spawn). Route such calls
-- through remote_safe.call so a missing interface/function degrades to nil.

local remote_safe = {}

--- remote.call(interface, fn, ...) only if the interface AND the function exist.
--- Returns the call result, or nil if the interface or function is absent.
function remote_safe.call(interface, fn, ...)
    local iface = remote.interfaces[interface]
    if not (iface and iface[fn]) then return nil end
    return remote.call(interface, fn, ...)
end

return remote_safe
