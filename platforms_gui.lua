-- Solo Teams - platforms_gui.lua
-- Author: bits-orio
-- License: MIT
--
-- Draggable, collapsible GUI overlay that shows all players and their
-- platforms. Includes clickable GPS ping buttons and per-player friend
-- toggle checkboxes.

local M = {}

--- Build a Factorio rich-text GPS tag for a platform's hub location.
--- Returns "" if the hub or surface is unavailable.
local function get_platform_gps(platform)
    local hub = platform.hub
    if hub and hub.valid and platform.surface then
        local pos = hub.position
        return string.format("[gps=%d,%d,%s]", pos.x, pos.y, platform.surface.name)
    end
    return ""
end

--- Build a Factorio rich-text GPS tag for a player's current position.
--- Returns "" if the player is offline or has no valid surface.
local function get_player_gps(player)
    if player and player.valid and player.connected and player.surface then
        local pos = player.position
        return string.format("[gps=%d,%d,%s]", pos.x, pos.y, player.surface.name)
    end
    return ""
end

--- Collect all platforms grouped by owner (player name).
--- Returns three tables:
---   owners:     { owner_name = { {name, location, gps}, ... }, ... }
---   order:      { owner_name, ... }  (insertion order)
---   owner_info: { owner_name = {gps, color, force_name}, ... }
--- Force names like "player-bob" are mapped to owner "bob".
--- The default "player" force keeps its name as-is.
function M.get_platforms_by_owner()
    local owners = {}
    local owner_info = {}
    local order = {}
    for _, force in pairs(game.forces) do
        if force.name ~= "enemy" and force.name ~= "neutral" then
            local has_platforms = false
            for _ in pairs(force.platforms) do has_platforms = true; break end
            if has_platforms then
                -- Strip the "player-" prefix to get the display name
                local owner = force.name:match("^player%-(.+)$") or force.name
                owners[owner] = {}
                order[#order + 1] = owner
                owner_info[owner] = {gps = "", color = {1, 1, 1}, force_name = force.name}
                -- Find the connected player matching this owner for live GPS/color
                for _, p in pairs(force.connected_players) do
                    if p.name == owner or force.name == "player" then
                        owner_info[owner].gps = get_player_gps(p)
                        owner_info[owner].color = p.chat_color
                        break
                    end
                end
                for _, platform in pairs(force.platforms) do
                    local location = platform.space_location and platform.space_location.name or "in transit"
                    local gps = get_platform_gps(platform)
                    owners[owner][#owners[owner] + 1] = {name = platform.name, location = location, gps = gps}
                end
            end
        end
    end
    return owners, order, owner_info
end

--- Check whether a player's GUI is in collapsed state.
local function is_gui_collapsed(player)
    storage.gui_collapsed = storage.gui_collapsed or {}
    return storage.gui_collapsed[player.index] or false
end

--- Build (or rebuild) the platforms GUI for a single player.
--- The GUI is placed on player.gui.screen so it can be freely dragged.
--- Position is persisted in storage.gui_location across rebuilds.
function M.build_platforms_gui(player)
    local screen = player.gui.screen
    storage.gui_location = storage.gui_location or {}

    -- Save current position before destroying, so drags are preserved
    if screen.sb_platforms_frame then
        storage.gui_location[player.index] = screen.sb_platforms_frame.location
        screen.sb_platforms_frame.destroy()
    end

    local collapsed = is_gui_collapsed(player)

    -- Main frame
    local frame = screen.add{
        type = "frame",
        name = "sb_platforms_frame",
        direction = "vertical"
    }

    -- Restore saved position or use default (5px from left edge)
    if storage.gui_location[player.index] then
        frame.location = storage.gui_location[player.index]
    else
        frame.location = {x = 5, y = 200}
    end

    -- Title bar: draggable, with "Platforms" label, spacer, and +/- toggle
    local title_bar = frame.add{type = "flow", name = "sb_title_bar", direction = "horizontal"}
    title_bar.style.vertical_align = "center"
    title_bar.style.horizontal_spacing = 8
    title_bar.drag_target = frame

    title_bar.add{type = "label", caption = "Platforms", style = "frame_title"}

    local spacer = title_bar.add{type = "empty-widget", style = "draggable_space_header"}
    spacer.style.horizontally_stretchable = true
    spacer.style.height = 24
    spacer.drag_target = frame

    title_bar.add{
        type = "sprite-button",
        name = "sb_platforms_toggle",
        caption = collapsed and "+" or "-",
        style = "close_button",
        tooltip = collapsed and "Show platforms" or "Hide platforms"
    }

    -- When collapsed, only the title bar is shown
    if collapsed then return end

    frame.style.maximal_height = 400
    frame.style.minimal_width = 220

    local scroll = frame.add{
        type = "scroll-pane",
        name = "sb_platforms_scroll",
        direction = "vertical"
    }
    scroll.style.maximal_height = 350

    -- Two-column table: col 1 = player/platform name + GPS, col 2 = friend toggle or location
    local tbl = scroll.add{
        type = "table",
        name = "sb_platforms_table",
        column_count = 2
    }
    tbl.style.horizontal_spacing = 12
    tbl.style.vertical_spacing = 2

    local owners, order, owner_info = M.get_platforms_by_owner()
    for _, owner in ipairs(order) do
        -- Player name row (col 1): bold, colored by chat_color, with GPS ping button
        local owner_flow = tbl.add{type = "flow", direction = "horizontal"}
        local owner_label = owner_flow.add{type = "label", caption = owner}
        owner_label.style.font = "default-bold"
        owner_label.style.font_color = owner_info[owner].color
        local c = owner_info[owner].color
        local color_str = string.format("%.2f,%.2f,%.2f", c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1)
        if owner_info[owner].gps ~= "" then
            owner_flow.add{
                type = "sprite-button",
                sprite = "utility/gps_map_icon",
                tags = {sb_gps = owner_info[owner].gps, sb_gps_label = owner, sb_gps_color = color_str, sb_gps_type = "player"},
                style = "mini_button",
                tooltip = "Ping " .. owner .. "'s location"
            }
        end

        -- Player name row (col 2): friend checkbox (only for other players)
        local target_force_name = owner_info[owner].force_name
        if target_force_name ~= player.force.name then
            local target_force = game.forces[target_force_name]
            if target_force then
                local is_friend = player.force.get_friend(target_force)
                local friend_flow = tbl.add{type = "flow", direction = "horizontal"}
                friend_flow.style.horizontal_align = "right"
                friend_flow.style.horizontally_stretchable = true
                local friend_label = friend_flow.add{type = "label", caption = "friend"}
                friend_label.style.font = "default-small"
                friend_label.style.font_color = {0, 1, 0}
                friend_label.style.right_margin = 4
                friend_flow.add{
                    type = "checkbox",
                    state = is_friend,
                    tags = {sb_friend_toggle = true, sb_target_force = target_force_name},
                    tooltip = is_friend and ("Unfriend " .. owner) or ("Friend " .. owner)
                }
            else
                tbl.add{type = "label", caption = ""}
            end
        else
            tbl.add{type = "label", caption = ""}
        end

        -- Platform rows: indented name (small font) + GPS button | location
        for _, info in ipairs(owners[owner]) do
            local plat_flow = tbl.add{type = "flow", direction = "horizontal"}
            local plat_label = plat_flow.add{type = "label", caption = "  " .. info.name}
            plat_label.style.font = "default-small"
            if info.gps ~= "" then
                plat_flow.add{
                    type = "sprite-button",
                    sprite = "utility/gps_map_icon",
                    tags = {sb_gps = info.gps, sb_gps_label = info.name, sb_gps_type = "platform"},
                    style = "mini_button",
                    tooltip = "Ping " .. info.name
                }
            end
            local loc_label = tbl.add{type = "label", caption = info.location}
            loc_label.style.font = "default-small"
        end
    end

    if #order == 0 then
        tbl.add{type = "label", caption = "No platforms yet."}
        tbl.add{type = "label", caption = ""}
    end
end

--- Rebuild the GUI for all connected players.
function M.update_all()
    for _, player in pairs(game.players) do
        if player.connected then
            M.build_platforms_gui(player)
        end
    end
end

--- Handle GUI click events for this mod's elements.
--- Returns true if the click was consumed, false otherwise.
function M.on_gui_click(event)
    local element = event.element
    if not element or not element.valid then return end

    -- Toggle collapse/expand
    if element.name == "sb_platforms_toggle" then
        local player = game.get_player(event.player_index)
        if player then
            storage.gui_collapsed = storage.gui_collapsed or {}
            storage.gui_collapsed[player.index] = not is_gui_collapsed(player)
            M.build_platforms_gui(player)
        end
        return true
    end

    -- GPS ping button: print a colored GPS tag to the player's chat
    if element.tags and element.tags.sb_gps then
        local player = game.get_player(event.player_index)
        if player then
            local label = element.tags.sb_gps_label or ""
            local gps = element.tags.sb_gps
            if element.tags.sb_gps_type == "player" then
                -- Player pings use the player's chat color
                local color = element.tags.sb_gps_color or "1,1,1"
                player.print("[color=" .. color .. "]" .. label .. "[/color] " .. gps)
            else
                -- Platform pings use neutral grey
                player.print("[color=0.7,0.7,0.7]" .. label .. "[/color] " .. gps)
            end
        end
        return true
    end

    return false
end

--- Handle friend checkbox toggle. Each player independently controls
--- their own force's friendship toward another force (one-directional).
function M.on_friend_toggle(event)
    local element = event.element
    if not element or not element.valid then return end
    if not (element.tags and element.tags.sb_friend_toggle) then return end

    local player = game.get_player(event.player_index)
    if not player then return end

    local target_force = game.forces[element.tags.sb_target_force]
    if not target_force then return end

    local new_state = element.state
    player.force.set_friend(target_force, new_state)

    M.build_platforms_gui(player)
end

return M
