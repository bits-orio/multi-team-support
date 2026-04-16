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
--     targets = {[target_index] = true, ...},  -- set of player indices to track
--     cameras = {[target_index] = LuaGuiElement, ...},  -- rebuilt on changes
--   }

local helpers   = require("helpers")
local spectator = require("spectator")

local follow_cam = {}

-- ─── Constants ────────────────────────────────────────────────────────

local FRAME_NAME    = "sb_follow_cam_frame"
local CAMERA_WIDTH  = 320
local CAMERA_HEIGHT = 200
local CAMERA_ZOOM   = 0.5

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
        storage.follow_cam[viewer_index] = {targets = {}, cameras = {}}
    end
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
        state.cameras = {}
        state.targets = {}
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

        -- Camera widget inside a deep frame for a nice border
        local cam_frame = cell.add{type = "frame", style = "inside_deep_frame"}
        local camera = cam_frame.add{
            type          = "camera",
            position      = target.position,
            surface_index = target.surface and target.surface.index or 1,
            zoom          = CAMERA_ZOOM,
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
        state.targets[target_index] = nil
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
--- Server cost per camera: two property assignments (position + surface_index).
--- Rendering is client-side (GPU), so server load scales with viewers × cameras.
function follow_cam.tick()
    if not storage.follow_cam then return end
    for viewer_idx, state in pairs(storage.follow_cam) do
        local viewer = game.get_player(viewer_idx)
        if not (viewer and viewer.connected and viewer.gui.screen[FRAME_NAME]) then
            storage.follow_cam[viewer_idx] = nil
        else
            for target_idx, camera in pairs(state.cameras) do
                if camera.valid then
                    local target = game.get_player(target_idx)
                    if target and target.valid then
                        camera.position      = target.position
                        camera.surface_index = target.surface and target.surface.index
                            or camera.surface_index
                    end
                end
            end
        end
    end
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

    -- Expand a single follow-cam cell into full spectator mode
    if el.tags and el.tags.sb_follow_cam_spectate then
        local player = game.get_player(event.player_index)
        local target = el.tags.target_idx and game.get_player(el.tags.target_idx)
        if not (player and player.valid and target and target.valid
                and target.connected and target.surface) then
            return true
        end
        local target_force = target.force
        local viewer_force = game.forces[spectator.get_effective_force(player)]
        if not (viewer_force and target_force) then return true end

        local surface  = target.surface
        local position = target.position

        -- Use friend-view if the two teams are friends; otherwise spectator mode.
        if spectator.needs_spectator_mode(viewer_force, target_force) then
            if spectator.is_spectating(player) then
                spectator.switch_target(player, target_force, surface, position)
            else
                spectator.enter(player, target_force, surface, position)
            end
        else
            spectator.enter_friend_view(player, surface, position)
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
    clear_state(player.index)
    -- Remove this player from all other viewers' target sets
    if not storage.follow_cam then return end
    for _, state in pairs(storage.follow_cam) do
        state.targets[player.index] = nil
    end
    follow_cam.rebuild_all()
end

return follow_cam
