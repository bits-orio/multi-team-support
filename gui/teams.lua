-- gui/teams.lua
-- Teams GUI: panel building, click handlers, friend toggle, nav.

local nav           = require("gui.nav")
local spectator     = require("scripts.spectator")
local helpers       = require("scripts.helpers")
local surface_utils = require("scripts.surface_utils")
local admin_gui     = require("gui.admin")
local landing_pen   = require("gui.landing_pen")
local follow_cam    = require("gui.follow_cam")
local friendship    = require("gui.friendship")
local teams_data    = require("gui.teams_data")
local team_card     = require("gui.team_card")

local teams_gui = {}

-- Re-export public data helper so callers keep the same API.
teams_gui.get_platforms_by_owner = teams_data.get_platforms_by_owner

-- ─── GUI Building ──────────────────────────────────────────────────────

local function add_footer(frame, player, viewer_force)
    local in_pen  = landing_pen.is_in_pen(player)
    local is_spec = spectator.is_spectating(player)

    if in_pen then
        if not is_spec then return end
    else
        if not viewer_force then return end

        -- Non-spectator: show only when on a surface not owned by their own team.
        -- Own surfaces (planets, platforms) omit the button to avoid bypassing
        -- cargo-pod travel mechanics.
        if not is_spec then
            local owner = surface_utils.get_owner(player.surface)
            if owner == viewer_force.name then return end
        end

        local return_surface = surface_utils.get_home_surface(viewer_force, player.index)
        if not return_surface then return end
    end

    -- player.crafting_queue_size errors when no crafting queue exists;
    -- guard on player.character before reading it.
    local crafting = is_spec and player.character and player.crafting_queue_size > 0

    local caption = "Exit remote view"
    if is_spec and crafting then caption = "Exit remote view (crafting paused)" end

    local tooltip
    if in_pen then
        tooltip = "Exit remote view and return to the Landing Pen"
    elseif is_spec then
        tooltip = "Exit remote view and return to your base"
    else
        tooltip = "Teleport back to your base"
    end

    local footer = frame.add{type = "flow", direction = "horizontal"}
    footer.style.top_margin              = 4
    footer.style.horizontal_align        = "center"
    footer.style.horizontally_stretchable = true
    footer.add{
        type    = "button",
        name    = "sb_return_to_base",
        caption = caption,
        style   = "button",
        tooltip = tooltip,
    }
end

