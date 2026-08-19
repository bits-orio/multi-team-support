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

--- Batched replacement for the old per-cell get_count: one statistics
--- object per (force, surface), shared across every column, and
--- pcall(fn, arg) instead of a fresh closure per protected read.
---
--- Quality-correct totals (the old bare-name reads were normal-quality
--- only -- measured 108 vs the true 208, see PRODUCTION_STATS_PROBES.md):
---   * All-time: one input_counts dictionary read per (force, surface).
---     The dict merges across qualities and covers every column at once.
---   * Timed: there is no merged shortcut -- a bare name is normal-only
---     -- so merged mode sums per-quality get_flow_count over the chain.
---
--- entries: rows from player_forces. col_recs: positional table of
--- column records {kind, name} with nil holes. Returns
--- row_counts[row_index][col_index] = number, with nil exactly where
--- col_recs has a hole (matching the old shape).
function M.collect(entries, col_recs, cols, precision)
    local owned = surfaces_by_force(entries)
    local chain = quality.chain()

    -- Reusable request/id tables: the API reads them synchronously, so
    -- mutating per read is safe and skips a per-cell allocation. Item IDs
    -- take a {name, quality} pair; fluid IDs must stay bare strings.
    local req  = {name = nil, category = "input", precision_index = precision, count = true}
    local pair = {name = nil, quality = nil}

    local row_counts = {}
    for i, entry in ipairs(entries) do
        local force  = entry.force
        local totals = {}
        for col_idx = 1, cols do
            if col_recs[col_idx] then totals[col_idx] = 0 end
        end
        for _, surface in ipairs(owned[force.name]) do
            local ok, istats = pcall(force.get_item_production_statistics, surface)
            if ok and istats then
                if precision == M.ALLTIME then
                    local okf, flat = pcall(read_input_counts, istats)
                    if okf and flat then
                        for col_idx = 1, cols do
                            local col = col_recs[col_idx]
                            -- kind dispatch: the fluid statistics path lands
                            -- with the Fluids tab (plan step 6).
                            if col and col.kind == "item" then
                                totals[col_idx] = totals[col_idx] + (flat[col.name] or 0)
                            end
                        end
                    end
                else
                    for col_idx = 1, cols do
                        local col = col_recs[col_idx]
                        if col and col.kind == "item" then
                            local sum = 0
                            for _, qname in ipairs(chain) do
                                pair.name, pair.quality = col.name, qname
                                req.name = pair
                                local ok2, val = pcall(istats.get_flow_count, req)
                                if ok2 and val then sum = sum + val end
                            end
                            totals[col_idx] = totals[col_idx] + sum
                        end
                    end
                end
            end
        end
        row_counts[i] = totals
    end
    return row_counts
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
