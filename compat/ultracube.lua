-- Multi-Team Support - compat/ultracube.lua
-- Author: bits-orio
-- License: MIT
--
-- Compatibility with the Ultracube overhaul mod by grandseiken.
-- https://mods.factorio.com/mod/Ultracube
--
-- Architecture
-- ────────────
-- Ultracube normally initialises players (cube creation, starting armor) in
-- its on_player_created handler. In MTS, players are created before force
-- assignment completes: with the landing pen they arrive on the spectator
-- force, and even without it the force transition happens in the same tick
-- just after the event fires. Acting at on_player_created would therefore
-- place the starting cube on the wrong force.
--
-- Ultracube exposes two remote calls for this situation:
--   • disable_auto_player_setup() — suppresses its own on_player_created
--     handler so we can drive the timing ourselves.
--   • setup_player(player_index)  — runs the per-player setup (equip armor)
--     and the per-force first-time setup (place starting cube) for whatever
--     force the player is currently on.
--
-- We call disable_auto_player_setup() once during on_init. setup_player() is
-- called via after_spawn() at each spawn site, after the player has been
-- teleported onto their team surface. Calling it at on_player_joined_team
-- would be too early — the teleport is deferred and the player's surface
-- is still the landing pen at that point, which would place the cube there.
--
-- Force recycling
-- ───────────────
-- MTS recycles force slots when a team disbands: force.reset() is called
-- and the slot returns to the pool for a future team. Ultracube tracks
-- per-force state (cube_given, victory_state) keyed by force name. Without
-- cleanup, a recycled slot retains the old team's flags and the new team
-- never gets a starting cube or a chance to win.
--
-- We call reset_force(force_name) when on_team_released fires, which clears
-- those flags so the next team to claim the slot starts fresh.

local remote_api = require("scripts.remote_api")

local ultracube = {}

function ultracube.is_active()
    return script.active_mods["Ultracube"] ~= nil
end

-- Called from on_init and on_configuration_changed.
function ultracube.on_init()
    if not ultracube.is_active() then return end
    if not (remote.interfaces["Ultracube"] and
            remote.interfaces["Ultracube"]["disable_auto_player_setup"]) then
        return
    end
    remote.call("Ultracube", "disable_auto_player_setup")
end

-- Called at every spawn site immediately after the player has been
-- teleported onto their team surface. At this point player.surface is
-- the correct team surface, so Ultracube will place the starting cube
-- there rather than on the landing pen or whatever intermediate surface
-- the player was on when force assignment happened.
function ultracube.after_spawn(player)
    if not ultracube.is_active() then return end
    if not (remote.interfaces["Ultracube"] and
            remote.interfaces["Ultracube"]["setup_player"]) then
        return
    end
    remote.call("Ultracube", "setup_player", player.index)
end

-- Called from init_events().
function ultracube.register_events()
    if not ultracube.is_active() then return end
    if not remote.interfaces["Ultracube"] then return end

    -- on_player_joined_team fires during force assignment, before the
    -- player has been teleported to their team surface. setup_player is
    -- therefore NOT called here — it is called explicitly at each spawn
    -- site via after_spawn() once the teleport has completed.

    script.on_event(remote_api.events.on_team_released, function(e)
        -- The force slot is being recycled. Clear Ultracube's per-force flags
        -- so the next team to claim this slot gets a fresh starting cube and
        -- an unblocked victory condition.
        if remote.interfaces["Ultracube"]["reset_force"] then
            remote.call("Ultracube", "reset_force", e.force_name)
        end
    end)
end

return ultracube
