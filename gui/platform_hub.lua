-- gui/platform_hub.lua
-- Anchors mod-registered widgets into the native space-platform-hub GUI via a
-- relative GUI. Mirrors the custom team-tab system: a mod registers a widget
-- (remote_api.register_platform_hub_widget) and fills the frame it is handed
-- through the on_platform_hub_gui_built event, raised each time a player opens
-- a platform hub. The frame is rebuilt every open so its content can reflect
-- the specific hub (entity.surface.platform / its location).

local remote_api = require("scripts.remote_api")

local platform_hub = {}

local PREFIX = "mts_hub_widget_"

local POSITIONS = {
    left   = defines.relative_gui_position.left,
    right  = defines.relative_gui_position.right,
    top    = defines.relative_gui_position.top,
    bottom = defines.relative_gui_position.bottom,
}

local function on_gui_opened(event)
    if event.gui_type ~= defines.gui_type.entity then return end
    local entity = event.entity
    if not (entity and entity.valid and entity.type == "space-platform-hub") then return end
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end

    for _, def in ipairs(remote_api.get_platform_hub_widgets()) do
        local name = PREFIX .. def.name
        -- Rebuild fresh each open so content matches THIS hub (no stale state,
        -- no duplicates).
        local existing = player.gui.relative[name]
        if existing then existing.destroy() end

        local frame = player.gui.relative.add{
            type      = "frame",
            name      = name,
            caption   = def.caption,
            direction = "vertical",
            anchor    = {
                gui      = defines.relative_gui_type.space_platform_hub_gui,
                position = POSITIONS[def.position] or defines.relative_gui_position.right,
            },
        }
        frame.style.padding = 8

        script.raise_event(remote_api.events.on_platform_hub_gui_built, {
            player_index = player.index,
            widget_name  = def.name,
            element      = frame,
            entity       = entity,
        })
    end
end

function platform_hub.register()
    script.on_event(defines.events.on_gui_opened, on_gui_opened)
end

return platform_hub
