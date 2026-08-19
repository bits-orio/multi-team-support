-- gui/stats/panel.lua
-- Production stats GUI frame construction.

local helpers    = require("scripts.helpers")
local columns    = require("gui.stats.columns")
local counts     = require("gui.stats.counts")
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

-- The picker-side hidden filter cannot exclude parameter fluids (they are
-- not hidden -- probe 2A -- and FluidPrototypeFilter has no parameter
-- variant). The engine appears to exclude parameter prototypes from
-- pickers natively (the filterless item picker never shows them):
-- playtest checkpoint, with the elem-changed visibility backstop in
-- handlers.lua as defence in depth. pcall'd per plan 3.15 -- a wrong
-- filter variant errors at assignment.
local function set_fluid_filters(btn)
    btn.elem_filters = {{filter = "hidden", invert = true}}
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

-- Per-quality breakdown lines for a merged-mode cell, in chain order.
-- [item=NAME,quality=Q] renders a quality-badged icon (probe-verified).
local function quality_tooltip(item_name, cell_brk)
    local lines = {}
    for _, qname in ipairs(quality.chain()) do
        local v = cell_brk[qname]
        if v and v > 0 then
            lines[#lines + 1] = "[item=" .. item_name .. ",quality=" .. qname .. "] "
                .. counts.fmt(v)
        end
    end
    return table.concat(lines, "\n")
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
    local title = tbar.add{type = "label", caption = "Production Stats", style = "frame_title"}
    title.ignored_by_interaction = true
    local spacer = tbar.add{type = "empty-widget", style = "draggable_space_header"}
    spacer.style.horizontally_stretchable = true
    spacer.style.height = 24
    spacer.drag_target  = frame
    tbar.add{type = "sprite-button", name = "sb_stats_close",
        sprite = "utility/close", style = "frame_action_button", tooltip = "Close"}

    -- Category tabs
    local cat_row = frame.add{type = "flow", name = "sb_stats_cats", direction = "horizontal"}
    cat_row.style.horizontal_spacing = 4
    cat_row.style.top_padding        = 4
    for _, cat in ipairs(CATEGORIES) do
        local sel = (cat == state.category)
        cat_row.add{
            type    = "button",
            name    = "sb_stats_cat_" .. cat,
            caption = sel and ("> " .. CAT_LABELS[cat]) or CAT_LABELS[cat],
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
            caption = sel and ("> " .. tp.label) or tp.label,
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
            caption = msel and "> Merged" or "Merged",
            style   = msel and "green_button" or "button",
            tooltip = "Sum across all qualities",
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
                btn.style.width = 36
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
        scroll.add{type = "label", caption = "(no players yet)"}
        return
    end

    local tbl = scroll.add{
        type = "table", name = "sb_stats_table",
        column_count = cols + 1, draw_horizontal_lines = true,
    }
    tbl.style.horizontal_spacing = 4
    tbl.style.vertical_spacing   = 2

    -- Header row: blank corner + per-column choose-elem-buttons. The
    -- Fluids tab types its buttons "fluid"; elem_type is create-time-only,
    -- and a full rebuild happens on every category switch anyway.
    local tab_fluid  = (state.category == "fluids")
    local col_elem   = tab_fluid and "fluid" or "item"
    tbl.add{type = "label", caption = ""}
    for col_idx = 1, cols do
        local col = col_recs[col_idx]
        local btn = tbl.add{
            type      = "choose-elem-button",
            name      = "sb_stats_item_" .. col_idx,
            elem_type = col_elem,
            style     = "slot_button",
            tags      = {sb_stats_col = col_idx, sb_stats_cat = state.category},
        }
        if tab_fluid then pcall(set_fluid_filters, btn) end
        if col then
            btn.elem_value = col.name
            local is_fluid = col.kind == "fluid"
            local proto = is_fluid and prototypes.fluid[col.name]
                                    or prototypes.item[col.name]
            local tag = is_fluid and "[fluid=" or "[item="
            -- Big icon + localised name (large-bold font scales both up so the
            -- icon stays readable when the slot button itself has been shrunk),
            -- then the click hint on a new line.
            btn.tooltip = {"",
                "[font=default-large-bold]" .. tag .. col.name .. "]  ",
                proto and proto.localised_name or col.name,
                "[/font]\nClick to change this column",
            }
        else
            btn.tooltip = tab_fluid and "Click to add a fluid to this column"
                                     or "Click to add an item to this column"
        end
        btn.style.width   = btn_size
        btn.style.height  = btn_size
        btn.style.padding = 0
    end

    -- Sort button row
    local sort_col  = state.sort_col
    local sort_dir  = state.sort_dir or "desc"
    local sort_cell = tbl.add{type = "flow", direction = "horizontal"}
    sort_cell.style.horizontally_stretchable = true
    local sc_spacer = sort_cell.add{type = "empty-widget"}
    sc_spacer.style.horizontally_stretchable = true
    local sort_lbl = sort_cell.add{type = "label", caption = "sort →"}
    sort_lbl.style.font       = "default-small"
    sort_lbl.style.font_color = {0.6, 0.6, 0.6}
    for col_idx = 1, cols do
        if col_recs[col_idx] then
            local active  = sort_col == col_idx
            local caption = active and (sort_dir == "desc" and "▼" or "▲") or "·"
            local btn = tbl.add{
                type    = "button",
                caption = caption,
                style   = active and "green_button" or "button",
                tags    = {sb_stats_sort = col_idx},
                tooltip = active
                    and (sort_dir == "desc" and "Sorted high→low (click for low→high)"
                                            or "Sorted low→high (click to clear sort)")
                    or  "Sort by this column (high→low)",
            }
            btn.style.width   = btn_size
            btn.style.height  = sort_h
            btn.style.padding = 0
        else
            tbl.add{type = "label", caption = ""}
        end
    end

    if sort_col then
        local pairs_list = {}
        for i = 1, #pf do
            pairs_list[i] = {entry = pf[i], cnts = row_counts[i], brk = breakdown[i]}
        end
        table.sort(pairs_list, function(a, b)
            local ca = a.cnts[sort_col] or 0
            local cb = b.cnts[sort_col] or 0
            if ca ~= cb then
                if sort_dir == "desc" then return ca > cb end
                return ca < cb
            end
            return a.entry.player_name < b.entry.player_name
        end)
        pf, row_counts, breakdown = {}, {}, {}
        for i, p in ipairs(pairs_list) do
            pf[i] = p.entry; row_counts[i] = p.cnts; breakdown[i] = p.brk
        end
    end

    -- Data rows
    for i, entry in ipairs(pf) do
        local name_cell = tbl.add{type = "flow", direction = "horizontal"}
        name_cell.style.vertical_align = "center"
        name_cell.style.minimal_width  = 160
        if entry.slot then
            local slot_lbl = name_cell.add{
                type    = "label",
                caption = "#" .. entry.slot,
                tooltip = "Team slot " .. entry.slot .. " (" .. entry.force.name .. ")",
            }
            slot_lbl.style.font         = "default-small"
            slot_lbl.style.font_color   = {0.55, 0.55, 0.55}
            slot_lbl.style.right_margin = 4
        end
        local name_lbl = name_cell.add{type = "label", caption = entry.caption}
        name_lbl.style.font = "default-bold"
        if not entry.online then
            name_lbl.style.font_color = {0.65, 0.65, 0.65}
            -- Surface how stale a fully-offline team is (same last-seen data
            -- and colour thresholds as the teams GUI activity label), so the
            -- disband decision doesn't need a second GUI.
            local act = entry.activity
            local off_lbl = name_cell.add{
                type    = "label",
                caption = act and (" (offline · " .. teams_data.fmt_ago(act.ago_ticks) .. ")")
                              or  " (offline)",
                tooltip = act and act.tooltip or nil,
            }
            off_lbl.style.font       = "default-small"
            off_lbl.style.font_color = act and act.color or {0.45, 0.45, 0.45}
        end
        for col_idx = 1, cols do
            local count = row_counts[i][col_idx]
            if count then
                local cell = tbl.add{type = "label", caption = counts.fmt(count)}
                -- Merged-mode cells with non-normal production carry a
                -- per-quality breakdown; normal-only cells stay bare, which
                -- is also the honest signal there is nothing to break down.
                local cell_brk = breakdown[i] and breakdown[i][col_idx]
                if cell_brk and next(cell_brk) then
                    cell.tooltip = quality_tooltip(col_recs[col_idx].name, cell_brk)
                end
                cell.style.minimal_width    = btn_size
                cell.style.horizontal_align = "right"
                if btn_size <= 26 then cell.style.font = "default-small" end
            else
                tbl.add{type = "label", caption = ""}
            end
        end
    end
end

return M
