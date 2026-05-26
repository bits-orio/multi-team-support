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

-- How often (ticks) open hub widgets are refreshed. A space platform hub has
-- no "inventory changed" event, so to keep widgets live (clone added/removed,
-- platform arrived, base established) we re-raise the build event on a bounded
-- poll -- only for players who actually have a hub open.
local REFRESH_INTERVAL = 15

--- Create-or-reuse the anchored frame for each registered widget and hand it to
--- the owning mod to (re)fill. The frame is REUSED across refreshes (not
--- destroyed), so a consumer that updates in place gets no flicker.
local function build_for(player, entity)
    for _, def in ipairs(remote_api.get_platform_hub_widgets()) do
        local name  = PREFIX .. def.name
        local frame = player.gui.relative[name]
        if not (frame and frame.valid) then
            frame = player.gui.relative.add{
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
        end
        script.raise_event(remote_api.events.on_platform_hub_gui_built, {
            player_index = player.index,
            widget_name  = def.name,
            element      = frame,
            entity       = entity,
        })
    end
end

local function on_gui_opened(event)
    if event.gui_type ~= defines.gui_type.entity then return end
    local entity = event.entity
    if not (entity and entity.valid and entity.type == "space-platform-hub") then return end
    local player = game.get_player(event.player_index)
    if player and player.valid then build_for(player, entity) end
end

--- Re-raise the build event for every player who currently has a hub open, so
--- widgets stay current. player.opened is synced game state, so this is
--- identical on every peer.
local function refresh_open(_)
    for _, player in pairs(game.connected_players) do
        local o = player.opened
        if o and o.object_name == "LuaEntity" and o.valid
           and o.type == "space-platform-hub" then
            build_for(player, o)
        end
    end
end

function platform_hub.register()
    script.on_event(defines.events.on_gui_opened, on_gui_opened)
    script.on_nth_tick(REFRESH_INTERVAL, refresh_open)
end

return platform_hub
