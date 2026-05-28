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

-- Gap (logical px) between adjacent camera panels — the "divider" line.
local NORMAL_GAP    = 4
local MAXIMIZED_GAP = 2

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

--- Show/refresh a camera's "Spectating <team>" label. Hidden unless the target
--- is actively in spectator mode. Called both at build time and from the tick so
--- the flag tracks the target's state live.
function M.update_spectate_label(label, target)
    if not (label and label.valid) then return end
    if target and target.valid and spectator.is_spectating(target) then
        local watched = spectator.get_target(target)
        label.caption = "Spectating "
            .. (watched and helpers.display_name(watched) or "another team")
        label.visible = true
    else
        label.visible = false
    end
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
        state.cameras         = {}
        state.targets         = {}
        state.zoom_levels     = {}
        state.physical        = {}
        state.spectate_labels = {}
        state.maximized       = nil
        state.shown_maximized = nil
        return
    end

    if viewer.gui.screen[M.FRAME_NAME] then
        -- Persist position only when the window currently on screen is a normal
        -- one. A maximized window sits at the top-left, so saving it would clobber
        -- the restore location and break "Esc returns to the original spot".
        if not state.shown_maximized then
            storage.follow_cam_location = storage.follow_cam_location or {}
            storage.follow_cam_location[viewer.index] = viewer.gui.screen[M.FRAME_NAME].location
        end
        viewer.gui.screen[M.FRAME_NAME].destroy()
    end

    storage.follow_cam_location = storage.follow_cam_location or {}
    local frame = helpers.reuse_or_create_frame(
        viewer, M.FRAME_NAME, storage.follow_cam_location, {x = 300, y = 120})

    local title_bar = helpers.add_title_bar(frame, "Follow Cam")
    title_bar.add{
        type    = "sprite-button",
        name    = "sb_follow_cam_maximize",
        sprite  = state.maximized and "utility/collapse" or "utility/expand",
        style   = "frame_action_button",
        tooltip = state.maximized and "Restore size" or "Maximize (Esc to restore)",
    }
    title_bar.add{
        type    = "sprite-button",
        name    = "sb_follow_cam_close",
        sprite  = "utility/close",
        style   = "close_button",
        tooltip = "Close Follow Cam",
    }

    local maximized = state.maximized == true
    local cols = choose_columns(#targets)
    local rows = math.ceil(#targets / cols)
    local gap  = maximized and MAXIMIZED_GAP or NORMAL_GAP

    -- Nested flows (not a table) so that, when maximized, stretchable cameras
    -- divide the frame's height across rows and its width across columns —
    -- letting the layout engine fill the screen exactly instead of us guessing.
    local outer = frame.add{type = "flow", direction = "vertical"}
    outer.style.vertical_spacing = gap
    if maximized then
        outer.style.horizontally_stretchable = true
        outer.style.vertically_stretchable   = true
    end

    local camera_refs = {}
    local spectate_labels = {}
    local idx = 1
    for _ = 1, rows do
        local row = outer.add{type = "flow", direction = "horizontal"}
        row.style.horizontal_spacing = gap
        if maximized then
            row.style.horizontally_stretchable = true
            row.style.vertically_stretchable   = true
        end

        for _ = 1, cols do
            local target = targets[idx]
            idx = idx + 1
            if target then
                local cell = row.add{type = "flow", direction = "vertical"}
                cell.style.vertical_spacing = 2
                if maximized then
                    cell.style.horizontally_stretchable = true
                    cell.style.vertically_stretchable   = true
                end

                local name_row = cell.add{type = "flow", direction = "horizontal"}
                name_row.style.vertical_align           = "center"
                name_row.style.horizontally_stretchable = true

                local name_lbl = name_row.add{type = "label", caption = target.name}
                name_lbl.style.font       = "default-bold"
                name_lbl.style.font_color = target.chat_color

                -- Always show the player's REAL team, even while they're temporarily
                -- force-swapped into the spectator force (otherwise this reads
                -- "spectator"). get_effective_force returns the real team when
                -- spectating, else the current force.
                local real_fn    = spectator.get_effective_force(target)
                local real_force = game.forces[real_fn]
                local team_lbl = name_row.add{
                    type    = "label",
                    caption = "  " .. helpers.display_name(real_fn),
                }
                team_lbl.style.font       = "default-small"
                team_lbl.style.font_color = real_force and helpers.force_color(real_force)
                                            or {1, 1, 1}

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

                -- Track the target's live view (default) or their physical body.
                local phys = state.physical and state.physical[target.index] or false
                local mode_btn = name_row.add{
                    type    = "button",
                    caption = phys and "Body" or "View",
                    tags    = {sb_follow_cam_view_toggle = true, target_idx = target.index},
                    tooltip = phys
                        and "Tracking the player's physical body. Click to track their live view (where they're looking) instead."
                        or  "Tracking the player's live view (where they're looking). Click to track their physical body instead.",
                }
                mode_btn.style.width   = 46
                mode_btn.style.height  = 22
                mode_btn.style.padding = 0
                mode_btn.style.font    = "default-small"

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

                -- Flag when the target is actively spectating another team: their
                -- live view (and so the View-mode camera) is on that team's surface,
                -- not their own base. The label is always created (hidden when not
                -- spectating) so the tick can flip it live without a full rebuild.
                local spec_lbl = cell.add{type = "label"}
                spec_lbl.style.font       = "default-small"
                spec_lbl.style.font_color = {1, 0.7, 0.2}
                M.update_spectate_label(spec_lbl, target)
                spectate_labels[target.index] = spec_lbl

                local zoom = state.zoom_levels[target.index] or M.CAMERA_ZOOM
                local _, t_surface, t_pos = spectator.resolve_view_for(target, phys)
                t_surface = (t_surface and t_surface.valid) and t_surface or target.surface
                t_pos     = t_pos or target.position
                local camera = cell.add{
                    type          = "camera",
                    position      = t_pos,
                    surface_index = t_surface and t_surface.index or 1,
                    zoom          = zoom,
                }
                if maximized then
                    camera.style.horizontally_stretchable = true
                    camera.style.vertically_stretchable   = true
                    camera.style.minimal_width  = 64
                    camera.style.minimal_height = 64
                else
                    camera.style.width  = M.CAMERA_WIDTH
                    camera.style.height = M.CAMERA_HEIGHT
                end
                -- Only persistently chart in physical mode (see resolve_view_for):
                -- live-view mode must not reveal fog around a pannable camera.
                if phys and viewer.force and viewer.force.valid and t_surface and t_surface.valid then
                    viewer.force.chart(t_surface, {
                        {t_pos.x - M.CHART_RADIUS, t_pos.y - M.CHART_RADIUS},
                        {t_pos.x + M.CHART_RADIUS, t_pos.y + M.CHART_RADIUS},
                    })
                end

                camera_refs[target.index] = camera
            end
        end
    end

    state.cameras         = camera_refs
    state.spectate_labels = spectate_labels

    if maximized then
        -- Pin the frame to the exact screen size (logical px = physical / scale)
        -- and anchor it top-left; the stretchable cameras above then fill it.
        -- Esc is captured so it restores rather than closes.
        local res, scale = viewer.display_resolution, viewer.display_scale
        frame.style.padding = 0
        if res and scale and scale > 0 then
            frame.style.width  = math.floor(res.width  / scale)
            frame.style.height = math.floor(res.height / scale)
        end
        frame.location = {x = 0, y = 0}
        viewer.opened  = frame
    end

    -- Record what we just rendered so the next rebuild knows whether the
    -- on-screen window was maximized (used by the save-location guard above).
    state.shown_maximized = maximized
end

return M
