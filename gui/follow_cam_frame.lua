-- gui/follow_cam_frame.lua
-- GUI constants and frame builder for the Follow Cam grid.
-- Storage helpers, public API, tick, and click handlers are in gui/follow_cam.lua.

local helpers   = require("scripts.helpers")
local spectator = require("scripts.spectator")

local M = {}

-- ─── Constants (re-exported so follow_cam.lua doesn't duplicate them) ─

M.FRAME_NAME      = "sb_follow_cam_frame"
M.CAMERA_WIDTH    = 320
M.CAMERA_HEIGHT   = 200
M.CAMERA_ZOOM     = 0.5
M.CAMERA_ZOOM_MIN = 0.05
M.CAMERA_ZOOM_MAX = 0.75
M.CAMERA_ZOOM_STEP = 1.25
M.CHART_RADIUS    = 200

-- ─── Private helpers ──────────────────────────────────────────────────

local function choose_columns(n)
    if n <= 1 then return 1 end
    if n <= 4 then return 2 end
    return 3
end

--- Resolve an ordered list of currently-online target players, sorted by name.
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

-- ─── Frame builder ────────────────────────────────────────────────────

--- Build (or rebuild) the follow cam frame based on current targets.
--- Closes the frame and clears state if there are no online targets.
function M.rebuild_frame(viewer, state)
    if not (viewer and viewer.valid and viewer.connected) then return end

    local targets = resolve_targets(state.targets)

    if #targets == 0 then
        if viewer.gui.screen[M.FRAME_NAME] then
            viewer.gui.screen[M.FRAME_NAME].destroy()
        end
        state.cameras     = {}
        state.targets     = {}
        state.zoom_levels = {}
        return
    end

    if viewer.gui.screen[M.FRAME_NAME] then
        storage.follow_cam_location = storage.follow_cam_location or {}
        storage.follow_cam_location[viewer.index] = viewer.gui.screen[M.FRAME_NAME].location
        viewer.gui.screen[M.FRAME_NAME].destroy()
    end

    storage.follow_cam_location = storage.follow_cam_location or {}
    local frame = helpers.reuse_or_create_frame(
        viewer, M.FRAME_NAME, storage.follow_cam_location, {x = 300, y = 120})

    local title_bar = helpers.add_title_bar(frame, "Follow Cam")
    title_bar.add{
        type    = "sprite-button",
        name    = "sb_follow_cam_close",
        sprite  = "utility/close",
        style   = "close_button",
        tooltip = "Close Follow Cam",
    }

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

        -- Expand to full spectator view (Esc returns to this grid).
        name_row.add{
            type    = "sprite-button",
            sprite  = "utility/search_icon",
            style   = "mini_button",
            tags    = {sb_follow_cam_spectate = true, target_idx = target.index},
            tooltip = "Expand to full spectator view (Esc to return here)",
        }

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

        name_row.add{
            type    = "sprite-button",
            sprite  = "utility/close",
            style   = "mini_button",
            tags    = {sb_follow_cam_remove = true, target_idx = target.index},
            tooltip = "Remove from Follow Cam",
        }

        local zoom = state.zoom_levels[target.index] or M.CAMERA_ZOOM
        local cam_frame = cell.add{type = "frame", style = "inside_deep_frame"}
        local _, t_surface, t_pos = spectator.resolve_view_for(target)
        t_surface = (t_surface and t_surface.valid) and t_surface or target.surface
        t_pos     = t_pos or target.position
        local camera = cam_frame.add{
            type          = "camera",
            position      = t_pos,
            surface_index = t_surface and t_surface.index or 1,
            zoom          = zoom,
        }
        camera.style.width  = M.CAMERA_WIDTH
        camera.style.height = M.CAMERA_HEIGHT
        if viewer.force and viewer.force.valid and t_surface and t_surface.valid then
            viewer.force.chart(t_surface, {
                {t_pos.x - M.CHART_RADIUS, t_pos.y - M.CHART_RADIUS},
                {t_pos.x + M.CHART_RADIUS, t_pos.y + M.CHART_RADIUS},
            })
        end

        camera_refs[target.index] = camera
    end

    state.cameras = camera_refs
end

return M
