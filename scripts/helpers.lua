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

-- ─── Surface Hiding Wrapper ────────────────────────────────────────────
-- Wrapper around force.set_surface_hidden that also validates arguments.
-- The DISABLE_SURFACE_HIDING kill-switch remains in place as a debugging
-- lever in case we need to rule out hiding again in the future (the
-- Platformer landing-pen teleport bug was caused by the interaction of
-- set_surface_hidden with god-mode players; see the god_pre_remote guard
-- in control.lua's on_player_controller_changed handler for the fix).
helpers.DISABLE_SURFACE_HIDING = false

function helpers.set_surface_hidden(force, surface, hidden)
    if helpers.DISABLE_SURFACE_HIDING then return end
    if not (force and force.valid and surface and surface.valid) then return end
    force.set_surface_hidden(surface, hidden)
end

-- ─── Diagnostic Logging ────────────────────────────────────────────────

--- Return a compact "(x,y)" string for a position table.
local function fmt_pos(p)
    if not p then return "?" end
    return string.format("(%.1f,%.1f)", p.x or 0, p.y or 0)
end

--- Return a comprehensive state string for a player, including:
---   name, force, surface, position, physical_surface, physical_position,
---   controller_type (useful for detecting remote vs character view).
--- Used by diagnostic log statements across the mod.
function helpers.player_state(player)
    if not (player and player.valid) then return "?" end
    local ctrl = player.controller_type
    local ctrl_name = "?"
    for name, id in pairs(defines.controllers) do
        if id == ctrl then ctrl_name = name; break end
    end
    local ps = player.physical_surface
    local s  = player.surface
    return string.format(
        "%s force=%s surface=%s pos=%s phys_surface=%s phys_pos=%s ctrl=%s",
        player.name,
        player.force and player.force.name or "?",
        (s and s.valid) and s.name or "?",
        fmt_pos(player.position),
        (ps and ps.valid) and ps.name or "?",
        fmt_pos(player.physical_position),
        ctrl_name
    )
end

--- Log a [DIAG] line with free-form context + player state snapshot.
--- Safe if player is nil.
function helpers.diag(context, player)
    log("[multi-team-support:DIAG] " .. context
        .. " | " .. helpers.player_state(player))
end

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

--- Player-facing name for a surface, stripping per-team prefixes and
--- capitalising the planet. Space platforms keep their literal name.
---   "mts-nauvis-1"   → "Nauvis"     (Space Age per-team variant)
---   "team-2-vulcanus" → "Vulcanus"  (legacy cloned surface)
---   "landing-pen"    → "landing-pen"
---   "my platform 3"  → "my platform 3"
function helpers.display_surface_name(surface_name)
    if not surface_name then return "?" end
    local base = surface_name:match("^mts%-(.+)%-%d+$")
        or surface_name:match("^team%-%d+%-(.+)$")
    if base then
        return base:sub(1, 1):upper() .. base:sub(2)
    end
    return surface_name
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

--- True if any player on this team force is currently connected.
--- Accounts for members spectating other teams (their effective force changes
--- to "spectator" but spectator_real_force tracks their actual team).
function helpers.team_has_online_member(force_name)
    for _, p in pairs(game.players) do
        if p.valid and p.connected then
            local real_fn = (storage.spectator_real_force or {})[p.index] or p.force.name
            if real_fn == force_name then return true end
        end
    end
    return false
end

--- Team tag plus the current leader's name in dim brackets.
---   "[color=R,G,B]Team Pioneers[/color] [color=0.7,0.7,0.7][[/color][color=...]Alice[/color][color=0.7,0.7,0.7]][/color]"
---   No leader: appends " [color=0.7,0.7,0.7][?][/color]"
function helpers.team_tag_with_leader(force_name)
    local tag        = helpers.team_tag(force_name)
    local leader_idx = (storage.team_leader or {})[force_name]
    local leader     = leader_idx and game.get_player(leader_idx) or nil
    if leader and leader.valid then
        return tag
            .. " [color=0.7,0.7,0.7][[/color]"
            .. helpers.colored_name(leader.name, leader.chat_color)
            .. "[color=0.7,0.7,0.7]][/color]"
    end
    return tag .. " [color=0.7,0.7,0.7][?][/color]"
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

--- Build the "show offline" checkbox flow used in Teams / Stats / Research /
--- Awards GUIs. The checkbox is named "sb_show_offline_toggle" so a single
--- on_gui_checked_state_changed handler in control.lua catches clicks from
--- any of the GUIs.
function helpers.add_show_offline_checkbox(parent, player)
    local show_offline = helpers.show_offline(player)
    local flow = parent.add{type = "flow", direction = "horizontal"}
    flow.style.horizontal_align         = "right"
    flow.style.horizontally_stretchable = true
    flow.style.bottom_margin            = 2
    local label = flow.add{type = "label", caption = "show offline"}
    label.style.font         = "default-small"
    label.style.font_color   = {0.6, 0.6, 0.6}
    label.style.right_margin = 4
    flow.add{
        type    = "checkbox",
        name    = "sb_show_offline_toggle",
        state   = show_offline,
        tooltip = show_offline and "Hide offline teams" or "Show offline teams",
    }
    return flow
end

return helpers
