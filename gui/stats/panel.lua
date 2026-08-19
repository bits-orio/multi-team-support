-- gui/stats/panel.lua
-- Production stats GUI frame construction.

local helpers    = require("scripts.helpers")
local columns    = require("gui.stats.columns")
local counts     = require("gui.stats.counts")
local grid       = require("gui.stats.grid")
local quality    = require("gui.stats.quality")
local teams_data = require("gui.teams_data")

local M = {}

local TIME_PERIODS = counts.TIME_PERIODS
local CATEGORIES   = columns.CATEGORIES
local CAT_LABELS   = columns.CAT_LABELS

-- Slot button sizing scales down as the column count grows, so that auto
-- categories (ores / plates / science) with many overhaul-mod prototypes
-- stay within a reasonable horizontal footprint. The 16-col tier preserves
-- the full button size for the curated tabs (intermediates / custom), which
-- max out at CURATED_COLS = 16.
local function slot_metrics(cols)
    local btn
    if     cols <= 16 then btn = 40
    elseif cols <= 24 then btn = 32
    else                   btn = 26
    end
    local sort_h = (btn <= 26) and 16 or 20
    return btn, sort_h
end


-- Union of is_quality_unlocked across the rendered teams. The docs
-- declare no return value but the call returns a real boolean in-game
-- (probe-verified); nil counts as unlocked so the doc quirk can only
-- ever SHOW a selector button, never hide one. UI-affordance only --
-- summation is data-gated in counts.collect, never unlock-gated.
local function unlocked_any(entries, qname)
    for _, entry in ipairs(entries) do
        local ok, ret = pcall(entry.force.is_quality_unlocked, qname)
        if ok and ret ~= false then return true end
    end
    return false
end


-- ─── GUI Construction ──────────────────────────────────────────────────

