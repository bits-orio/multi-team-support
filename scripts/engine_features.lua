-- Multi-Team Support - scripts/engine_features.lua
-- Author: bits-orio
-- License: MIT
--
-- What the running game can do beyond the version info.json asks for. Each
-- flag is worked out once, when control.lua is parsed, and every write of a
-- newer property goes through a function here, so the mod keeps loading on
-- the older game.
--
-- Measured: on a game before 2.1.25 reading LuaGuiElement.opacity gives nil
-- and writing it throws, so the version is the test, never a read.

local M = {}

local function at_least(version)
    return helpers.compare_versions(script.active_mods.base, version) >= 0
end

--- Sprites and sprite buttons can be faded (LuaGuiElement.opacity, 2.1.25).
M.GUI_OPACITY = at_least("2.1.25")

--- A surface's pollutant can be overridden (LuaSurface.override_pollution_type:
--- added in 2.1.7, desyncs before 2.1.12).
M.POLLUTANT_OVERRIDE = at_least("2.1.12")

--- Fade the icon of a sprite or sprite button: 1 is solid, 0.5 looks like
--- the game's own ghost items. Only the icon fades; a button's frame and
--- number stay solid. Does nothing on a game without the property.
function M.set_opacity(element, opacity)
    if M.GUI_OPACITY then element.opacity = opacity end
end

return M
