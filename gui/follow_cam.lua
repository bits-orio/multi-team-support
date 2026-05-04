-- Multi-Team Support - gui/follow_cam.lua
-- Author: bits-orio
-- License: MIT
--
-- Follow Cam: a grid of live camera widgets that track individual players.
-- Players are added/removed one at a time from the "Follow Cam" buttons in
-- each team card (except the viewer's own player). Works across teams.
--
-- Camera widgets render client-side (GPU), so the server cost is just
-- the per-tick property assignments. Updates happen via on_nth_tick(2)
-- (30 FPS) to halve server cost with no visible difference.
--
-- Storage shape:
--   storage.follow_cam[viewer_index] = {
--     targets     = {[target_index] = true, ...},  -- player indices to track
--     cameras     = {[target_index] = LuaGuiElement, ...},  -- rebuilt on changes
--     zoom_levels = {[target_index] = number, ...},  -- per-camera zoom, survives rebuilds
--   }

local helpers   = require("scripts.helpers")
local spectator = require("scripts.spectator")

local follow_cam = {}

-- ─── Constants ────────────────────────────────────────────────────────

local FRAME_NAME    = "sb_follow_cam_frame"
local CAMERA_WIDTH  = 320
local CAMERA_HEIGHT = 200
local CAMERA_ZOOM   = 0.5
-- Tile radius we chart around the tracked player each tick so the camera
-- widget always has chart data to render (otherwise non-friend viewers see
-- a black cell). Generous enough to cover the widest zoom-out.
local CHART_RADIUS  = 200
-- Default is also the max: zooming in any closer gives an uncomfortably
-- tight view, so the + button only restores zoom after a zoom-out.
local CAMERA_ZOOM_MIN  = 0.05
local CAMERA_ZOOM_MAX  = 0.75
local CAMERA_ZOOM_STEP = 1.25

-- ─── Storage ──────────────────────────────────────────────────────────

local function get_state(viewer_index)
    storage.follow_cam = storage.follow_cam or {}
    return storage.follow_cam[viewer_index]
end

local function clear_state(viewer_index)
    if storage.follow_cam then storage.follow_cam[viewer_index] = nil end
end

--- Ensure state exists for a viewer.
local function ensure_state(viewer_index)
    storage.follow_cam = storage.follow_cam or {}
    if not storage.follow_cam[viewer_index] then
        storage.follow_cam[viewer_index] = {targets = {}, cameras = {}, zoom_levels = {}}
    end
    storage.follow_cam[viewer_index].zoom_levels =
        storage.follow_cam[viewer_index].zoom_levels or {}
    return storage.follow_cam[viewer_index]
end

-- ─── GUI Helpers ──────────────────────────────────────────────────────

--- Pick a sensible column count based on number of cameras.
local function choose_columns(n)
    if n <= 1 then return 1 end
    if n <= 4 then return 2 end
    return 3
end

--- Resolve an ordered list of currently-online target players.
--- Sorted alphabetically for stable grid ordering.
local function resolve_targets(target_set)
    local list = {}
    for idx in pairs(target_set) do
        local p = game.get_player(idx)
        if p and p.valid and p.connected then
            list[#list + 1] = p
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- ─── GUI Building ─────────────────────────────────────────────────────

--- Build (or rebuild) the follow cam frame based on current targets.
--- If there are no online targets, closes the frame.
local function rebuild_frame(viewer, state)
    if not (viewer and viewer.valid and viewer.connected) then return end

    local targets = resolve_targets(state.targets)

    -- No targets → close the frame, clear state
    if #targets == 0 then
        if viewer.gui.screen[FRAME_NAME] then
            viewer.gui.screen[FRAME_NAME].destroy()
        end
        state.cameras     = {}
        state.targets     = {}
        state.zoom_levels = {}
        return
    end

    -- Destroy existing frame to release camera refs cleanly, then rebuild
    if viewer.gui.screen[FRAME_NAME] then
        storage.follow_cam_location = storage.follow_cam_location or {}
        storage.follow_cam_location[viewer.index] = viewer.gui.screen[FRAME_NAME].location
        viewer.gui.screen[FRAME_NAME].destroy()
    end

    storage.follow_cam_location = storage.follow_cam_location or {}
    local frame = helpers.reuse_or_create_frame(
        viewer, FRAME_NAME, storage.follow_cam_location, {x = 300, y = 120})

    -- Title bar with close button
    local title_bar = helpers.add_title_bar(frame, "Follow Cam")
    title_bar.add{
        type    = "sprite-button",
        name    = "sb_follow_cam_close",
        sprite  = "utility/close",
        style   = "close_button",
        tooltip = "Close Follow Cam",
    }

    -- Camera grid
    local cols = choose_columns(#targets)
    local grid = frame.add{
        type         = "table",
        column_count = cols,
    }
    grid.style.horizontal_spacing = 6
    grid.style.vertical_spacing   = 6

    local camera_refs = {}
    for _, target in ipairs(targets) do
        local cell = grid.add{type = "flow", direction = "vertical"}
        cell.style.vertical_spacing = 2

        -- Player name + team tag + "expand to spectator" button.
        -- (To stop following, click the radar icon again in the Teams panel.)
        local name_row = cell.add{type = "flow", direction = "horizontal"}
        name_row.style.vertical_align           = "center"
        name_row.style.horizontally_stretchable = true

        local name_lbl = name_row.add{type = "label", caption = target.name}
        name_lbl.style.font       = "default-bold"
        name_lbl.style.font_color = target.chat_color

        local team_lbl = name_row.add{
            type    = "label",
            caption = "  " .. helpers.display_name(target.force.name),
        }
        team_lbl.style.font       = "default-small"
        team_lbl.style.font_color = helpers.force_color(target.force)

        local spacer = name_row.add{type = "empty-widget"}
        spacer.style.horizontally_stretchable = true

        -- Expand-to-spectator: opens the full-screen remote view. The follow
        -- cam frame stays intact underneath, so pressing Esc returns the
        -- player here with the camera grid exactly as it was.
        name_row.add{
            type    = "sprite-button",
            sprite  = "utility/search_icon",
            style   = "mini_button",
            tags    = {sb_follow_cam_spectate = true, target_idx = target.index},
            tooltip = "Expand to full spectator view (Esc to return here)",
        }

        -- Per-camera zoom controls (− / +).
        local zoom_out = name_row.add{
            type    = "button",
            caption = "−",
            tags    = {sb_follow_cam_zoom_out = true, target_idx = target.index},
            tooltip = "Zoom out",
        }
        zoom_out.style.width   = 22
        zoom_out.style.height  = 22
        zoom_out.style.padding = 0
        zoom_out.style.font    = "default-bold"

        local zoom_in = name_row.add{
            type    = "button",
            caption = "+",
            tags    = {sb_follow_cam_zoom_in = true, target_idx = target.index},
            tooltip = "Zoom in",
        }
        zoom_in.style.width   = 22
        zoom_in.style.height  = 22
        zoom_in.style.padding = 0
        zoom_in.style.font    = "default-bold"

        -- Per-camera close: removes just this target from the grid.
        name_row.add{
            type    = "sprite-button",
            sprite  = "utility/close",
            style   = "mini_button",
            tags    = {sb_follow_cam_remove = true, target_idx = target.index},
            tooltip = "Remove from Follow Cam",
        }

        -- Camera widget inside a deep frame for a nice border.
        local zoom = state.zoom_levels[target.index] or CAMERA_ZOOM
        local cam_frame = cell.add{type = "frame", style = "inside_deep_frame"}
        local camera = cam_frame.add{
            type          = "camera",
            position      = target.position,
            surface_index = target.surface and target.surface.index or 1,
            zoom          = zoom,
        }
        camera.style.width  = CAMERA_WIDTH
        camera.style.height = CAMERA_HEIGHT

        camera_refs[target.index] = camera
    end

    state.cameras = camera_refs
end

-- ─── Public API ────────────────────────────────────────────────────────

--- Add a player to the viewer's follow cam grid (or remove if already there).
function follow_cam.toggle_target(viewer, target_index)
    if not (viewer and viewer.valid) then return end
    if viewer.index == target_index then return end  -- can't follow yourself
    local state = ensure_state(viewer.index)
    if state.targets[target_index] then
        state.targets[target_index]     = nil
        state.zoom_levels[target_index] = nil
    else
        state.targets[target_index] = true
    end
    rebuild_frame(viewer, state)
end

--- Close the follow cam for a viewer (clears all targets).
function follow_cam.close(viewer)
    if not (viewer and viewer.valid) then return end
    if viewer.gui.screen[FRAME_NAME] then
        storage.follow_cam_location = storage.follow_cam_location or {}
        storage.follow_cam_location[viewer.index] = viewer.gui.screen[FRAME_NAME].location
        viewer.gui.screen[FRAME_NAME].destroy()
    end
    clear_state(viewer.index)
end

--- Check whether a viewer is currently following a specific player.
--- Used by the teams GUI to highlight already-selected follow targets.
function follow_cam.is_following(viewer_index, target_index)
    local state = (storage.follow_cam or {})[viewer_index]
    return state and state.targets[target_index] == true
end

-- ─── Tick Update ──────────────────────────────────────────────────────

--- Update all active follow cams. Called from on_nth_tick(2) in control.lua.
--- Per camera: resolves the target's view (avoiding chain-spectate when the
--- target is itself mts-spectating), writes position + surface_index, and
--- charts a box around the target for the viewer's force so the camera
--- widget has chart data and never renders as a black cell. `force.chart`
--- is idempotent on already-charted areas, so the repeat cost is minimal.
function follow_cam.tick()
    if not storage.follow_cam then return end
    for viewer_idx, state in pairs(storage.follow_cam) do
        local viewer = game.get_player(viewer_idx)
        if not (viewer and viewer.connected and viewer.gui.screen[FRAME_NAME]) then
            storage.follow_cam[viewer_idx] = nil
        else
            local viewer_force = viewer.force
            for target_idx, camera in pairs(state.cameras) do
                if camera.valid then
                    local target = game.get_player(target_idx)
                    if target and target.valid then
                        local _, surface, position = spectator.resolve_view_for(target)
                        if surface and surface.valid and position then
                            camera.position      = position
                            camera.surface_index = surface.index
                            -- Reveal a box around the target for the viewer's
                            -- force so the camera always has chart data. Per
                            -- design decision: spectating is read-only and
                            -- unrestricted, so we don't gate this on friendship.
                            if viewer_force and viewer_force.valid then
                                viewer_force.chart(surface, {
                                    {position.x - CHART_RADIUS, position.y - CHART_RADIUS},
                                    {position.x + CHART_RADIUS, position.y + CHART_RADIUS},
                                })
                            end
                        end
                    end
                end
            end
        end
    end
end

-- ─── Zoom ─────────────────────────────────────────────────────────────

--- Adjust a single camera's zoom by multiplying by `factor`, clamped to
--- [CAMERA_ZOOM_MIN, CAMERA_ZOOM_MAX]. Persists the zoom so it survives
--- rebuild_frame (e.g. when another target is added or removed).
local function adjust_zoom(viewer_index, target_idx, factor)
    local state = storage.follow_cam and storage.follow_cam[viewer_index]
    if not (state and target_idx) then return end
    state.zoom_levels = state.zoom_levels or {}
    local current = state.zoom_levels[target_idx] or CAMERA_ZOOM
    local new_zoom = math.max(CAMERA_ZOOM_MIN, math.min(current * factor, CAMERA_ZOOM_MAX))
    state.zoom_levels[target_idx] = new_zoom
    local cam = state.cameras and state.cameras[target_idx]
    if cam and cam.valid then cam.zoom = new_zoom end
end

-- ─── Click Handler ────────────────────────────────────────────────────

--- Handle GUI clicks. Returns true if consumed.
function follow_cam.on_gui_click(event)
    local el = event.element
    if not el or not el.valid then return false end

    if el.name == "sb_follow_cam_close" then
        local player = game.get_player(event.player_index)
        if player then follow_cam.close(player) end
        return true
    end

    local tags = el.tags
    if not tags then return false end

    if tags.sb_follow_cam_zoom_in then
        adjust_zoom(event.player_index, tags.target_idx, CAMERA_ZOOM_STEP)
        return true
    end

    if tags.sb_follow_cam_zoom_out then
        adjust_zoom(event.player_index, tags.target_idx, 1 / CAMERA_ZOOM_STEP)
        return true
    end

    if tags.sb_follow_cam_remove then
        local player = game.get_player(event.player_index)
        if player then follow_cam.toggle_target(player, tags.target_idx) end
        return true
    end

    -- Expand a single follow-cam cell into full spectator mode
    if tags.sb_follow_cam_spectate then
        local player = game.get_player(event.player_index)
        local target = tags.target_idx and game.get_player(tags.target_idx)
        if not (player and player.valid and target and target.valid
                and target.connected) then
            return true
        end
        -- Resolve the target's true team and actual view (see
        -- spectator.resolve_view_for for the chain-spectate rule).
        local target_force, surface, position = spectator.resolve_view_for(target)
        local viewer_force = game.forces[spectator.get_effective_force(player)]
        if not (viewer_force and target_force
                and surface and surface.valid and position) then
            return true
        end

        -- Use friend-view if the two teams are friends; otherwise spectator mode.
        -- `target` is passed through so the broadcast can name the watched player.
        if spectator.needs_spectator_mode(viewer_force, target_force) then
            if spectator.is_spectating(player) then
                spectator.switch_target(player, target_force, surface, position, target)
            else
                spectator.enter(player, target_force, surface, position, target)
            end
        else
            spectator.enter_friend_view(player, surface, position, target_force, target)
        end
        return true
    end

    return false
end

-- ─── Lifecycle ────────────────────────────────────────────────────────

--- Rebuild all open follow cams (e.g. when a target disconnects).
--- Drops offline targets from each viewer's grid.
function follow_cam.rebuild_all()
    if not storage.follow_cam then return end
    for viewer_idx, state in pairs(storage.follow_cam) do
        local viewer = game.get_player(viewer_idx)
        if viewer and viewer.connected and viewer.gui.screen[FRAME_NAME] then
            rebuild_frame(viewer, state)
        else
            storage.follow_cam[viewer_idx] = nil
        end
    end
end

--- Called when a player disconnects: close their follow cam, and drop
--- them from any other viewer's grid.
function follow_cam.on_player_left(player)
    -- Destroy the frame so the player starts clean on rejoin; without this,
    -- the stale frame persists but storage state is gone, making buttons no-ops.
    if player.gui.screen[FRAME_NAME] then
        player.gui.screen[FRAME_NAME].destroy()
    end
    clear_state(player.index)
    -- Remove this player from all other viewers' target sets
    if not storage.follow_cam then return end
    for _, state in pairs(storage.follow_cam) do
        state.targets[player.index] = nil
    end
    follow_cam.rebuild_all()
end

return follow_cam
