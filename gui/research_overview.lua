-- gui/research_overview.lua
-- Data helpers and overview-mode renderer for the research comparison panel.
-- The frame shell, toggle, and click handlers live in gui/research.lua.

local helpers       = require("scripts.helpers")
local research_diff = require("gui.research_diff")
local team_clock    = require("scripts.team_clock")

local M = {}

local COLLAPSED_COLS = 12

-- ─── Per-player GUI state ─────────────────────────────────────────────
-- storage.research_gui_expanded[viewer_index][force_name] = bool
-- storage.research_gui_diff_target[viewer_index]          = force_name | nil

function M.get_expanded(viewer_index, force_name)
    local t = (storage.research_gui_expanded or {})[viewer_index]
    return t and t[force_name] or false
end

function M.set_expanded(viewer_index, force_name, state)
    storage.research_gui_expanded = storage.research_gui_expanded or {}
    storage.research_gui_expanded[viewer_index] = storage.research_gui_expanded[viewer_index] or {}
    storage.research_gui_expanded[viewer_index][force_name] = state
end

function M.get_diff_target(viewer_index)
    return (storage.research_gui_diff_target or {})[viewer_index]
end

function M.set_diff_target(viewer_index, target)
    storage.research_gui_diff_target = storage.research_gui_diff_target or {}
    storage.research_gui_diff_target[viewer_index] = target
end

-- ─── Time / data helpers ──────────────────────────────────────────────

-- Headline play-time caption. Shows server-elapsed time (the official basis for
-- records/awards), and — once a team has been offline at all — appends the
-- team's online time so the competition reads fairly across schedules.
local function fmt_play_time(clock_tick, online_ticks)
    if not clock_tick then return "not yet spawned" end
    local elapsed = game.tick - clock_tick
    if elapsed < 0 then elapsed = 0 end
    local caption = research_diff.fmt_duration(elapsed) .. " playing"
    if online_ticks and online_ticks < elapsed then
        caption = caption .. " (" .. research_diff.fmt_duration(online_ticks) .. " online)"
    end
    return caption
end

--- Return sorted list of researched techs for a force.
--- Entries: { name, localised, tick, order }.
--- Sorted by tick ascending; techs with no tick appended last by order.
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

--- Return ordered list of occupied team forces:
--- { owner, force_name, force, color, online, clock_start }.
local function get_player_forces()
    local result = {}
    local seen   = {}
    for _, force in pairs(game.forces) do
        if force.name:find("^team%-") then
            local force_name = force.name
            if not seen[force_name] then
                seen[force_name] = true
                local slot     = helpers.team_slot(force_name)
                local occupied = slot and (storage.team_pool or {})[slot] == "occupied"
                if not occupied then goto next_force end
                result[#result + 1] = {
                    owner       = helpers.display_name(force_name),
                    force_name  = force_name,
                    force       = force,
                    color       = helpers.force_color(force),
                    online      = #force.connected_players > 0,
                    clock_start = (storage.team_clock_start or {})[force_name],
                    online_time = team_clock.online_ticks(force_name),
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

-- ─── Overview renderer ────────────────────────────────────────────────

function M.draw_overview(content_frame, viewer_force, viewer_clock, viewer_player)
    local forces = get_player_forces()
    if #forces == 0 then
        content_frame.add{type = "label", caption = "No players found."}
        return
    end

    local own_force_name = viewer_force.name
    local show_offline   = helpers.show_offline(viewer_player)
    local viewer_index   = viewer_player.index

    for _, info in ipairs(forces) do
        if not info.online and info.force_name ~= own_force_name and not show_offline then
            goto continue
        end

        local techs    = get_researched(info.force)
        local expanded = M.get_expanded(viewer_index, info.force_name)

        local section = content_frame.add{
            type  = "frame",
            direction = "vertical",
            style = "inside_shallow_frame",
        }
        section.style.horizontally_stretchable = true
        section.style.margin  = 4
        section.style.padding = 6

        local hdr = section.add{type = "flow", direction = "horizontal"}
        hdr.style.vertical_align = "center"

        local bullet = hdr.add{type = "label", caption = "\xE2\x97\x8F"}
        bullet.style.font_color   = info.online and info.color or {0.45, 0.45, 0.45}
        bullet.style.right_margin = 4

        local name_lbl = hdr.add{type = "label", caption = info.owner}
        name_lbl.style.font       = "default-bold"
        name_lbl.style.font_color = info.online and info.color or {0.65, 0.65, 0.65}
        if not info.online then
            local off = hdr.add{type = "label", caption = " (offline)"}
            off.style.font       = "default-small"
            off.style.font_color = {0.45, 0.45, 0.45}
        end

        local count_lbl = hdr.add{type = "label", caption = "  [" .. #techs .. "]"}
        count_lbl.style.font       = "default-small"
        count_lbl.style.font_color = {0.7, 0.7, 0.7}

        local spacer = hdr.add{type = "empty-widget"}
        spacer.style.horizontally_stretchable = true

        local start_lbl = hdr.add{
            type    = "label",
            caption = fmt_play_time(info.clock_start, info.online_time),
            tooltip = "Server time since this team started (records/awards use this)."
                .. "\nIn parentheses: time at least one member was online — pauses while the whole team is offline.",
        }
        start_lbl.style.font       = "default-small"
        start_lbl.style.font_color = {0.6, 0.8, 0.6}

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

        section.add{type = "line"}.style.top_margin = 2

        if #techs == 0 then
            local none = section.add{type = "label", caption = "(no research yet)"}
            none.style.font_color = {0.5, 0.5, 0.5}
            none.style.top_margin = 2
        else
            local display_techs = techs
            if not expanded and #techs > COLLAPSED_COLS then
                display_techs = {}
                for i = 1, COLLAPSED_COLS do display_techs[i] = techs[i] end
            end
            local grid = section.add{type = "table", column_count = COLLAPSED_COLS}
            grid.style.horizontal_spacing = 0
            grid.style.vertical_spacing   = 0
            grid.style.top_margin         = 2
            research_diff.add_tech_icons(grid, display_techs, info.clock_start)
        end

        ::continue::
    end
end

return M
