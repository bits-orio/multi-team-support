-- Multi-Team Support - research_diff.lua
-- Author: bits-orio
-- License: MIT
--
-- Shared tech helpers and diff-mode renderer extracted from research_gui.lua.

local helpers = require("scripts.helpers")

local research_diff = {}

-- ---------------------------------------------------------------------------
-- Time formatting
-- ---------------------------------------------------------------------------

--- Convert a tick count to a human-readable duration string ("1h 23m 45s").
function research_diff.fmt_duration(ticks)
    local s = math.floor(ticks / 60)
    local h = math.floor(s / 3600); s = s % 3600
    local m = math.floor(s / 60);   s = s % 60
    if h > 0 then return string.format("%dh %02dm %02ds", h, m, s) end
    if m > 0 then return string.format("%dm %02ds", m, s) end
    return string.format("%ds", s)
end

-- ---------------------------------------------------------------------------
-- Tech data helpers
-- ---------------------------------------------------------------------------

--- Return the research-timestamp table for a force (may be empty table).
function research_diff.force_ticks(force)
    return (storage.tech_research_ticks or {})[force.name] or {}
end

--- Build a tooltip string for a tech icon.
function research_diff.tech_tooltip(entry, clock_start)
    local name_line = entry.localised
    if not entry.tick then
        return {"", name_line, "\nResearched: (before tracking began)"}
    end
    if not clock_start then
        return {"", name_line, "\nResearched: tick " .. entry.tick}
    end
    local elapsed = entry.tick - clock_start
    if elapsed < 0 then elapsed = 0 end
    return {"", name_line, "\nResearched: " .. research_diff.fmt_duration(elapsed) .. " after spawn"}
end

-- ---------------------------------------------------------------------------
-- Icon grid rendering
-- ---------------------------------------------------------------------------

--- Add tech icons to a table element. Each icon opens the tech tree on click.
function research_diff.add_tech_icons(grid, tech_list, clock_start)
    for _, entry in ipairs(tech_list) do
        grid.add{
            type    = "sprite-button",
            sprite  = "technology/" .. entry.name,
            tooltip = research_diff.tech_tooltip(entry, clock_start),
            style   = "slot_button",
            tags    = {sb_research_open_tech = entry.name},
        }
    end
end

--- Render the research queue for a force as a fixed row of max_slots icon buttons.
--- Filled slots show the queued tech icon, a thin progress bar below it, and open
--- the tech tree on click. Empty slots are dimmed placeholders.
function research_diff.add_queue_icons(parent, force, max_slots)
    local queue = force.research_queue or {}
    for i = 1, max_slots do
        local tech = queue[i]
        if tech and tech.valid then
            -- Progress: active research uses force.research_progress; queued-but-not-
            -- started techs use tech.saved_progress (preserved across reorders).
            local progress = (i == 1) and force.research_progress or tech.saved_progress
            local pct      = math.floor(progress * 100)

            local slot = parent.add{type = "flow", direction = "vertical"}
            slot.style.vertical_spacing = 1

            local btn = slot.add{
                type    = "sprite-button",
                sprite  = "technology/" .. tech.name,
                tooltip = {"", tech.localised_name,
                    "\nQueued at position " .. i ..
                    (pct > 0 and ("\nProgress: " .. pct .. "%") or "")},
                style   = "slot_button",
                tags    = {sb_research_open_tech = tech.name},
            }
            btn.style.width  = 28
            btn.style.height = 28

            local bar = slot.add{type = "progressbar", value = progress}
            bar.style.width  = 28
            bar.style.height = 4
            bar.style.color  = {r = 0.2, g = 0.8, b = 0.2}
        else
            local btn = parent.add{type = "sprite-button", style = "slot_button"}
            btn.style.width   = 28
            btn.style.height  = 28
            btn.enabled       = false
        end
    end
end

-- ---------------------------------------------------------------------------
-- Diff mode
-- ---------------------------------------------------------------------------

