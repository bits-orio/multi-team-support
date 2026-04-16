-- Multi-Team Support - helpers.lua
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

--- Get the display name for a force.
--- Uses storage.team_names for team forces (e.g. "Team 01" or custom name),
--- falling back to the force name itself for non-team forces.
---   "team-1" → "Team 01" (or custom name from /mts-rename)
---   "enemy"  → "enemy"
function helpers.display_name(force_name)
    if storage and storage.team_names and storage.team_names[force_name] then
        return storage.team_names[force_name]
    end
    return force_name
end

--- Get the team name for use in chat announcements. Always prefixed with
--- "Team " when the display name doesn't already start with "Team".
---   "team-1" with default name "Team 01" → "Team 01"
---   "team-1" renamed to "Pioneers"       → "Team Pioneers"
---   "team-1" renamed to "team alpha"     → "team alpha"  (already has it)
function helpers.team_display(force_name)
    local name = helpers.display_name(force_name)
    if name:lower():find("^team") then
        return name
    end
    return "Team " .. name
end

--- Rich-text colored team name for announcements. Uses the force's color.
---   "team-1" renamed to "Pioneers" → "[color=R,G,B]Team Pioneers[/color]"
function helpers.team_tag(force_name)
    local force = game.forces[force_name]
    local color = force and helpers.force_color(force) or helpers.WHITE
    return helpers.colored_name(helpers.team_display(force_name), color)
end

--- Return the force's color (set from the team leader's player color).
--- Prefers custom_color (writable) over color (read-only, may be stale).
--- Falls back to white if neither is set.
function helpers.force_color(force)
    return force.custom_color or force.color or helpers.WHITE
end

--- Wrap a string in a Factorio localised_name reference so it renders
--- with icon+name in chat. Falls back to the plain name if no prototype.
---   helpers.item_rich_name("iron-plate") → "[item=iron-plate]"
function helpers.item_rich_name(item_name)
    if prototypes and prototypes.item and prototypes.item[item_name] then
        return "[item=" .. item_name .. "]"
    end
    return item_name
end

--- Return a rich-text tech name including icon.
---   helpers.tech_rich_name("automation") → "[technology=automation]"
function helpers.tech_rich_name(tech_name)
    return "[technology=" .. tech_name .. "]"
end

--- Build a grey force-name tag for chat messages.
---   " [color=0.50,0.50,0.50](force-bob)[/color]"
function helpers.force_tag(force_name)
    return " [color=0.50,0.50,0.50](" .. force_name .. ")[/color]"
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

-- ─── Time Formatting ───────────────────────────────────────────────────

--- Format an elapsed tick count into a human-readable string.
--- 60 ticks = 1 second in Factorio.
---   3600 ticks     → "60s"
---   60*60 ticks    → "1m 0s"
---   60*60*60 ticks → "1h 0m"
function helpers.format_elapsed(ticks)
    if not ticks or ticks < 0 then return "?" end
    local total_seconds = math.floor(ticks / 60)
    local hours = math.floor(total_seconds / 3600)
    local mins  = math.floor((total_seconds % 3600) / 60)
    local secs  = total_seconds % 60
    if hours > 0 then
        return string.format("%dh %dm", hours, mins)
    elseif mins > 0 then
        return string.format("%dm %ds", mins, secs)
    else
        return string.format("%ds", secs)
    end
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
