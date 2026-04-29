-- Multi-Team Support - research_gui.lua
-- Author: bits-orio
-- License: MIT
--
-- Research comparison panel.
--
-- OVERVIEW MODE (default)
--   One block per player force. Header shows player name (colored),
--   research count, play time, and expand/collapse button.
--   Collapsed (default): single row of tech icons.
--   Expanded: all icons flow in a table sized to the frame width.
--
--   Clicking a tech icon opens that technology in the tech tree.
--   Clicking the diff button on another player's header opens diff mode.
--
-- DIFF MODE  (click diff button on a player header)
--   Shows:
--     - Context line: who started earlier and by how much
--     - "You both have researched" - shared techs
--     - "<player> has, you don't" - ordered by their research timestamp
--     - "You have, <player> doesn't" - ordered by your research timestamp
--     - Infinite tech level differences (label rows)
--     - [Back] button returns to overview
--
--   Pressing Escape in diff mode returns to overview.
--
-- Storage used (read-only here; written by control.lua):
--   storage.player_clock_start[player_index] = game.tick of first real spawn
--   storage.tech_research_ticks[force_name][tech_name] = game.tick researched

local nav           = require("gui.nav")
local helpers       = require("scripts.helpers")
local research_diff = require("gui.research_diff")

local research_gui = {}

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

local NAV_BTN    = "sb_research_btn"
local FRAME_NAME = "sb_research_frame"
local FRAME_W    = 560
local FRAME_H    = 580

-- Number of icon columns for a single collapsed row (fits ~460px content area)
local COLLAPSED_COLS = 12

-- ---------------------------------------------------------------------------
-- Per-player GUI state
-- ---------------------------------------------------------------------------

-- storage.research_gui_expanded[viewer_index][owner_name] = true/false
-- storage.research_gui_diff_target[viewer_index] = owner_name or nil

local function get_expanded(viewer_index, owner)
    local t = (storage.research_gui_expanded or {})[viewer_index]
    return t and t[owner] or false
end

local function set_expanded(viewer_index, owner, state)
    storage.research_gui_expanded = storage.research_gui_expanded or {}
    storage.research_gui_expanded[viewer_index] = storage.research_gui_expanded[viewer_index] or {}
    storage.research_gui_expanded[viewer_index][owner] = state
end

local function get_diff_target(viewer_index)
    return (storage.research_gui_diff_target or {})[viewer_index]
end

local function set_diff_target(viewer_index, target)
    storage.research_gui_diff_target = storage.research_gui_diff_target or {}
    storage.research_gui_diff_target[viewer_index] = target
end

-- ---------------------------------------------------------------------------
-- Time formatting
-- ---------------------------------------------------------------------------

--- Format play time since spawn (elapsed from clock_start to now).
local function fmt_play_time(clock_tick)
    if not clock_tick then return "not yet spawned" end
    local elapsed = game.tick - clock_tick
    if elapsed < 0 then elapsed = 0 end
    return research_diff.fmt_duration(elapsed) .. " playing"
end

-- ---------------------------------------------------------------------------
-- Tech data helpers
-- ---------------------------------------------------------------------------