function M.build_stats_gui(player, leaving_index)
    local screen = player.gui.screen

    if not storage.stats_gui_location then storage.stats_gui_location = {} end
    local saved_pos
    if screen.sb_stats_frame then
        saved_pos = screen.sb_stats_frame.location
        storage.stats_gui_location[player.index] = saved_pos
        screen.sb_stats_frame.destroy()
    else
        saved_pos = storage.stats_gui_location[player.index]
    end

    local state        = columns.get_state(player)
    local col_recs     = columns.get_columns(player.index, state.category)
    local cols         = columns.get_target_cols(player.index, state.category)
    local btn_size, sort_h = slot_metrics(cols)
    local all_pf       = counts.player_forces(leaving_index)
    local show_offline = helpers.show_offline(player)
    local my_name    = helpers.display_name(player.force.name)
    local pf = {}
    for _, entry in ipairs(all_pf) do
        if entry.online or entry.player_name == my_name or show_offline then
            pf[#pf + 1] = entry
        end
    end

    -- Resolve the quality view tolerantly: a stored name that no longer
    -- exists (quality mod removed mid-save) falls back to merged.
    local qview = state.quality or "merged"
    if qview ~= "merged" and not prototypes.quality[qview] then
        qview, state.quality = "merged", "merged"
    end

    -- Counts are computed before any GUI exists: the quality selector row
    -- needs the produced-qualities set from the same pass.
    local row_counts, breakdown, produced =
        counts.collect(pf, col_recs, cols, state.precision, qview)

    local frame = screen.add{type = "frame", name = "sb_stats_frame", direction = "vertical"}
    frame.style.minimal_width = 320
    if saved_pos then frame.location = saved_pos else frame.auto_center = true end

    -- Title bar
    local tbar = frame.add{type = "flow", name = "sb_stats_titlebar", direction = "horizontal"}
    tbar.drag_target = frame
    tbar.style.vertical_align     = "center"
    tbar.style.horizontal_spacing = 8
    local title = tbar.add{type = "label", caption = {"mts-gui.stats-title"}, style = "frame_title"}
    title.ignored_by_interaction = true
    local spacer = tbar.add{type = "empty-widget", style = "draggable_space_header"}
    spacer.style.horizontally_stretchable = true
    spacer.style.height = 24
    spacer.drag_target  = frame
    tbar.add{type = "sprite-button", name = "sb_stats_close",
        sprite = "utility/close", style = "frame_action_button", tooltip = {"mts-tip.stats-close"}}

    -- Category tabs
    local cat_row = frame.add{type = "flow", name = "sb_stats_cats", direction = "horizontal"}
    cat_row.style.horizontal_spacing = 4
    cat_row.style.top_padding        = 4
    for _, cat in ipairs(CATEGORIES) do
        local sel = (cat == state.category)
        cat_row.add{
            type    = "button",
            name    = "sb_stats_cat_" .. cat,
            caption = sel and {"mts-gui.selected-tab", CAT_LABELS[cat]} or CAT_LABELS[cat],
            style   = sel and "green_button" or "button",
        }
    end

    -- Time period tabs
    local time_row = frame.add{type = "flow", name = "sb_stats_times", direction = "horizontal"}
    time_row.style.horizontal_spacing = 4
    time_row.style.bottom_padding     = 4
    for _, tp in ipairs(TIME_PERIODS) do
        local sel = (tp.precision == state.precision)
        time_row.add{
            type    = "button",
            name    = "sb_stats_time_" .. tp.key,
            caption = sel and {"mts-gui.selected-tab", tp.label} or tp.label,
            style   = sel and "green_button" or "button",
        }
    end

    -- Quality view row: merged + per-quality pins. Rendered only when the
    -- quality axis exists at all (base-only installs see no change), and
    -- not on the Fluids tab -- fluids have no quality dimension.
    -- Membership: unlocked by ANY rendered team UNION produced -- data can
    -- exist at a quality nobody unlocked (scripted/cheat production) and
    -- must stay selectable on a competitive panel.
    if quality.multi_enabled() and state.category ~= "fluids" then
        local qrow = frame.add{type = "flow", name = "sb_stats_quals", direction = "horizontal"}
        qrow.style.horizontal_spacing = 4
        qrow.style.bottom_padding     = 4
        local msel = (qview == "merged")
        qrow.add{
            type    = "button",
            name    = "sb_stats_qual_merged",
            caption = msel and {"mts-gui.selected-tab", {"mts-gui.stats-quality-merged"}}
                            or {"mts-gui.stats-quality-merged"},
            style   = msel and "green_button" or "button",
            tooltip = {"mts-tip.stats-quality-merged"},
        }
        for _, qname in ipairs(quality.chain()) do
            if qname == "normal" or produced[qname] or qview == qname
                or unlocked_any(pf, qname) then
                local sel = (qview == qname)
                local qproto = prototypes.quality[qname]
                local btn = qrow.add{
                    type    = "button",
                    name    = "sb_stats_qual_" .. qname,
                    caption = "[img=quality/" .. qname .. "]",
                    style   = sel and "green_button" or "button",
                    tooltip = qproto and qproto.localised_name or qname,
                }
                -- The default button style's horizontal padding crops the
                -- rich-text icon glyph; zero it and let the icon center in
                -- the full content box.
                btn.style.width   = 30
                btn.style.padding = 0
            end
        end
    end

    helpers.add_show_offline_checkbox(frame, player)

    local scroll = frame.add{
        type = "scroll-pane", name = "sb_stats_scroll", direction = "vertical",
        horizontal_scroll_policy = "auto", vertical_scroll_policy = "auto",
    }
    scroll.style.maximal_height = 500
    -- Let the scroll pane grow to fit wider tables (many cols × small buttons),
    -- with a hard ceiling so the frame never exceeds typical screen widths.
    local desired_w = 160 + cols * (btn_size + 4) + 40
    if desired_w < 900  then desired_w = 900  end
    if desired_w > 1500 then desired_w = 1500 end
    scroll.style.maximal_width = desired_w

    if #pf == 0 then
        scroll.add{type = "label", caption = {"mts-gui.stats-no-players"}}
        return
    end

    grid.build(scroll, {
        state = state, qview = qview, col_recs = col_recs, cols = cols,
        btn_size = btn_size, sort_h = sort_h,
        pf = pf, row_counts = row_counts, breakdown = breakdown,
    })
end

return M
