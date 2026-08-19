-- gui/stats/grid.lua
-- The stats table itself: column-picker header, sort row, and per-team
-- data rows. gui/stats/panel.lua builds the frame chrome around it and
-- hands over a context of precomputed data.

local counts     = require("gui.stats.counts")
local quality    = require("gui.stats.quality")
local teams_data = require("gui.teams_data")

local M = {}

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

--- ctx: state, qview, col_recs, cols, btn_size, sort_h, pf, row_counts,
--- breakdown -- all precomputed by panel.build_stats_gui. Sorting
--- reorders pf/row_counts/breakdown together, so it lives here with the
--- rows that render them.
function M.build(scroll, ctx)
    local state      = ctx.state
    local qview      = ctx.qview
    local col_recs   = ctx.col_recs
    local cols       = ctx.cols
    local btn_size   = ctx.btn_size
    local sort_h     = ctx.sort_h
    local pf         = ctx.pf
    local row_counts = ctx.row_counts
    local breakdown  = ctx.breakdown

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