--- Return sorted list of researched techs for a force.
--- Each entry: { name, localised, tick, order }
--- Sorted by tick ascending; techs with no tick appended last by tech.order.
local function get_researched(force)
    local ticks   = research_diff.force_ticks(force)
    local stamped = {}
    local unstamp = {}
    for name, tech in pairs(force.technologies) do
        if tech.researched then
            local t = ticks[name]
            if t then
                stamped[#stamped + 1] = {name = name, localised = tech.localised_name, tick = t, order = tech.order}
            else
                unstamp[#unstamp + 1] = {name = name, localised = tech.localised_name, tick = nil, order = tech.order}
            end
        end
    end
    table.sort(stamped,  function(a, b) return a.tick  < b.tick  end)
    table.sort(unstamp,  function(a, b) return a.order < b.order end)
    for _, v in ipairs(unstamp) do stamped[#stamped + 1] = v end
    return stamped
end

-- ---------------------------------------------------------------------------
-- Player block helpers (overview)
-- ---------------------------------------------------------------------------

--- Derive the owner name and force from the same logic as surfaces_gui.
--- Returns an ordered list of { owner, force, color, online, clock_start }.
local function get_player_forces()
    local result = {}
    local seen   = {}
    for _, force in pairs(game.forces) do
        if force.name:find("^team%-") then
            local force_name = force.name
            if not seen[force_name] then
                seen[force_name] = true
                -- Skip teams with no players (unoccupied slots)
                -- Skip unoccupied slots (use team_pool since spectating members
                -- temporarily move off their team force).
                local slot = tonumber(force_name:match("^team%-(%d+)$"))
                local occupied = slot and (storage.team_pool or {})[slot] == "occupied"
                if not occupied then goto next_force end
                local owner = helpers.display_name(force_name)
                local color = helpers.force_color(force)
                local online = #force.connected_players > 0
                -- Use team clock instead of player clock for research timing
                local clock_start = (storage.team_clock_start or {})[force_name]
                result[#result + 1] = {
                    owner        = owner,
                    force_name   = force_name,  -- internal force name for lookups
                    force        = force,
                    color        = color,
                    online       = online,
                    clock_start  = clock_start,
                }
                ::next_force::
            end
        end
    end
    table.sort(result, function(a, b)
        local ca = a.clock_start or math.huge
        local cb = b.clock_start or math.huge
        if ca ~= cb then return ca < cb end
        return a.owner < b.owner
    end)
    return result
end

-- ---------------------------------------------------------------------------
-- Overview mode
-- ---------------------------------------------------------------------------

local function draw_overview(content_frame, viewer_force, viewer_clock, viewer_player)
    local forces = get_player_forces()

    if #forces == 0 then
        content_frame.add{type = "label", caption = "No players found."}
        return
    end

    local own_force_name = viewer_force.name
    local own_owner      = helpers.display_name(viewer_force.name)
    local show_offline = helpers.show_offline(viewer_player)
    local viewer_index = viewer_player.index

    for _, info in ipairs(forces) do
        -- Skip offline teams unless it's the viewer's team or show_offline is on
        if not info.online and info.force_name ~= own_force_name and not show_offline then
            goto continue
        end

        local techs    = get_researched(info.force)
        local expanded = get_expanded(viewer_index, info.force_name)

        -- Section frame per player
        local section = content_frame.add{
            type      = "frame",
            direction = "vertical",
            style     = "inside_shallow_frame",
        }
        section.style.horizontally_stretchable = true
        section.style.margin  = 4
        section.style.padding = 6

        -- Header row: bullet + name + count + play time + diff btn + expand btn
        local hdr = section.add{type = "flow", direction = "horizontal"}
        hdr.style.vertical_align = "center"

        -- Bullet
        local bullet = hdr.add{type = "label", caption = "\xE2\x97\x8F"}
        bullet.style.font_color   = info.online and info.color or {0.45, 0.45, 0.45}
        bullet.style.right_margin = 4

        -- Name
        local name_lbl = hdr.add{type = "label", caption = info.owner}
        name_lbl.style.font       = "default-bold"
        name_lbl.style.font_color = info.online and info.color or {0.65, 0.65, 0.65}
        if not info.online then
            local off = hdr.add{type = "label", caption = " (offline)"}
            off.style.font       = "default-small"
            off.style.font_color = {0.45, 0.45, 0.45}
        end

        -- Research count
        local count_lbl = hdr.add{type = "label", caption = "  [" .. #techs .. "]"}
        count_lbl.style.font       = "default-small"
        count_lbl.style.font_color = {0.7, 0.7, 0.7}

        -- Spacer
        local spacer = hdr.add{type = "empty-widget"}
        spacer.style.horizontally_stretchable = true

        -- Play time
        local start_lbl = hdr.add{type = "label", caption = fmt_play_time(info.clock_start)}
        start_lbl.style.font       = "default-small"
        start_lbl.style.font_color = {0.6, 0.8, 0.6}

        -- Diff button (for other teams)
        if info.force_name ~= own_force_name then
            local diff_btn = hdr.add{
                type    = "sprite-button",
                sprite  = "utility/search_icon",
                style   = "mini_button",
                tooltip = "Compare: you vs " .. info.owner,
                tags    = {sb_research_diff_target = info.force_name},
            }
            diff_btn.style.left_margin = 4
        end

        -- Expand/collapse button (double chevron: » down = expand, « up = collapse)
        if #techs > COLLAPSED_COLS then
            local toggle_btn = hdr.add{
                type    = "button",
                caption = expanded and "\xE2\x96\xB2\xE2\x96\xB2" or "\xE2\x96\xBC\xE2\x96\xBC",
                style   = "tool_button",
                tooltip = expanded and "Collapse" or "Expand all " .. #techs .. " technologies",
                tags    = {sb_research_expand_toggle = info.force_name},
            }
            toggle_btn.style.width       = 28
            toggle_btn.style.height      = 28
            toggle_btn.style.left_margin = 4
            toggle_btn.style.font        = "default-bold"
        end

        -- Separator
        section.add{type = "line"}.style.top_margin = 2

        -- Tech icon grid
        if #techs == 0 then
            local none = section.add{type = "label", caption = "(no research yet)"}
            none.style.font_color = {0.5, 0.5, 0.5}
            none.style.top_margin = 2
        else
            local cols = COLLAPSED_COLS
            local display_techs = techs
            if not expanded and #techs > COLLAPSED_COLS then
                display_techs = {}
                for i = 1, COLLAPSED_COLS do
                    display_techs[i] = techs[i]
                end
            end

            local grid = section.add{type = "table", column_count = cols}
            grid.style.horizontal_spacing = 0
            grid.style.vertical_spacing   = 0
            grid.style.top_margin         = 2

            research_diff.add_tech_icons(grid, display_techs, info.clock_start)
        end
        ::continue::
    end
end

-- ---------------------------------------------------------------------------
-- Frame construction
-- ---------------------------------------------------------------------------

local function build_frame(player, diff_target)
    storage.research_gui_location = storage.research_gui_location or {}
    local frame = helpers.reuse_or_create_frame(
        player, FRAME_NAME, storage.research_gui_location, {x = 300, y = 100})

    frame.style.width  = FRAME_W
    frame.style.height = FRAME_H

    -- Persist diff target for Escape handling
    set_diff_target(player.index, diff_target)

    -- diff_target is a force name (e.g. "team-1"), convert to display name for caption
    local diff_display = diff_target and helpers.display_name(diff_target) or nil
    local caption = diff_display and ("Research: You vs " .. diff_display) or "Research"
    local title_bar = helpers.add_title_bar(frame, caption)
    title_bar.add{
        type    = "sprite-button",
        name    = "sb_research_close",
        sprite  = "utility/close",
        style   = "close_button",
        tooltip = "Close",
    }

    helpers.add_show_offline_checkbox(frame, player)

    -- Scroll pane for content
    local scroll = frame.add{
        type = "scroll-pane",
        name = "sb_research_scroll",
        direction = "vertical",
        vertical_scroll_policy = "auto-and-reserve-space",
        horizontal_scroll_policy = "never",
    }
    scroll.style.horizontally_stretchable = true
    scroll.style.vertically_stretchable   = true

    local viewer_force = player.force
    local viewer_clock = (storage.player_clock_start or {})[player.index]

    if diff_target then
        research_diff.draw(scroll, viewer_force, viewer_clock, diff_target, COLLAPSED_COLS)
    else
        draw_overview(scroll, viewer_force, viewer_clock, player)
    end

    -- Allow Esc to navigate back from diff or close
    player.opened = frame
end

-- ---------------------------------------------------------------------------
-- Toggle
-- ---------------------------------------------------------------------------

function research_gui.toggle(player)
    if player.gui.screen[FRAME_NAME] then
        storage.research_gui_location = storage.research_gui_location or {}
        storage.research_gui_location[player.index] = player.gui.screen[FRAME_NAME].location
        player.gui.screen[FRAME_NAME].destroy()
    else
        build_frame(player, nil)
    end
end

-- ---------------------------------------------------------------------------
-- Click handler
-- ---------------------------------------------------------------------------

function research_gui.on_gui_click(event)
    local el = event.element
    if not (el and el.valid) then return false end

    -- Close button
    if el.name == "sb_research_close" then
        local player = event.player or game.get_player(event.player_index)
        if player then research_gui.toggle(player) end
        return true
    end

    -- Back button (diff -> overview)
    if el.name == "sb_research_back" then
        local player = event.player or game.get_player(event.player_index)
        if player then build_frame(player, nil) end
        return true
    end

    -- Diff button (sb_research_diff_target tag)
    if el.tags and el.tags.sb_research_diff_target then
        local player = event.player or game.get_player(event.player_index)
        if player then build_frame(player, el.tags.sb_research_diff_target) end
        return true
    end

    -- Expand/collapse toggle
    if el.tags and el.tags.sb_research_expand_toggle then
        local player = event.player or game.get_player(event.player_index)
        if player then
            local owner = el.tags.sb_research_expand_toggle
            set_expanded(player.index, owner, not get_expanded(player.index, owner))
            build_frame(player, nil)
        end
        return true
    end

    -- Tech icon click -> open tech tree
    if el.tags and el.tags.sb_research_open_tech then
        local player = event.player or game.get_player(event.player_index)
        if player then
            player.open_technology_gui(el.tags.sb_research_open_tech)
        end
        return true
    end

    return false
end

-- ---------------------------------------------------------------------------
-- Escape handler (called from control.lua on_gui_closed)
-- ---------------------------------------------------------------------------

--- Handle Escape key on the research frame.
--- If in diff mode: go back to overview.
--- If any player section is expanded: collapse all.
--- Otherwise: close the frame.
--- Returns true if the event was consumed.
function research_gui.on_gui_closed(event)
    local player = game.get_player(event.player_index)
    if not player then return false end
    local frame = player.gui.screen[FRAME_NAME]
    if not (frame and frame.valid) then return false end
    -- Check if Factorio is closing our frame
    if event.element ~= frame then return false end

    -- If in diff mode, go back to overview
    local diff_target = get_diff_target(player.index)
    if diff_target then
        build_frame(player, nil)
        return true
    end

    -- If any section is expanded, collapse all
    local had_expanded = false
    local expanded_map = (storage.research_gui_expanded or {})[player.index]
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

    -- Otherwise close the frame
    storage.research_gui_location[player.index] = frame.location
    frame.destroy()
    return true
end

-- ---------------------------------------------------------------------------
-- Refresh for open panels
-- ---------------------------------------------------------------------------

function research_gui.update_all()
    for _, player in pairs(game.players) do
        if player.connected and player.gui.screen[FRAME_NAME] then
            local diff_target = get_diff_target(player.index)
            build_frame(player, diff_target)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Nav bar registration
-- ---------------------------------------------------------------------------

function research_gui.on_player_created(player)
    nav.add_top_button(player, {
        name    = NAV_BTN,
        sprite  = "item/lab",
        tooltip = "Research Comparison",
    })
end

-- Register click handler at module load (desync-safe, fires on every script load).
nav.on_click(NAV_BTN, function(e)
    research_gui.toggle(e.player)
end)

return research_gui