function teams_gui.build_gui(player)
    storage.gui_location = storage.gui_location or {}
    local frame = helpers.reuse_or_create_frame(
        player, "sb_platforms_frame", storage.gui_location, {x = 5, y = 400})

    local title_bar = helpers.add_title_bar(frame, "Teams")
    title_bar.style.horizontal_spacing = 8
    title_bar.add{
        type    = "sprite-button",
        name    = "sb_platforms_close",
        sprite  = "utility/close",
        style   = "close_button",
        tooltip = "Close panel",
    }

    frame.style.maximal_height = 600
    frame.style.minimal_width  = 480
    frame.style.maximal_width  = 560

    local show_offline = helpers.show_offline(player)
    helpers.add_show_offline_checkbox(frame, player)

    local scroll = frame.add{
        type = "scroll-pane",
        name = "sb_platforms_scroll",
        direction = "vertical",
        horizontal_scroll_policy = "never",
        vertical_scroll_policy   = "auto-and-reserve-space",
    }
    scroll.style.maximal_height           = 520
    scroll.style.horizontally_stretchable = true

    local viewer_force_name = spectator.get_effective_force(player)
    local viewer_force      = game.forces[viewer_force_name]
    local current_target    = spectator.get_target(player)

    -- Own team first, then sorted by name. Uses team_pool occupancy so
    -- spectating members don't make their team card disappear.
    local team_forces = {}
    for _, force in pairs(game.forces) do
        if not teams_data.SKIP_FORCES[force.name] and teams_data.is_team_occupied(force.name) then
            team_forces[#team_forces + 1] = force
        end
    end
    table.sort(team_forces, function(a, b)
        if a.name == viewer_force_name then return true end
        if b.name == viewer_force_name then return false end
        return a.name < b.name
    end)

    local visible_count = 0
    for _, force in ipairs(team_forces) do
        local is_own = (force.name == viewer_force_name)
        local online = helpers.team_has_online_member(force.name)
        if online or is_own or show_offline then
            visible_count = visible_count + 1
            team_card.build_team_card(scroll, force, player, viewer_force_name, current_target)
        end
    end

    if visible_count == 0 then
        local none = scroll.add{type = "label", caption = "No teams yet."}
        none.style.font_color = {0.7, 0.7, 0.7}
    end

    add_footer(frame, player, viewer_force)
end

function teams_gui.update_all()
    for _, player in pairs(game.players) do
        if player.connected and player.gui.screen.sb_platforms_frame then
            teams_gui.build_gui(player)
        end
    end
end

-- Re-export in-place updaters so events/ticks.lua keeps its existing calls.
teams_gui.update_activity_labels_all  = team_card.update_activity_labels_all
teams_gui.update_queue_progress_all   = team_card.update_queue_progress_all

-- ─── Click Handlers ────────────────────────────────────────────────────

local function on_return_to_base(player)
    if spectator.is_spectating(player) then
        spectator.exit(player)
        -- Rebuild immediately so the button disappears on the first click,
        -- confirming to the player that the exit actually worked.
        teams_gui.build_gui(player)
        return
    end
    local saved = storage.spectator_saved_location
        and storage.spectator_saved_location[player.index]
    local target_surface, target_pos
    if saved then
        target_surface = game.surfaces[saved.surface_name]
        target_pos     = saved.position
        storage.spectator_saved_location[player.index] = nil
    end
    if not target_surface then
        target_surface = surface_utils.get_home_surface(player.force, player.index)
        target_pos     = helpers.ORIGIN
    end
    if target_surface then
        if player.character then
            local safe = target_surface.find_non_colliding_position(
                player.character.name, target_pos, 8, 0.5)
            target_pos = safe or target_pos
        end
        helpers.diag("teams_gui.on_return_to_base: TELEPORT → " .. target_surface.name, player)
        player.teleport(target_pos, target_surface)
    end
end

local function on_spectate_click(player, tags)
    local target_force = game.forces[tags.sb_target_force]
    local surface      = game.surfaces[tags.sb_surface]
    local position     = tags.sb_position or helpers.ORIGIN
    if not (target_force and surface) then return end

    local leader_idx = (storage.team_leader or {})[target_force.name]
    local leader = leader_idx and game.get_player(leader_idx)
    if leader and leader.connected and leader.surface == surface then
        position = leader.position
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

local function on_follow_cam_toggle(player, tags)
    if not tags.target_idx then return end
    follow_cam.toggle_target(player, tags.target_idx)
    teams_gui.build_gui(player)
end

function teams_gui.on_gui_click(event)
    local element = event.element
    if not element or not element.valid then return end

    if element.name == "sb_return_to_base" then
        local player = game.get_player(event.player_index)
        if player then on_return_to_base(player) end
        return true
    end

    if element.name == "sb_platforms_close" then
        local player = game.get_player(event.player_index)
        if player then teams_gui.toggle(player) end
        return true
    end

    if element.tags and element.tags.sb_spectate then
        local player = game.get_player(event.player_index)
        if player then on_spectate_click(player, element.tags) end
        return true
    end

    if element.tags and element.tags.sb_follow_cam_toggle then
        local player = game.get_player(event.player_index)
        if player then on_follow_cam_toggle(player, element.tags) end
        return true
    end

    return false
end

-- ─── Friend Toggle ─────────────────────────────────────────────────────

function teams_gui.on_friend_toggle(event)
    if not admin_gui.flag("friendship_enabled") then return end
    local player = game.get_player(event.player_index)
    if not player or landing_pen.is_in_pen(player) then return end
    if friendship.on_toggle(event) then
        teams_gui.update_all()
    end
end

-- ─── Panel Toggle & Nav ────────────────────────────────────────────────

function teams_gui.toggle(player)
    local frame = player.gui.screen.sb_platforms_frame
    if frame then
        storage.gui_location = storage.gui_location or {}
        storage.gui_location[player.index] = frame.location
        frame.destroy()
    else
        teams_gui.build_gui(player)
    end
end

function teams_gui.on_player_created(player)
    nav.add_top_button(player, {
        name    = "sb_platforms_btn",
        sprite  = "utility/gps_map_icon",
        tooltip = "Teams",
    })
end

nav.on_click("sb_platforms_btn", function(e)
    teams_gui.toggle(e.player)
end)

return teams_gui
