-- gui/research.lua
-- Research comparison panel: frame shell, toggle, click/close handlers.
-- Data helpers and overview renderer live in gui/research_overview.lua.

local nav              = require("gui.nav")
local helpers          = require("scripts.helpers")
local research_diff    = require("gui.research_diff")
local research_overview = require("gui.research_overview")

local research_gui = {}

local NAV_BTN    = "sb_research_btn"
local FRAME_NAME = "sb_research_frame"
local FRAME_W    = 560
local FRAME_H    = 580

-- ─── Frame construction ───────────────────────────────────────────────

local function build_frame(player, diff_target)
    storage.research_gui_location = storage.research_gui_location or {}
    local frame = helpers.reuse_or_create_frame(
        player, FRAME_NAME, storage.research_gui_location, {x = 300, y = 100})

    frame.style.width  = FRAME_W
    frame.style.height = FRAME_H

    research_overview.set_diff_target(player.index, diff_target)

    local diff_display = diff_target and helpers.display_name(diff_target) or nil
    local caption      = diff_display and ("Research: You vs " .. diff_display) or "Research"
    local title_bar    = helpers.add_title_bar(frame, caption)
    title_bar.add{
        type    = "sprite-button",
        name    = "sb_research_close",
        sprite  = "utility/close",
        style   = "close_button",
        tooltip = "Close",
    }

    helpers.add_show_offline_checkbox(frame, player)

    local scroll = frame.add{
        type = "scroll-pane",
        name = "sb_research_scroll",
        direction = "vertical",
        vertical_scroll_policy   = "auto-and-reserve-space",
        horizontal_scroll_policy = "never",
    }
    scroll.style.horizontally_stretchable = true
    scroll.style.vertically_stretchable   = true

    local viewer_clock = (storage.player_clock_start or {})[player.index]
    if diff_target then
        research_diff.draw(scroll, player.force, viewer_clock, diff_target, 12)
    else
        research_overview.draw_overview(scroll, player.force, viewer_clock, player)
    end

    player.opened = frame
end

-- ─── Toggle ───────────────────────────────────────────────────────────

function research_gui.toggle(player)
    if player.gui.screen[FRAME_NAME] then
        storage.research_gui_location = storage.research_gui_location or {}
        storage.research_gui_location[player.index] = player.gui.screen[FRAME_NAME].location
        player.gui.screen[FRAME_NAME].destroy()
    else
        build_frame(player, nil)
    end
end

-- ─── Click handler ────────────────────────────────────────────────────

function research_gui.on_gui_click(event)
    local el = event.element
    if not (el and el.valid) then return false end

    if el.name == "sb_research_close" then
        local player = event.player or game.get_player(event.player_index)
        if player then research_gui.toggle(player) end
        return true
    end

    if el.name == "sb_research_back" then
        local player = event.player or game.get_player(event.player_index)
        if player then build_frame(player, nil) end
        return true
    end

    if el.tags and el.tags.sb_research_diff_target then
        local player = event.player or game.get_player(event.player_index)
        if player then build_frame(player, el.tags.sb_research_diff_target) end
        return true
    end

    if el.tags and el.tags.sb_research_expand_toggle then
        local player = event.player or game.get_player(event.player_index)
        if player then
            local owner = el.tags.sb_research_expand_toggle
            research_overview.set_expanded(player.index, owner,
                not research_overview.get_expanded(player.index, owner))
            build_frame(player, nil)
        end
        return true
    end

    if el.tags and el.tags.sb_research_open_tech then
        local player = event.player or game.get_player(event.player_index)
        if player then player.open_technology_gui(el.tags.sb_research_open_tech) end
        return true
    end

    return false
end

-- ─── Escape handler ───────────────────────────────────────────────────

--- Handle Escape on the research frame.
--- Diff mode → back to overview. Any expanded section → collapse all.
--- Otherwise → close.
function research_gui.on_gui_closed(event)
    local player = game.get_player(event.player_index)
    if not player then return false end
    local frame = player.gui.screen[FRAME_NAME]
    if not (frame and frame.valid) then return false end
    if event.element ~= frame then return false end

    local diff_target = research_overview.get_diff_target(player.index)
    if diff_target then
        build_frame(player, nil)
        return true
    end

    local had_expanded  = false
    local expanded_map  = (storage.research_gui_expanded or {})[player.index]
    if expanded_map then
        for owner, state in pairs(expanded_map) do
            if state then
                had_expanded = true
                expanded_map[owner] = false
            end
        end
    end
    if had_expanded then
        build_frame(player, nil)
        return true
    end

    storage.research_gui_location[player.index] = frame.location
    frame.destroy()
    return true
end

-- ─── Refresh ──────────────────────────────────────────────────────────

function research_gui.update_all()
    for _, player in pairs(game.players) do
        if player.connected and player.gui.screen[FRAME_NAME] then
            build_frame(player, research_overview.get_diff_target(player.index))
        end
    end
end

-- ─── Nav registration ─────────────────────────────────────────────────

function research_gui.on_player_created(player)
    nav.add_top_button(player, {
        name    = NAV_BTN,
        sprite  = "item/lab",
        tooltip = "Research Comparison",
    })
end

nav.on_click(NAV_BTN, function(e)
    research_gui.toggle(e.player)
end)

return research_gui
