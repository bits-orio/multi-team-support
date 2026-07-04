-- Multi-Team Support - prototypes/compat/belt_ban.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- Data-stage compat shim for the "belt-ban" mod (No Belts - Challenge Mode).
--
-- belt-ban disables the logistics / logistics-2 / logistics-3 technologies
-- (enabled = false) to strip out every transport belt. A disabled prerequisite
-- can never be satisfied, so that permanently orphans three important NON-belt
-- technologies that list logistics-2 as a prerequisite:
--
--   * automobilism   (car)
--   * bulk-inserter  (bulk inserter + capacity bonus)
--   * railway        (rails, locomotive, wagons)
--
-- We remove "logistics-2" from those three techs' prerequisites so they
-- reconnect to the tree through their OTHER prerequisites (engine /
-- fast-inserter / advanced-circuit), all of which stay researchable. Belts
-- themselves remain banned: we never touch logistics-2's own enabled flag.
--
-- Order relative to belt-ban does not matter -- belt-ban never edits these
-- three techs' prerequisites, so stripping logistics-2 here is independent of
-- whichever mod's data-final-fixes runs first.

-- tech name -> prerequisite to strip
local STRIP = {
    ["automobilism"]  = "logistics-2",
    ["bulk-inserter"] = "logistics-2",
    ["railway"]       = "logistics-2",
}

--- Remove `prereq` from `tech`'s prerequisites, if both exist.
local function strip_prerequisite(tech_name, prereq)
    local tech = data.raw.technology[tech_name]
    if not tech or not tech.prerequisites then return end
    for i = #tech.prerequisites, 1, -1 do
        if tech.prerequisites[i] == prereq then
            table.remove(tech.prerequisites, i)
        end
    end
end

for tech_name, prereq in pairs(STRIP) do
    strip_prerequisite(tech_name, prereq)
end
