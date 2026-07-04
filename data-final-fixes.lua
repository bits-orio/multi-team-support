-- Multi-Team Support - data-final-fixes.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- Space Age integration: per-team planet variants and space connections.
-- Loaded at data-final-fixes so we see all base planets/connections from
-- any other mods.
--
-- When Space Age is not present, these files short-circuit (no planets to
-- deep-copy), and the mod falls back to the default surface-cloning behavior.

-- belt-ban compat: reconnect the non-belt techs (automobilism, bulk-inserter,
-- railway) that belt-ban orphans by disabling logistics-2. Independent of
-- Space Age, so it runs before the space-age guard below.
if mods["belt-ban"] then
    require("prototypes.compat.belt_ban")
end

if not mods["space-age"] then return end

require("prototypes.planets")
require("prototypes.connections")
