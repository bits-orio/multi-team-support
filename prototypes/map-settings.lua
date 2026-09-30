-- New-map enemy defaults for a multi-team race: biters stay where the map put
-- them, and evolution moves only with pollution and nest kills, not the clock.
--
-- The map-settings prototype is what the Map generator screen starts from, so
-- a host can still tick either back on there for one map. Presets that carry
-- their own values (Death world, Rail world) keep them when picked. Existing
-- saves are untouched: map settings live in the save, and this prototype only
-- seeds new maps.
--
-- Runs at data.lua, the earliest stage, so a mod that deliberately tunes
-- enemies (in its own data-updates or final-fixes) still wins.

local map = data.raw["map-settings"]["map-settings"]
map.enemy_expansion.enabled     = false
map.enemy_evolution.time_factor = 0
