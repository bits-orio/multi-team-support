-- Multi-Team Support - compat/gridlocked.lua
-- Author: bits-orio
-- License: MIT
--
-- Stopgap for the Gridlocked mod's HUD label. Gridlocked builds its
-- "Chunk points" label once at on_player_created against the player's
-- then-current force, and never rebuilds it. In MTS, players spawn on
-- the spectator force (landing pen), then move to a team force when
-- they claim a slot — at which point the HUD still shows the spectator
-- force's points and stays stale until something else triggers a
-- per-force refresh inside Gridlocked (typically a research finish).
--
-- The proper long-term fix is upstream: Gridlocked should hook
-- on_player_changed_force and rebuild the label. This module exists
-- only to bridge that gap. Delete it once the upstream fix lands.

local gridlocked = {}

--- True when Gridlocked is loaded in this save.
function gridlocked.is_active()
    return script.active_mods["gridlocked"] ~= nil
end

--- Refresh Gridlocked's HUD label for `player` to match the current
--- force's stored point count. Safe to call unconditionally — no-op
--- when Gridlocked isn't loaded, when the HUD frame doesn't exist
--- (player has gl-show-points disabled, frame already destroyed,
--- etc.), or when the force has no point entry.
function gridlocked.refresh_hud(player)
    if not gridlocked.is_active() then return end
    if not (player and player.valid) then return end

    local frame = player.gui.screen.gl_points
    if not (frame and frame.valid) then return end
    local flow = frame.flow
    if not (flow and flow.valid) then return end
    local label = flow.label
    if not (label and label.valid) then return end

    local pts = remote.call("gridlocked", "get_points", player.force.index)
    if pts then
        label.caption = "Chunk points: " .. pts
    end
end

return gridlocked
