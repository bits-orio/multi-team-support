-- gui/stats/counts.lua
-- Statistics reads, count formatting, and the team-force row list for the
-- production stats GUI.

local helpers       = require("scripts.helpers")
local surface_utils = require("scripts.surface_utils")
local teams_data    = require("gui.teams_data")

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

function M.get_count(force, item_name, precision)
    local total = 0
    -- A force has zero production on surfaces it doesn't own, so scanning only
    -- its own surfaces yields the same total while skipping every other team's
    -- (PF-1) -- the game.surfaces scan cost the item count nothing but time.
    for _, surface in ipairs(surface_utils.owned_surfaces_by_force(force.name)) do
        local ok, stats = pcall(function()
            return force.get_item_production_statistics(surface)
        end)
        if ok and stats then
            if precision == M.ALLTIME then
                local ok2, val = pcall(function() return stats.get_input_count(item_name) end)
                if ok2 and val then total = total + val end
            else
                local ok2, val = pcall(function()
                    return stats.get_flow_count{
                        name            = item_name,
                        category        = "input",
                        precision_index = precision,
                        count           = true,
                    }
                end)
                if ok2 and val then total = total + val end
            end
        end
    end
    return total
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