--- Draw the research diff view comparing viewer_force against a target team.
--- @param content_frame  LuaGuiElement  scrollable pane to draw into
--- @param viewer_force   LuaForce
--- @param viewer_clock   number|nil     tick the viewer's team started
--- @param target_force_name string      internal force name (e.g. "team-1")
--- @param collapsed_cols number         number of icon columns per row
function research_diff.draw(content_frame, viewer_force, viewer_clock, target_force_name, collapsed_cols)
    -- Resolve target force
    local target_force = game.forces[target_force_name]
    if not target_force then
        content_frame.add{type = "label", caption = "Team '" .. target_force_name .. "' not found."}
        return
    end

    -- Target clock start (team clock, not player clock)
    local target_clock = (storage.team_clock_start or {})[target_force_name]

    -- Back button
    local back_btn = content_frame.add{
        type    = "button",
        name    = "sb_research_back",
        caption = "< Back",
        style   = "back_button",
    }
    back_btn.style.bottom_margin = 6

    -- Context: who started earlier
    local target_owner = helpers.display_name(target_force_name)
    local viewer_owner = helpers.display_name(viewer_force.name)
    if viewer_clock and target_clock then
        local diff_ticks = math.abs(viewer_clock - target_clock)
        local context
        if viewer_clock < target_clock then
            context = "You started " .. research_diff.fmt_duration(diff_ticks) .. " earlier than " .. target_owner
        elseif target_clock < viewer_clock then
            context = target_owner .. " started " .. research_diff.fmt_duration(diff_ticks) .. " earlier than you"
        else
            context = "You both started at the same time"
        end
        local ctx_lbl = content_frame.add{type = "label", caption = context}
        ctx_lbl.style.font         = "default-bold"
        ctx_lbl.style.font_color   = {0.7, 0.9, 0.7}
        ctx_lbl.style.bottom_margin = 8
    end

    -- Compute diff sets
    local viewer_ticks = research_diff.force_ticks(viewer_force)
    local target_ticks = research_diff.force_ticks(target_force)

    -- both_have: researched by both
    local both_have = {}
    -- they_have: researched by target but NOT by viewer
    local they_have = {}
    -- you_have: researched by viewer but NOT by target
    local you_have  = {}

    for name, tech in pairs(target_force.technologies) do
        if tech.researched then
            if viewer_force.technologies[name] and viewer_force.technologies[name].researched then
                both_have[#both_have + 1] = {
                    name      = name,
                    localised = tech.localised_name,
                    tick      = target_ticks[name],
                    order     = tech.order,
                }
            else
                they_have[#they_have + 1] = {
                    name      = name,
                    localised = tech.localised_name,
                    tick      = target_ticks[name],
                    order     = tech.order,
                }
            end
        end
    end

    for name, tech in pairs(viewer_force.technologies) do
        if tech.researched and not (target_force.technologies[name] and target_force.technologies[name].researched) then
            you_have[#you_have + 1] = {
                name      = name,
                localised = tech.localised_name,
                tick      = viewer_ticks[name],
                order     = tech.order,
            }
        end
    end

    -- Sort each set by timestamp (then tech.order for unstamped)
    local function sort_diff(list)
        local stamped, unstamped = {}, {}
        for _, e in ipairs(list) do
            if e.tick then stamped[#stamped+1] = e else unstamped[#unstamped+1] = e end
        end
        table.sort(stamped,   function(a, b) return a.tick  < b.tick  end)
        table.sort(unstamped, function(a, b) return a.order < b.order end)
        for _, v in ipairs(unstamped) do stamped[#stamped+1] = v end
        return stamped
    end
    both_have = sort_diff(both_have)
    they_have = sort_diff(they_have)
    you_have  = sort_diff(you_have)

    local cols = collapsed_cols

    local function diff_section(title, list, clock_for_tooltip)
        local hdr = content_frame.add{type = "label", caption = title .. "  (" .. #list .. ")"}
        hdr.style.font          = "default-bold"
        hdr.style.top_margin    = 6
        hdr.style.bottom_margin = 2

        if #list == 0 then
            local none = content_frame.add{type = "label", caption = "(none)"}
            none.style.font_color = {0.5, 0.5, 0.5}
        else
            local grid = content_frame.add{type = "table", column_count = cols}
            grid.style.horizontal_spacing = 0
            grid.style.vertical_spacing   = 0
            research_diff.add_tech_icons(grid, list, clock_for_tooltip)
        end
    end

    -- Use viewer's clock for shared techs tooltip (arbitrary choice; both valid)
    diff_section("You both have researched", both_have, viewer_clock)
    diff_section(target_owner .. " has, you don't", they_have, target_clock)
    diff_section("You have, " .. target_owner .. " doesn't", you_have, viewer_clock)

    -- Infinite tech level differences
    local inf_diffs = {}
    for name, v_tech in pairs(viewer_force.technologies) do
        local t_tech = target_force.technologies[name]
        if v_tech.researched and t_tech and t_tech.researched then
            local vl = (v_tech.level  or 1)
            local tl = (t_tech.level  or 1)
            if vl ~= tl then
                inf_diffs[#inf_diffs + 1] = {
                    name   = name,
                    v_lvl  = vl,
                    t_lvl  = tl,
                    loc    = v_tech.localised_name,
                }
            end
        end
    end

    if #inf_diffs > 0 then
        table.sort(inf_diffs, function(a, b)
            return tostring(a.name) < tostring(b.name)
        end)
        local hdr2 = content_frame.add{type = "label", caption = "Infinite tech level differences"}
        hdr2.style.font         = "default-bold"
        hdr2.style.top_margin   = 8
        hdr2.style.bottom_margin = 2

        local inf_tbl = content_frame.add{type = "table", column_count = 3}
        inf_tbl.style.horizontal_spacing = 12
        inf_tbl.style.vertical_spacing   = 2
        -- Header row
        local function hd(txt)
            local l = inf_tbl.add{type = "label", caption = txt}
            l.style.font = "default-bold"
        end
        hd("Technology"); hd("You"); hd(target_owner)
        for _, d in ipairs(inf_diffs) do
            inf_tbl.add{type = "label", caption = d.loc}
            local vl = inf_tbl.add{type = "label", caption = "Lv " .. d.v_lvl}
            local tl = inf_tbl.add{type = "label", caption = "Lv " .. d.t_lvl}
            if d.v_lvl > d.t_lvl then
                vl.style.font_color = {0.4, 1, 0.4}
            else
                tl.style.font_color = {0.4, 1, 0.4}
            end
        end
    end
end

return research_diff
