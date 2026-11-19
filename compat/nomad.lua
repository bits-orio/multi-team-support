-- Multi-Team Support - compat/nomad.lua
-- Author: bits-orio
-- License: MIT
--
-- Compatibility with Nomad by holunder.
-- https://mods.factorio.com/mod/nomad
--
-- Nomad starts the game on a mothership in orbit instead of on the ground:
-- research only works in space, and planets are for mining. Under MTS every
-- team gets its own mothership above its own Nauvis.
--
-- Nomad puts a new player on the ship of whatever force they have one tick
-- after on_player_created. In MTS that is too early: the player is still in
-- the landing pen on the spectator force, so the ship would belong to the
-- wrong force. Nomad exposes remote calls for a mod that runs several forces:
--
--   • disable_auto_player_setup() — Nomad stops acting on on_player_created.
--   • setup_player(player_index)  — the player goes to their force's ship. A
--     force without a ship gets one above the planet the player stands on.
--   • reset_force(force_name)     — forget the force's ship and its progress.
--   • set_surface_planet(...)     — which planet a team surface stands for, so
--     deposits generate there. MTS calls that one on every mod that has it
--     (compat/surface_planet.lua); nothing to do here.
--
-- We call disable_auto_player_setup() from on_init and
-- on_configuration_changed, and setup_player() from after_spawn(), once the
-- player stands on the team's Nauvis: that is the planet the new ship then
-- orbits. A later member of the team joins the ship that is already there.
--
-- Force recycling
-- ───────────────
-- A released team's platforms are destroyed with its surfaces
-- (team_slots.cleanup_force_surfaces). reset_force() on on_team_released
-- clears what Nomad remembers per force (ship, achievements, "Nomad achieved")
-- so the next team in the slot starts over.
--
-- A Nomad release without these remote calls is left alone: remote_safe.call
-- skips a function that is not there.

local remote_safe = require("compat.remote_safe")

local nomad = {}

local INTERFACE = "nomad"

function nomad.is_active()
    return script.active_mods["nomad"] ~= nil
end

--- Called from on_init and on_configuration_changed. MTS loads before Nomad,
--- so on a new game this runs before Nomad's own on_init, which keeps the flag.
function nomad.on_init()
    if not nomad.is_active() then return end
    remote_safe.call(INTERFACE, "disable_auto_player_setup")
end

--- Called at every spawn site right after the player has been teleported onto
--- their team surface.
function nomad.after_spawn(player)
    if not nomad.is_active() then return end
    remote_safe.call(INTERFACE, "setup_player", player.index)
end

--- Fanned out from the single MTS-owned on_team_released dispatcher in
--- events/ticks.lua.
function nomad.on_team_released(e)
    if not nomad.is_active() then return end
    remote_safe.call(INTERFACE, "reset_force", e.force_name)
end

return nomad
