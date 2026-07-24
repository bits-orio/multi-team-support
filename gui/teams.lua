-- gui/teams.lua
-- Teams GUI: panel building, click handlers, friend toggle, nav.

local nav           = require("gui.nav")
local spectator     = require("scripts.spectator")
local helpers       = require("scripts.helpers")
local admin_gui     = require("gui.admin")
local landing_pen   = require("gui.landing_pen")
local follow_cam    = require("gui.follow_cam")
local friendship    = require("gui.friendship")
local teams_data    = require("gui.teams_data")
local team_card     = require("gui.team_card")
local team_pins     = require("scripts.team_pins")

local teams_gui = {}

-- Re-export public data helper so callers keep the same API.
teams_gui.get_platforms_by_owner = teams_data.get_platforms_by_owner

-- ─── GUI Building ──────────────────────────────────────────────────────

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

    frame.style.maximal_height = 900
    frame.style.minimal_width  = 360
    frame.style.maximal_width  = 400

    local show_offline = helpers.show_offline(player)
    helpers.add_show_offline_checkbox(frame, player)

    local scroll = frame.add{
        type = "scroll-pane",
        name = "sb_platforms_scroll",
        direction = "vertical",
        horizontal_scroll_policy = "never",
        vertical_scroll_policy   = "auto-and-reserve-space",
    }
    scroll.style.maximal_height           = 820
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

    if element.tags and element.tags.sb_pin_toggle then
        local player = game.get_player(event.player_index)
        local target = element.tags.target_idx and game.get_player(element.tags.target_idx)
        if player and target then
            team_pins.toggle(player, target)
            teams_gui.build_gui(player)
        end
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
