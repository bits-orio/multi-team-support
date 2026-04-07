-- Solo Teams - helpers.lua
-- Author: bits-orio
-- License: MIT
--
-- Shared utility functions used across all modules.
-- Eliminates duplicated patterns and provides canonical answers to
-- common questions about forces, players, surfaces, and GUI state.

local helpers = {}

-- ─── Constants ─────────────────────────────────────────────────────────

helpers.WHITE  = {r = 1, g = 1, b = 1}
helpers.ORIGIN = {x = 0, y = 0}

-- ─── Force Helpers ─────────────────────────────────────────────────────

--- Strip the "player-" prefix from a force name to get the display name.
--- Returns the name unchanged if it doesn't match the pattern.
---   "player-bob" → "bob"
---   "enemy"      → "enemy"
function helpers.display_name(force_name)
    return force_name:match("^player%-(.+)$") or force_name
end

--- Return the first connected player's chat_color for a force, or white.
function helpers.force_color(force)
    local first = force.connected_players[1]
    return first and first.chat_color or helpers.WHITE
end

--- Build a Factorio rich-text colored tag for a player.
---   "[color=R,G,B]name[/color]"
function helpers.colored_name(name, color)
    return string.format("[color=%.2f,%.2f,%.2f]%s[/color]",
        color.r or color[1] or 1,
        color.g or color[2] or 1,
        color.b or color[3] or 1,
        name)
end

-- ─── Broadcast ─────────────────────────────────────────────────────────

--- Print a message to all connected players.
function helpers.broadcast(msg)
    for _, p in pairs(game.players) do
        if p.connected then p.print(msg) end
    end
end

-- ─── GUI Frame Helpers ─────────────────────────────────────────────────

--- Reuse an existing screen frame (preserving drag position) or create a
--- new one. Returns the frame (cleared if reused, fresh if created).
---
---   frame = helpers.reuse_or_create_frame(player, "sb_platforms_frame",
---               storage.gui_location, {x = 5, y = 400})
---
--- The location_table is keyed by player.index.
function helpers.reuse_or_create_frame(player, frame_name, location_table, default_pos)
    local screen = player.gui.screen
    local frame = screen[frame_name]
    if frame then
        location_table[player.index] = frame.location
        frame.clear()
    else
        frame = screen.add{
            type      = "frame",
            name      = frame_name,
            direction = "vertical",
        }
        local saved = location_table[player.index]
        frame.location = saved or default_pos
    end
    return frame
end

--- Add a standard draggable title bar to a frame.
--- Returns the title_bar flow so callers can add extra widgets.
function helpers.add_title_bar(frame, caption)
    local title_bar = frame.add{type = "flow", direction = "horizontal"}
    title_bar.style.vertical_align = "center"
    title_bar.drag_target = frame
    title_bar.add{type = "label", caption = caption, style = "frame_title"}
    local spacer = title_bar.add{type = "empty-widget", style = "draggable_space_header"}
    spacer.style.horizontally_stretchable = true
    spacer.style.height = 24
    spacer.drag_target = frame
    return title_bar
end

-- ─── Player Preferences ────────────────────────────────────────────────

--- Returns true if this player wants to see offline players in GUIs.
function helpers.show_offline(player)
    storage.show_offline_players = storage.show_offline_players or {}
    return storage.show_offline_players[player.index] or false
end

--- Toggle the show-offline preference for a player.
function helpers.toggle_show_offline(player)
    storage.show_offline_players = storage.show_offline_players or {}
    storage.show_offline_players[player.index] = not helpers.show_offline(player)
end

return helpers
