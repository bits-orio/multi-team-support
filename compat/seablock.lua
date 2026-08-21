-- Multi-Team Support - compat/seablock.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- Sea Block hands EVERY player a full bulk kit (2000 landfill, 1200 iron plate,
-- solar panels, ...) from its own on_player_created. Under MTS that means a
-- two-person team starts with two copies of it and races a solo team with double
-- the resources.
--
-- Sea Block's own single-player path already treats that kit as a once-per-map
-- thing -- it goes into a rock chest at the starting point instead of into an
-- inventory, and any one player can mine it. Marking those items team-scoped
-- here restores that intent for multiplayer rather than inventing a new rule.
--
-- The kit is read from Sea Block's public remote interface rather than
-- hardcoded: it varies with startup settings (wind turbines vs solar panels +
-- accumulators, the LandfillPainting landfill variant) and with which of Bob's
-- and Angel's mods are present.
--
-- Only what Sea Block itself hands out is claimed. Anything else in the captured
-- loadout -- a gun, ammo, armor, another mod's construction robots -- is left
-- player-scoped, so every member still spawns with their own personal kit.

local seablock = {}

-- Detection is by remote interface, not mod name -- see kit_item_names.
local INTERFACE_NAME = "SeaBlock"

-- Literal rather than starter_scope.TEAM: starter_scope requires this module, so
-- importing it back would close a require cycle. Keep in step with
-- scripts/starter_scope.lua.
local TEAM_SCOPE = "team"

--- Set of item names in Sea Block's starting kit, or nil when Sea Block is
--- absent or has not registered its interface yet. get_starting_items returns a
--- name -> count map.
local function kit_item_names()
    -- Gate on the INTERFACE, not on script.active_mods[MOD_NAME]. "SeaBlock" is
    -- the interface every Sea Block lineage registers (KiwiHawk's original and
    -- this fork alike), whereas the mod NAME differs per fork -- gating on the
    -- name would silently do nothing on a stack running any other one.
    local iface = remote.interfaces[INTERFACE_NAME]
    if not (iface and iface.get_starting_items) then return nil end

    local ok, kit = pcall(remote.call, INTERFACE_NAME, "get_starting_items")
    if not (ok and type(kit) == "table") then return nil end

    local names, any = {}, false
    for name, count in pairs(kit) do
        -- Sea Block keeps entries it has been told not to hand out at quantity 0
        -- (its own on_player_created skips those), so they are not part of the
        -- kit and must not be team-scoped.
        if type(count) == "number" and count > 0 then
            names[name] = true
            any = true
        end
    end
    if not any then return nil end
    return names
end

--- Mark every captured starter entry that Sea Block also hands out as
--- team-scoped. Idempotent, and on any stack without Sea Block it costs a single
--- remote.interfaces lookup and returns.
function seablock.mark_team_items(items)
    if type(items) ~= "table" then return end
    local names = kit_item_names()
    if not names then return end

    local marked = 0
    for _, item in pairs(items) do
        if names[item.name] and item.scope ~= TEAM_SCOPE then
            item.scope = TEAM_SCOPE
            marked = marked + 1
        end
    end
    if marked > 0 then
        log("[multi-team-support:seablock] marked " .. marked
            .. " starter item(s) team-scoped (Sea Block bulk kit)")
    end
end

return seablock
