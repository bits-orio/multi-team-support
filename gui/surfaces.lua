-- Solo Teams - surfaces_gui.lua
-- Author: bits-orio
-- License: MIT
--
-- Draggable, collapsible GUI overlay that shows all players and their
-- platforms. Includes spectate buttons and per-player friend toggle
-- checkboxes with mutual friendship semantics.

local nav           = require("gui.nav")
local spectator     = require("spectator")
local helpers       = require("helpers")
local surface_utils = require("surface_utils")
local friendship    = require("gui.friendship")
local admin_gui     = require("gui.admin")
local landing_pen   = require("gui.landing_pen")

local surfaces_gui = {}

-- ─── GPS Helpers ───────────────────────────────────────────────────────

--- Build a Factorio rich-text GPS tag for a platform's hub location.
local function get_platform_gps(platform)
    local hub = platform.hub
    if not (hub and hub.valid and platform.surface) then return "" end
    local pos = hub.position
    return string.format("[gps=%d,%d,%s]", pos.x, pos.y, platform.surface.name)
end

--- Build a Factorio rich-text GPS tag for a player's current position.
local function get_player_gps(player)
    if not (player and player.valid and player.connected and player.surface) then return "" end
    local pos = player.position
    return string.format("[gps=%d,%d,%s]", pos.x, pos.y, player.surface.name)
end

-- ─── Data Collection ───────────────────────────────────────────────────

--- Build a single owner entry for a force that has space platforms.
local function collect_platform_owner(force)
    local owner = helpers.display_name(force.name)
    local platforms = {}
    for _, platform in pairs(force.platforms) do
        local location = platform.space_location and platform.space_location.name or "in transit"
        local hub = platform.hub
        local hub_pos = (hub and hub.valid) and hub.position or nil
        platforms[#platforms + 1] = {
            name         = platform.name,
            location     = location,
            gps          = get_platform_gps(platform),
            surface_name = platform.surface and platform.surface.name or nil,
            position     = hub_pos and {x = hub_pos.x, y = hub_pos.y} or helpers.ORIGIN,
        }
    end
    local owner_player = game.get_player(owner)
    local online = owner_player and owner_player.connected or false
    local info = {
        gps        = online and get_player_gps(owner_player) or "",
        color      = online and owner_player.chat_color or helpers.WHITE,
        force_name = force.name,
        online     = online,
    }
    return owner, platforms, info
end

--- Build a single owner entry for a vanilla surface player.
local function collect_vanilla_owner(player, ps)
    local surface = game.surfaces[ps.name]
    if not (surface and surface.valid) then return nil end
    local owner = player.name
    local planet_disp = ps.planet:sub(1, 1):upper() .. ps.planet:sub(2)
    local platforms = {{
        name         = owner .. "'s base on " .. planet_disp,
        location     = planet_disp,
        gps          = string.format("[gps=0,0,%s]", ps.name),
        surface_name = ps.name,
        position     = helpers.ORIGIN,
    }}
    local info = {
        gps        = get_player_gps(player),
        color      = player.chat_color,
        force_name = spectator.get_effective_force(player),
        online     = player.connected,
    }
    return owner, platforms, info
end

local SKIP_FORCES = {enemy = true, neutral = true, player = true, spectator = true}

