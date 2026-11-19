-- Multi-Team Support - compat/surface_planet.lua
-- Author: bits-orio
-- License: MIT
--
-- Tells other mods which planet a team surface stands for.
--
-- Some terrain mods keep per-planet settings and state, keyed by the planet's
-- name (cell size per planet, a palette per planet, and so on). A team surface
-- is named "mts-<planet>-<N>" or "team-<N>-<planet>", so those mods do not
-- recognise it. Rather than have each of them learn MTS's names, MTS calls a
-- function they expose under a shared name:
--
--   set_surface_planet(surface_index, planet_name)
--
-- on ANY remote interface that has it. The mod on the other side never hears
-- of MTS, and another team mod can make the same call. No list of mods lives
-- here: a mod opts in by exposing the function.
--
-- Called once per team surface, from on_surface_created, which runs before the
-- surface's first chunk generates. Called again for every team surface from
-- on_configuration_changed, so a mod added to a running save learns about the
-- surfaces that already exist.

local surface_utils = require("scripts.surface_utils")

local surface_planet = {}

local FN = "set_surface_planet"

--- Tell every mod that exposes set_surface_planet which planet this surface
--- stands for. No-op for a surface that is not a team variant.
function surface_planet.announce(surface)
    if not (surface and surface.valid) then return end
    local planet = surface_utils.variant_base_planet(surface.name)
    if not planet then return end
    for interface, functions in pairs(remote.interfaces) do
        if functions[FN] then
            -- pcall: a foreign function that rejects the call must not take
            -- surface creation down with it.
            local ok, err = pcall(remote.call, interface, FN, surface.index, planet)
            if not ok then
                log("[multi-team-support] " .. interface .. "." .. FN
                    .. " failed for " .. surface.name .. ": " .. tostring(err))
            end
        end
    end
end

--- Announce every existing team surface (on_configuration_changed).
function surface_planet.announce_all()
    for _, surface in pairs(game.surfaces) do
        surface_planet.announce(surface)
    end
end

return surface_planet
