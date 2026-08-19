-- gui/stats/counts.lua
-- Statistics reads, count formatting, and the team-force row list for the
-- production stats GUI.

local helpers       = require("scripts.helpers")
local surface_utils = require("scripts.surface_utils")
local teams_data    = require("gui.teams_data")
local quality       = require("gui.stats.quality")

local M = {}

-- Sentinel stored in state.precision to indicate "all time" mode.
M.ALLTIME = "alltime"

M.TIME_PERIODS = {
    {key = "1min",    label = "1m",  precision = defines.flow_precision_index.one_minute},
    {key = "10min",   label = "10m", precision = defines.flow_precision_index.ten_minutes},
    {key = "1hr",     label = "1h",  precision = defines.flow_precision_index.one_hour},
    {key = "10hr",    label = "10h", precision = defines.flow_precision_index.ten_hours},
    {key = "alltime", label = "All", precision = "alltime"},
}

function M.fmt(n)
    if n == 0 then return "0" end
    if n >= 1000000 then return string.format("%.1fM", n / 1000000) end
    if n >= 1000    then return string.format("%.1fk", n / 1000) end
    return tostring(math.floor(n))
end

--- Owned-surface lists for the given row entries, resolved with ONE pass
--- over game.surfaces. The old per-cell get_count called
--- owned_surfaces_by_force per invocation, and get_owner's platform
--- fallback is O(forces x platforms) -- so the panel paid
--- teams x cols x surfaces x that before reading a single statistic.
--- A force still has zero production on surfaces it doesn't own (PF-1),
--- so grouping by owner yields the same totals.
local function surfaces_by_force(entries)
    local owned = {}
    for _, entry in ipairs(entries) do owned[entry.force.name] = {} end
    for _, surface in pairs(game.surfaces) do
        if surface.valid then
            local owner = surface_utils.get_owner(surface)
            local list = owner and owned[owner]
            if list then list[#list + 1] = surface end
        end
    end
    return owned
end

-- Attribute reads need a named accessor to be pcall-able without
-- allocating a closure per call.
local function read_input_counts(stats) return stats.input_counts end

--- Batched, quality-correct statistics reads: one statistics object per
--- (force, surface) shared across every column, pcall(fn, arg) instead
--- of per-read closures, reusable id tables (item IDs take a
--- {name, quality} pair; fluid IDs must stay bare strings).
---
--- qview: "merged" (default) or a quality name to pin the whole table.
---
--- Merged mode (the old bare-name reads were normal-only -- measured 108
--- vs the true 208, see PRODUCTION_STATS_PROBES.md):
---   * All-time totals come from one input_counts dictionary read per
---     surface -- it merges across qualities and covers every column.
---   * The same flat read powers the fan-out gate: flat[name] (merged)
---     vs get_input_count(name) (normal-only) differ exactly when this
---     force ever produced the item at a non-normal quality. Gating on
---     DATA rather than is_quality_unlocked keeps scripted or cheated
---     production at locked qualities counted.
---   * Normal-only cells: timed reads use the single bare call (equal to
---     merged by the gate). Multi cells expand once on the all-time axis
---     and read only qualities with real production -- sound because
---     counts are cumulative: all-time zero implies every window zero.
---
--- Returns (row_counts, breakdown, produced):
---   row_counts[row][col] = number, nil exactly at col_recs holes.
---   breakdown[row][col]  = {quality_name -> count} for merged-mode cells
---                          with non-normal production (tooltip data).
---   produced             = set of quality names seen with production
---                          across all rendered cells (selector row).
function M.collect(entries, col_recs, cols, precision, qview)
    qview = qview or "merged"
    local owned = surfaces_by_force(entries)
    local chain = quality.chain()

    local req  = {name = nil, category = "input", precision_index = precision, count = true}
    local pair = {name = nil, quality = nil}

    local row_counts, breakdown, produced = {}, {}, {}
    for i, entry in ipairs(entries) do
        local force  = entry.force
        local totals = {}
        local brk    = {}
        for col_idx = 1, cols do
            if col_recs[col_idx] then totals[col_idx] = 0 end
        end
        for _, surface in ipairs(owned[force.name]) do
            local ok, istats = pcall(force.get_item_production_statistics, surface)
            if ok and istats then
                if qview ~= "merged" then
                    -- Pinned view: one read per cell at that quality. No
                    -- gate, no breakdown -- the number IS one quality.
                    for col_idx = 1, cols do
                        local col = col_recs[col_idx]
                        if col and col.kind == "item" then
                            pair.name, pair.quality = col.name, qview
                            local ok2, val
                            if precision == M.ALLTIME then
                                ok2, val = pcall(istats.get_input_count, pair)
                            else
                                req.name = pair
                                ok2, val = pcall(istats.get_flow_count, req)
                            end
                            if ok2 and val then
                                totals[col_idx] = totals[col_idx] + val
                            end
                        end
                    end
                else
                    local okf, flat = pcall(read_input_counts, istats)
                    if okf and flat then
                        for col_idx = 1, cols do
                            local col = col_recs[col_idx]
                            -- kind dispatch: the fluid statistics path lands
                            -- with the Fluids tab (plan step 6).
                            if col and col.kind == "item" then
                                local merged_all = flat[col.name] or 0
                                local okn, normal_all = pcall(istats.get_input_count, col.name)
                                local multi = okn and normal_all ~= nil
                                    and merged_all ~= normal_all

                                if precision == M.ALLTIME then
                                    totals[col_idx] = totals[col_idx] + merged_all
                                end

                                if not multi then
                                    if precision ~= M.ALLTIME then
                                        req.name = col.name
                                        local ok2, val = pcall(istats.get_flow_count, req)
                                        if ok2 and val then
                                            totals[col_idx] = totals[col_idx] + val
                                        end
                                    end
                                else
                                    local cell_brk = brk[col_idx]
                                    if not cell_brk then
                                        cell_brk = {}
                                        brk[col_idx] = cell_brk
                                    end
                                    for _, qname in ipairs(chain) do
                                        pair.name, pair.quality = col.name, qname
                                        local oka, alltime = pcall(istats.get_input_count, pair)
                                        if oka and alltime and alltime > 0 then
                                            produced[qname] = true
                                            local val
                                            if precision == M.ALLTIME then
                                                val = alltime
                                            else
                                                req.name = pair
                                                local ok2, v = pcall(istats.get_flow_count, req)
                                                val = ok2 and v or nil
                                                if val then
                                                    totals[col_idx] = totals[col_idx] + val
                                                end
                                            end
                                            if val and val > 0 then
                                                cell_brk[qname] = (cell_brk[qname] or 0) + val
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        row_counts[i] = totals
        breakdown[i]  = brk
    end
    return row_counts, breakdown, produced
end

--- Returns team forces sorted by display name; includes online status.
--- leaving_index: index of a player who just left (connected may still be true).
function M.player_forces(leaving_index)
    local list = {}
    for name, force in pairs(game.forces) do
        if name:find("^team%-") then
            local slot = helpers.team_slot(name)
            local occupied = slot and (storage.team_pool or {})[slot] == "occupied"
            if not occupied then goto next_force end

            -- Effective-force members, not force.players: a member spectating
            -- another team is temporarily on the spectator force, but their
            -- team is not offline. Keeps the online flag consistent with the
            -- activity data below and with the teams GUI.
            local members = teams_data.collect_team_members(force)
            local online = false
            for _, member in ipairs(members.members) do
                if member.connected and member.index ~= leaving_index then
                    online = true; break
                end
            end
            list[#list + 1] = {
                player_name = helpers.display_name(name),
                caption     = helpers.team_tag_with_leader(name),
                force       = force,
                online      = online,
                slot        = slot,
                activity    = teams_data.activity_info(members.members),
            }
            ::next_force::
        end
    end
    table.sort(list, function(a, b) return a.player_name < b.player_name end)
    return list
end

return M
