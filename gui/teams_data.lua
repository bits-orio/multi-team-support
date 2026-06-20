-- gui/teams_data.lua
-- Data collection and activity helpers shared by the teams GUI modules.

local spectator = require("scripts.spectator")
local helpers   = require("scripts.helpers")

local M = {}

M.SKIP_FORCES = {enemy = true, neutral = true, player = true, spectator = true}

-- ─── GPS Helpers ───────────────────────────────────────────────────────

local function get_platform_gps(platform)
    local hub = platform.hub
    if not (hub and hub.valid and platform.surface) then return "" end
    local pos = hub.position
    return string.format("[gps=%d,%d,%s]", pos.x, pos.y, platform.surface.name)
end

-- ─── Data Collection ───────────────────────────────────────────────────

function M.collect_team_surfaces(force)
    local list = {}

    for _, platform in pairs(force.platforms) do
        local location = platform.space_location and platform.space_location.name or "in transit"
        local hub = platform.hub
        local hub_pos = (hub and hub.valid) and hub.position or nil
        list[#list + 1] = {
            name         = platform.name,
            location     = location,
            gps          = get_platform_gps(platform),
            surface_name = platform.surface and platform.surface.name or nil,
            position     = hub_pos and {x = hub_pos.x, y = hub_pos.y} or helpers.ORIGIN,
        }
    end

    for _, surface in pairs(game.surfaces) do
        if surface.valid then
            local owner_fn, planet = surface.name:match("^(team%-%d+)%-(%w+)$")
            if owner_fn == force.name then
                local planet_disp = planet:sub(1, 1):upper() .. planet:sub(2)
                list[#list + 1] = {
                    name         = planet_disp .. " base",
                    location     = planet_disp,
                    gps          = string.format("[gps=0,0,%s]", surface.name),
                    surface_name = surface.name,
                    position     = helpers.ORIGIN,
                }
            end
        end
    end

    -- Ephemeral, consumer-registered surfaces (mts-v1 create_team_surface, e.g.
    -- MTS Dimension Warp warp/floor/dock worlds). This map is keyed 1:1 by surface
    -- name, so -- unlike the base-keyed variant map below -- two surfaces on the
    -- same base planet are BOTH listed instead of collapsing to one.
    for sname, owner in pairs(storage.surface_owner_overrides or {}) do
        if owner == force.name then
            local surface = game.surfaces[sname]
            if surface and surface.valid then
                list[#list + 1] = {
                    name         = sname,
                    location     = sname,
                    gps          = string.format("[gps=0,0,%s]", sname),
                    surface_name = sname,
                    position     = helpers.ORIGIN,
                }
            end
        end
    end

    local per_team = (storage.map_force_to_planets or {})[force.name] or {}
    for base, variant in pairs(per_team) do
        local surface = game.surfaces[variant]
        if surface and surface.valid then
            local planet_disp = base:sub(1, 1):upper() .. base:sub(2)
            list[#list + 1] = {
                name         = planet_disp .. " base",
                location     = planet_disp,
                gps          = string.format("[gps=0,0,%s]", surface.name),
                surface_name = surface.name,
                position     = helpers.ORIGIN,
            }
        end
    end

    return list
end

--- Uses *effective* force so spectating members still appear under their real team.
function M.collect_team_members(force)
    local leader_idx = (storage.team_leader or {})[force.name]
    local leader = leader_idx and game.get_player(leader_idx) or nil

    local members = {}
    for _, p in pairs(game.players) do
        if p.valid and spectator.get_effective_force(p) == force.name then
            members[#members + 1] = p
        end
    end
    table.sort(members, function(a, b)
        if a == leader then return true end
        if b == leader then return false end
        return a.name < b.name
    end)

    return { leader = leader, members = members }
end

--- A team is "occupied" if its slot is claimed, regardless of whether members
--- are temporarily on the spectator force.
function M.is_team_occupied(force_name)
    local slot = tonumber(force_name:match("^team%-(%d+)$"))
    if not slot then return false end
    return (storage.team_pool or {})[slot] == "occupied"
end

--- Public helper used by /mts-players command and other modules.
function M.get_platforms_by_owner()
    local owners     = {}
    local owner_info = {}
    local order      = {}

    for _, force in pairs(game.forces) do
        if not M.SKIP_FORCES[force.name] and M.is_team_occupied(force.name) then
            local owner        = helpers.display_name(force.name)
            local surfaces     = M.collect_team_surfaces(force)
            local members      = M.collect_team_members(force)
            local leader       = members.leader
            local online       = leader and leader.connected or false
            owners[owner]      = surfaces
            owner_info[owner]  = {
                gps        = "",
                color      = (leader and leader.chat_color) or helpers.WHITE,
                force_name = force.name,
                online     = online,
            }
            order[#order + 1] = owner
        end
    end

    return owners, order, owner_info
end

-- ─── Activity Helpers ─────────────────────────────────────────────────

local function fmt_ago(ticks)
    if ticks < 3600 then return "just now" end
    local s = math.floor(ticks / 60)
    local h = math.floor(s / 3600)
    local m = math.floor((s % 3600) / 60)
    local d = math.floor(h / 24)
    if d >= 1 then return d .. "d ago" end
    if h >= 1 then return h .. "h " .. m .. "m ago" end
    return m .. "m ago"
end
M.fmt_ago = fmt_ago

local function fmt_playtime(ticks)
    local s = math.floor(ticks / 60)
    local h = math.floor(s / 3600)
    local m = math.floor((s % 3600) / 60)
    if h >= 1 then return h .. "h " .. m .. "m" end
    return (m > 0 and m .. "m" or "< 1m")
end

local function player_last_active_tick(player)
    if player.connected then return game.tick end
    return (storage.player_last_seen or {})[player.index]
end

local function team_last_active_tick(member_list)
    local best = nil
    for _, p in ipairs(member_list) do
        local t = player_last_active_tick(p)
        if t and (not best or t > best) then best = t end
    end
    return best
end
M.team_last_active_tick = team_last_active_tick

local function build_activity_tooltip(member_list)
    if #member_list == 0 then return nil end
    local lines = {}
    for _, p in ipairs(member_list) do
        local c = p.chat_color
        local hex = string.format("#%02x%02x%02x",
            math.floor((c.r or c[1] or 0) * 255),
            math.floor((c.g or c[2] or 0) * 255),
            math.floor((c.b or c[3] or 0) * 255))
        local t = player_last_active_tick(p)
        local seen = p.connected and "online now"
            or (t and ("last seen: " .. fmt_ago(game.tick - t)) or "never seen")
        lines[#lines + 1] = "[color=" .. hex .. "]" .. p.name .. "[/color]: Played "
            .. fmt_playtime(p.online_time) .. " (" .. seen .. ")"
    end
    return table.concat(lines, "\n")
end
M.build_activity_tooltip = build_activity_tooltip

return M
