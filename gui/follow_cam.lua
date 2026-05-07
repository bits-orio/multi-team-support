-- gui/follow_cam.lua
-- Follow Cam: grid of live camera widgets that track individual players.
-- Frame building constants and rebuild_frame live in gui/follow_cam_frame.lua.

local helpers   = require("scripts.helpers")
local spectator = require("scripts.spectator")
local fcf       = require("gui.follow_cam_frame")

local follow_cam = {}

local FRAME_NAME       = fcf.FRAME_NAME
local CAMERA_ZOOM      = fcf.CAMERA_ZOOM
local CAMERA_ZOOM_MIN  = fcf.CAMERA_ZOOM_MIN
local CAMERA_ZOOM_MAX  = fcf.CAMERA_ZOOM_MAX
local CAMERA_ZOOM_STEP = fcf.CAMERA_ZOOM_STEP
local CHART_RADIUS     = fcf.CHART_RADIUS

-- ─── Storage helpers ──────────────────────────────────────────────────

local function clear_state(viewer_index)
    if storage.follow_cam then storage.follow_cam[viewer_index] = nil end
end

local function ensure_state(viewer_index)
    storage.follow_cam = storage.follow_cam or {}
    if not storage.follow_cam[viewer_index] then
        storage.follow_cam[viewer_index] = {targets = {}, cameras = {}, zoom_levels = {}}
    end
    storage.follow_cam[viewer_index].zoom_levels =
        storage.follow_cam[viewer_index].zoom_levels or {}
    return storage.follow_cam[viewer_index]
end

-- ─── Public API ───────────────────────────────────────────────────────

--- Toggle a player in the viewer's follow cam grid.
function follow_cam.toggle_target(viewer, target_index)
    if not (viewer and viewer.valid) then return end
    if viewer.index == target_index then return end
    local state = ensure_state(viewer.index)
    if state.targets[target_index] then
        state.targets[target_index]     = nil
        state.zoom_levels[target_index] = nil
    else
        state.targets[target_index] = true
    end
    fcf.rebuild_frame(viewer, state)
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

--- Return true if the viewer is currently following target_index.
function follow_cam.is_following(viewer_index, target_index)
    local state = (storage.follow_cam or {})[viewer_index]
    return state and state.targets[target_index] == true
end

-- ─── Tick Update ──────────────────────────────────────────────────────

--- Update all active follow cams. Called from on_nth_tick(2) in control.lua.
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

local function adjust_zoom(viewer_index, target_idx, factor)
    local state = storage.follow_cam and storage.follow_cam[viewer_index]
    if not (state and target_idx) then return end
    state.zoom_levels = state.zoom_levels or {}
    local current  = state.zoom_levels[target_idx] or CAMERA_ZOOM
    local new_zoom = math.max(CAMERA_ZOOM_MIN, math.min(current * factor, CAMERA_ZOOM_MAX))
    state.zoom_levels[target_idx] = new_zoom
    local cam = state.cameras and state.cameras[target_idx]
    if cam and cam.valid then cam.zoom = new_zoom end
end

-- ─── Click Handler ────────────────────────────────────────────────────

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

    if tags.sb_follow_cam_spectate then
        local player = game.get_player(event.player_index)
        local target = tags.target_idx and game.get_player(tags.target_idx)
        if not (player and player.valid and target and target.valid
                and target.connected) then
            return true
        end
        local target_force, surface, position = spectator.resolve_view_for(target)
        local viewer_force = game.forces[spectator.get_effective_force(player)]
        if not (viewer_force and target_force
                and surface and surface.valid and position) then
            return true
        end
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
function follow_cam.rebuild_all()
    if not storage.follow_cam then return end
    for viewer_idx, state in pairs(storage.follow_cam) do
        local viewer = game.get_player(viewer_idx)
        if viewer and viewer.connected and viewer.gui.screen[FRAME_NAME] then
            fcf.rebuild_frame(viewer, state)
        else
            storage.follow_cam[viewer_idx] = nil
        end
    end
end

--- Called when a player disconnects: close their cam and drop them from others.
function follow_cam.on_player_left(player)
    if player.gui.screen[FRAME_NAME] then
        player.gui.screen[FRAME_NAME].destroy()
    end
    clear_state(player.index)
    if not storage.follow_cam then return end
    for _, state in pairs(storage.follow_cam) do
        state.targets[player.index] = nil
    end
    follow_cam.rebuild_all()
end

return follow_cam