--- Collect all platforms grouped by owner (player name).
--- Returns three tables: owners, order, owner_info.
function surfaces_gui.get_platforms_by_owner()
    local owners     = {}
    local owner_info = {}
    local order      = {}

    -- Space platform forces
    for _, force in pairs(game.forces) do
        if not SKIP_FORCES[force.name] then
            local has_platforms = false
            for _ in pairs(force.platforms) do has_platforms = true; break end
            if has_platforms then
                local owner, platforms, info = collect_platform_owner(force)
                owners[owner]     = platforms
                owner_info[owner] = info
                order[#order + 1] = owner
            end
        end
    end

    -- Vanilla surfaces (only if no platform entry exists for this player)
    local player_surfaces = storage.player_surfaces or {}
    for _, p in pairs(game.players) do
        local ps = player_surfaces[p.index]
        if ps and not owners[p.name] then
            local owner, platforms, info = collect_vanilla_owner(p, ps)
            if owner then
                owners[owner]     = platforms
                owner_info[owner] = info
                order[#order + 1] = owner
            end
        end
    end

    return owners, order, owner_info
end

-- ─── GUI Building ──────────────────────────────────────────────────────

local function is_gui_collapsed(player)
    storage.gui_collapsed = storage.gui_collapsed or {}
    return storage.gui_collapsed[player.index] or false
end

--- Add the owner name row (col 1) to the table.
local function add_owner_label(tbl, owner, info)
    local owner_flow  = tbl.add{type = "flow", direction = "horizontal"}
    local owner_label = owner_flow.add{type = "label", caption = owner}
    owner_label.style.font = "default-bold"
    if info.online then
        owner_label.style.font_color = info.color
    else
        owner_label.style.font_color = {0.65, 0.65, 0.65}
        local off_lbl = owner_flow.add{type = "label", caption = " (offline)"}
        off_lbl.style.font       = "default-small"
        off_lbl.style.font_color = {0.45, 0.45, 0.45}
    end
end

--- Add the friend checkbox (col 2) to the table.
--- Hidden entirely when friendship is disabled via admin flag.
local function add_friend_checkbox(tbl, viewer_force_name, viewer_force, target_force_name, owner, viewer_player)
    if target_force_name == viewer_force_name
       or not admin_gui.flag("friendship_enabled")
       or landing_pen.is_in_pen(viewer_player) then
        tbl.add{type = "label", caption = ""}
        return
    end
    local target_force = game.forces[target_force_name]
    if not (viewer_force and target_force) then
        tbl.add{type = "label", caption = ""}
        return
    end

    local lbl_text, lbl_color, tip, checked =
        friendship.get_state(viewer_force_name, target_force_name, viewer_force, target_force, owner)

    local friend_flow = tbl.add{type = "flow", direction = "horizontal"}
    friend_flow.style.horizontal_align = "right"
    friend_flow.style.horizontally_stretchable = true
    local friend_label = friend_flow.add{type = "label", caption = lbl_text}
    friend_label.style.font       = "default-small"
    friend_label.style.font_color = lbl_color
    friend_label.style.right_margin = 4
    friend_flow.add{
        type    = "checkbox",
        state   = checked,
        tags    = {sb_friend_toggle = true, sb_target_force = target_force_name},
        tooltip = tip,
    }
end

--- Add platform/surface rows with optional spectate buttons.
local function add_platform_rows(tbl, platforms, target_force_name, owner, is_own, is_current_target)
    for _, info in ipairs(platforms) do
        local plat_flow  = tbl.add{type = "flow", direction = "horizontal"}
        local plat_label = plat_flow.add{type = "label", caption = "  " .. info.name}
        plat_label.style.font = "default-small"
        if not is_own and not is_current_target and info.surface_name then
            plat_flow.add{
                type    = "sprite-button",
                sprite  = "utility/search_icon",
                tags    = {
                    sb_spectate     = true,
                    sb_target_force = target_force_name,
                    sb_surface      = info.surface_name,
                    sb_position     = info.position,
                },
                style   = "mini_button",
                tooltip = "Spectate " .. owner .. "'s " .. info.name,
            }
        end
        local loc_label = tbl.add{type = "label", caption = info.location}
        loc_label.style.font = "default-small"
    end
end

--- Find the player's home surface (delegates to surface_utils).
local function get_home_surface(force, player_index)
    return surface_utils.get_home_surface(force, player_index)
end

--- Add the footer with return/stop-spectating button.
local function add_footer(frame, player, viewer_force)
    if not viewer_force then return end
    local return_surface = get_home_surface(viewer_force, player.index)
    if not return_surface then return end
    if player.surface.index == return_surface.index then return end

    local is_spec  = spectator.is_spectating(player)
    local crafting = is_spec and player.crafting_queue_size > 0
    local caption
    if is_spec then
        caption = crafting and "Stop spectating (crafting paused)" or "Stop spectating"
    else
        caption = "Return to my base"
    end
    local tooltip = is_spec and "Stop spectating and return to your base"
                             or "Teleport back to your space platform"

    local footer = frame.add{type = "flow", direction = "horizontal"}
    footer.style.top_margin = 4
    footer.style.horizontal_align = "center"
    footer.style.horizontally_stretchable = true
    footer.add{
        type    = "button",
        name    = "sb_return_to_base",
        caption = caption,
        style   = "button",
        tooltip = tooltip,
    }
end

--- Build (or rebuild) the platforms GUI for a single player.
function surfaces_gui.build_surfaces_gui(player)
    storage.gui_location = storage.gui_location or {}
    local frame = helpers.reuse_or_create_frame(
        player, "sb_platforms_frame", storage.gui_location, {x = 5, y = 400})

    local collapsed = is_gui_collapsed(player)
    local title_bar = helpers.add_title_bar(frame, "Players")
    title_bar.style.horizontal_spacing = 8
    title_bar.add{
        type    = "sprite-button",
        name    = "sb_platforms_toggle",
        caption = collapsed and "+" or "-",
        style   = "close_button",
        tooltip = collapsed and "Show players" or "Hide players",
    }
    if collapsed then return end

    frame.style.maximal_height = 400
    frame.style.minimal_width  = 320

    local show_offline = helpers.show_offline(player)

    -- "Show offline" toggle
    local offline_flow = frame.add{type = "flow", direction = "horizontal"}
    offline_flow.style.horizontal_align = "right"
    offline_flow.style.horizontally_stretchable = true
    offline_flow.style.bottom_margin = 2
    local offline_label = offline_flow.add{type = "label", caption = "show offline"}
    offline_label.style.font       = "default-small"
    offline_label.style.font_color = {0.6, 0.6, 0.6}
    offline_label.style.right_margin = 4
    offline_flow.add{
        type    = "checkbox",
        name    = "sb_show_offline_toggle",
        state   = show_offline,
        tooltip = show_offline and "Hide offline players" or "Show offline players",
    }

    local scroll = frame.add{type = "scroll-pane", name = "sb_platforms_scroll", direction = "vertical"}
    scroll.style.maximal_height = 350

    local tbl = scroll.add{type = "table", name = "sb_platforms_table", column_count = 2}
    tbl.style.horizontal_spacing = 12
    tbl.style.vertical_spacing   = 2

    local viewer_force_name = spectator.get_effective_force(player)
    local viewer_force      = game.forces[viewer_force_name]
    local current_target    = spectator.get_target(player)
    local visible_count     = 0

    local owners, order, owner_info = surfaces_gui.get_platforms_by_owner()
    for _, owner in ipairs(order) do
        local info             = owner_info[owner]
        local target_force_name = info.force_name
        local is_own            = (target_force_name == viewer_force_name)
        local is_current_target = (target_force_name == current_target)

        if info.online or is_own or show_offline then
            visible_count = visible_count + 1
            add_owner_label(tbl, owner, info)
            add_friend_checkbox(tbl, viewer_force_name, viewer_force, target_force_name, owner, player)
            add_platform_rows(tbl, owners[owner], target_force_name, owner, is_own, is_current_target)
        end
    end

    if visible_count == 0 then
        tbl.add{type = "label", caption = "No players yet."}
        tbl.add{type = "label", caption = ""}
    end

    add_footer(frame, player, viewer_force)
end

--- Rebuild the platforms GUI for all connected players.
function surfaces_gui.update_all()
    for _, player in pairs(game.players) do
        if player.connected and player.gui.screen.sb_platforms_frame then
            surfaces_gui.build_surfaces_gui(player)
        end
    end
end

-- ─── Click Handlers ────────────────────────────────────────────────────

--- Handle return-to-base click: exit spectation, then teleport home.
local function on_return_to_base(player)
    if spectator.is_spectating(player) then
        -- spectator.exit() handles restoring saved location
        spectator.exit(player)
        return
    end
    -- Friend-view or manual navigation: restore saved location or fall back to home origin
    local saved = storage.spectator_saved_location
        and storage.spectator_saved_location[player.index]
    local target_surface, target_pos
    if saved then
        target_surface = game.surfaces[saved.surface_name]
        target_pos     = saved.position
        storage.spectator_saved_location[player.index] = nil
    end
    if not target_surface then
        target_surface = get_home_surface(player.force, player.index)
        target_pos     = helpers.ORIGIN
    end
    if target_surface then
        if player.character then
            local safe = target_surface.find_non_colliding_position(
                player.character.name, target_pos, 8, 0.5)
            target_pos = safe or target_pos
        end
        player.teleport(target_pos, target_surface)
    end
end

--- Handle spectate button click.
local function on_spectate_click(player, tags)
    local target_force = game.forces[tags.sb_target_force]
    local surface      = game.surfaces[tags.sb_surface]
    local position     = tags.sb_position or helpers.ORIGIN
    if not (target_force and surface) then return end

    -- If the target player is on this surface, spectate their live position.
    -- If they're away (spectating someone else), use their saved pre-spectate position.
    local target_name = helpers.display_name(target_force.name)
    local target_player = game.get_player(target_name)
    if target_player and target_player.connected then
        if target_player.surface == surface then
            position = target_player.position
        else
            local saved = storage.spectator_saved_location
                and storage.spectator_saved_location[target_player.index]
            if saved and saved.surface_name == surface.name then
                position = saved.position
            end
        end
    end

    local viewer_force = game.forces[spectator.get_effective_force(player)]
    if not viewer_force then return end

    if spectator.needs_spectator_mode(viewer_force, target_force) then
        if spectator.is_spectating(player) then
            spectator.switch_target(player, target_force, surface, position)
        else
            spectator.enter(player, target_force, surface, position)
        end
    else
        spectator.enter_friend_view(player, surface, position)
    end
end

--- Handle GUI click events. Returns true if consumed.
function surfaces_gui.on_gui_click(event)
    local element = event.element
    if not element or not element.valid then return end

    if element.name == "sb_return_to_base" then
        local player = game.get_player(event.player_index)
        if player then on_return_to_base(player) end
        return true
    end

    if element.name == "sb_platforms_toggle" then
        local player = game.get_player(event.player_index)
        if player then
            storage.gui_collapsed = storage.gui_collapsed or {}
            storage.gui_collapsed[player.index] = not is_gui_collapsed(player)
            surfaces_gui.build_surfaces_gui(player)
        end
        return true
    end

    if element.tags and element.tags.sb_spectate then
        local player = game.get_player(event.player_index)
        if player then on_spectate_click(player, element.tags) end
        return true
    end

    return false
end

-- ─── Friend Toggle ─────────────────────────────────────────────────────

--- Handle friend checkbox toggle (delegates to gui.friendship).
--- No-ops when friendship is disabled via admin flag.
function surfaces_gui.on_friend_toggle(event)
    if not admin_gui.flag("friendship_enabled") then return end
    local player = game.get_player(event.player_index)
    if not player or landing_pen.is_in_pen(player) then return end
    if friendship.on_toggle(event) then
        surfaces_gui.update_all()
    end
end

-- ─── Panel Toggle & Nav ────────────────────────────────────────────────

--- Toggle the platforms panel open/closed for a player.
function surfaces_gui.toggle(player)
    local frame = player.gui.screen.sb_platforms_frame
    if frame then
        storage.gui_location = storage.gui_location or {}
        storage.gui_location[player.index] = frame.location
        frame.destroy()
    else
        surfaces_gui.build_surfaces_gui(player)
    end
end

--- Register the nav bar button for this player.
function surfaces_gui.on_player_created(player)
    nav.add_top_button(player, {
        name    = "sb_platforms_btn",
        sprite  = "utility/gps_map_icon",
        tooltip = "Players & Platforms",
    })
    nav.on_click("sb_platforms_btn", function(e)
        surfaces_gui.toggle(e.player)
    end)
end

return surfaces_gui
