-- Sorting and per-viewer preference for the Teams panel.
local helpers = require("scripts.helpers")
local teams_data = require("gui.teams_data")

local M = {}

function M.get_mode(player)
    return (storage.teams_sort_mode or {})[player.index] or "name"
end

function M.set_mode(player, mode)
    if mode ~= "name" and mode ~= "recent_online" then return end
    storage.teams_sort_mode = storage.teams_sort_mode or {}
    storage.teams_sort_mode[player.index] = mode
end

-- Compare digit runs numerically without converting to floating point.
-- Equal numeric runs (02 / 2) continue at the next chunk; the force slot
-- breaks ties below, giving duplicate display names a deterministic order.
local function natural_less(a, b)
    a, b = a:lower(), b:lower()
    while #a > 0 and #b > 0 do
        local an, bn = a:match("^%d+"), b:match("^%d+")
        local ac = an or a:match("^%D+")
        local bc = bn or b:match("^%D+")
        if an and bn then
            local av, bv = an:gsub("^0+", ""), bn:gsub("^0+", "")
            if #av ~= #bv then return #av < #bv end
            if av ~= bv then return av < bv end
        elseif ac ~= bc then
            return ac < bc
        end
        a, b = a:sub(#ac + 1), b:sub(#bc + 1)
    end
    return #a < #b
end

function M.sort(forces, own_force_name, mode)
    local keys = {}
    for _, force in ipairs(forces) do
        local key = {name = helpers.display_name(force.name),
                     slot = helpers.team_slot(force.name) or math.huge}
        if mode == "recent_online" then
            local members = teams_data.collect_team_members(force).members
            key.last_online = teams_data.team_last_active_tick(members) or -1
            key.online = false
            for _, member in ipairs(members) do
                if member.connected then key.online = true; break end
            end
        end
        keys[force.name] = key
    end
    table.sort(forces, function(a, b)
        if a.name == b.name then return false end
        if a.name == own_force_name then return true end
        if b.name == own_force_name then return false end
        local ka, kb = keys[a.name], keys[b.name]
        if mode == "recent_online" then
            if ka.online ~= kb.online then return ka.online end
            if ka.last_online ~= kb.last_online then return ka.last_online > kb.last_online end
        end
        if natural_less(ka.name, kb.name) then return true end
        if natural_less(kb.name, ka.name) then return false end
        if ka.slot ~= kb.slot then return ka.slot < kb.slot end
        return a.name < b.name
    end)
end

return M
