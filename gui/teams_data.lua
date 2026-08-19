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

-- Localised planet name for an internal space-location id, falling back to
-- the Lua-capitalised form when no prototype exists (modded/legacy surfaces).
local function ls_planet_name(id, capitalised)
    return {"?", {"space-location-name." .. id}, capitalised}
end

-- Every entry carries ls_name/ls_location LocalisedString twins next to the
-- plain name/location fields. All display consumers (gui/team_card.lua,
-- /mts-players) use the ls_ twins; the plain fields stay for data/debug
-- consumers and can fold after the post-playtest cleanup confirms none
-- remain.
function M.collect_team_surfaces(force)
    local list = {}

    for _, platform in pairs(force.platforms) do
        local loc_id = platform.space_location and platform.space_location.name
        local hub = platform.hub
        local hub_pos = (hub and hub.valid) and hub.position or nil
        list[#list + 1] = {
            name         = platform.name,
            location     = loc_id or "in transit",
            ls_name      = platform.name,
            ls_location  = loc_id and ls_planet_name(loc_id, loc_id)
                or {"mts-gui.in-transit"},
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
                local ls_planet   = ls_planet_name(planet, planet_disp)
                list[#list + 1] = {
                    name         = planet_disp .. " base",
                    location     = planet_disp,
                    ls_name      = {"mts-gui.planet-base", ls_planet},
                    ls_location  = ls_planet,
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
                    ls_name      = sname,
                    ls_location  = sname,
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
            local ls_planet   = ls_planet_name(base, planet_disp)
            list[#list + 1] = {
                name         = planet_disp .. " base",
                location     = planet_disp,
                ls_name      = {"mts-gui.planet-base", ls_planet},
                ls_location  = ls_planet,
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
    local slot = helpers.team_slot(force_name)
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

--- LocalisedString twin of fmt_ago. Own keys (not the engine time symbols)
--- because the "ago" phrasing must travel with the units for translators to
--- reorder. Plain fmt_ago stays only for the plain activity_info twin
--- (post-playtest cleanup may fold both once no consumer remains).
local function ls_fmt_ago(ticks)
    if ticks < 3600 then return {"mts-gui.ago-just-now"} end
    local s = math.floor(ticks / 60)
    local h = math.floor(s / 3600)
    local m = math.floor((s % 3600) / 60)
    local d = math.floor(h / 24)
    if d >= 1 then return {"mts-gui.ago-days", d} end
    if h >= 1 then return {"mts-gui.ago-hours-minutes", h, m} end
    return {"mts-gui.ago-minutes", m}
end
M.ls_fmt_ago = ls_fmt_ago

local function fmt_playtime(ticks)
    local s = math.floor(ticks / 60)
    local h = math.floor(s / 3600)
    local m = math.floor((s % 3600) / 60)
    if h >= 1 then return h .. "h " .. m .. "m" end
    return (m > 0 and m .. "m" or "< 1m")
end

--- LocalisedString twin of fmt_playtime, composing the engine's translated
--- time symbols like helpers.ls_duration (the stage-1 builders themselves
--- zero-pad minutes, so they aren't byte-identical to fmt_playtime).
local function ls_fmt_playtime(ticks)
    local s = math.floor(ticks / 60)
    local h = math.floor(s / 3600)
    local m = math.floor((s % 3600) / 60)
    if h >= 1 then
        return {"", {"time-symbol-hours-short", h}, " ",
                    {"time-symbol-minutes-short", m}}
    end
    if m > 0 then return {"time-symbol-minutes-short", m} end
    return {"mts-gui.playtime-under-minute"}
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

-- Rich-text member name in the member's chat colour, shared by both tooltip
-- builders below.
local function member_rich_name(p)
    local c = p.chat_color
    local hex = string.format("#%02x%02x%02x",
        math.floor((c.r or c[1] or 0) * 255),
        math.floor((c.g or c[2] or 0) * 255),
        math.floor((c.b or c[3] or 0) * 255))
    return "[color=" .. hex .. "]" .. p.name .. "[/color]"
end

local function build_activity_tooltip(member_list)
    if #member_list == 0 then return nil end
    local lines = {}
    for _, p in ipairs(member_list) do
        local t = player_last_active_tick(p)
        local seen = p.connected and "online now"
            or (t and ("last seen: " .. fmt_ago(game.tick - t)) or "never seen")
        lines[#lines + 1] = member_rich_name(p) .. ": Played "
            .. fmt_playtime(p.online_time) .. " (" .. seen .. ")"
    end
    return table.concat(lines, "\n")
end
M.build_activity_tooltip = build_activity_tooltip

-- Join LocalisedString lines with "\n", chunked below the engine's
-- 20-parameters-per-table limit (a nested table restarts the budget). Two
-- levels cover ~170 lines — far beyond any team's member count.
--- LocalisedString twin of build_activity_tooltip (dual API).
local function ls_build_activity_tooltip(member_list)
    if #member_list == 0 then return nil end
    local lines = {}
    for _, p in ipairs(member_list) do
        local t = player_last_active_tick(p)
        local seen = p.connected and {"mts-tip.seen-online-now"}
            or (t and {"mts-tip.last-seen", ls_fmt_ago(game.tick - t)}
                or {"mts-tip.seen-never"})
        lines[#lines + 1] = {"mts-tip.member-activity", member_rich_name(p),
            ls_fmt_playtime(p.online_time), seen}
    end
    return helpers.ls_join(lines, "\n")
end
M.ls_build_activity_tooltip = ls_build_activity_tooltip

--- Activity summary for a team's member list, shared by the teams GUI cards,
--- the production stats rows, and the disband dialog so they all agree.
--- Returns nil when the team has no recorded activity, else:
---   ago_ticks  - ticks since the most recent member activity
---   any_online - true if any member is connected right now
---   ago_text   - "active" when online, else fmt_ago(ago_ticks)
---   color      - green < 1h, yellow < 24h, red older
---   tooltip    - per-member playtime/last-seen breakdown
function M.activity_info(member_list)
    local last_tick = team_last_active_tick(member_list)
    if not last_tick then return nil end
    local ago_ticks  = game.tick - last_tick
    local any_online = false
    for _, p in ipairs(member_list) do
        if p.connected then any_online = true; break end
    end
    local color
    if ago_ticks < 216000 then
        color = {0.4, 1.0, 0.4}
    elseif ago_ticks < 5184000 then
        color = {1.0, 0.8, 0.2}
    else
        color = {1.0, 0.4, 0.4}
    end
    return {
        ago_ticks  = ago_ticks,
        any_online = any_online,
        ago_text   = any_online and "active" or fmt_ago(ago_ticks),
        color      = color,
        tooltip    = build_activity_tooltip(member_list),
    }
end

--- LocalisedString twin of activity_info: same shape, with ago_text and
--- tooltip as LocalisedStrings. Drop-in for the plain version as its
--- consumers (team_card, stats, admin command) migrate (dual API).
function M.ls_activity_info(member_list)
    local info = M.activity_info(member_list)
    if not info then return nil end
    info.ago_text = info.any_online and {"mts-gui.activity-active"}
        or ls_fmt_ago(info.ago_ticks)
    info.tooltip  = ls_build_activity_tooltip(member_list)
    return info
end

return M
