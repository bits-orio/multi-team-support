-- Multi-Team Support - data-final-fixes.lua
-- Author: bits-orio
-- License: MIT
--
-- Space Age integration: per-team planet variants and space connections.
-- Loaded at data-final-fixes so we see all base planets/connections from
-- any other mods.
--
-- When Space Age is not present, these files short-circuit (no planets to
-- deep-copy), and the mod falls back to the default surface-cloning behavior.

if not mods["space-age"] then return end

require("prototypes.planets")
require("prototypes.connections")
