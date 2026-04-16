-- Multi-Team Support - prototypes/connections.lua
-- Author: bits-orio
-- License: MIT
--
-- Data-stage (final-fixes): creates per-team space-connection prototypes
-- by mirroring the vanilla connection topology for each team slot.
--
-- For every existing space-connection between two base planets (e.g.
-- "nauvis-vulcanus"), we generate N variants, one per team:
--   team 1: mts-nauvis-1 <-> mts-vulcanus-1
--   team 2: mts-nauvis-2 <-> mts-vulcanus-2
--   ...
--
-- We skip connections involving "solar-system-edge" or whose endpoints
-- aren't in our BASE_PLANETS list (e.g. modded custom planets).

local space_age = require("space_age")

assert(data.raw["space-connection"], "connections.lua: no space-connection prototypes loaded")

local max_teams = settings.startup["mts_max_teams"].value

-- Build a set for quick membership check
local base_set = {}
for _, name in ipairs(space_age.BASE_PLANETS) do base_set[name] = true end

--- Build a dynamic icon stack for a connection using the two endpoint icons.
local function make_icons(from_planet, to_planet, base_icons)
    -- If we can't find both endpoints' icons, fall back to the base connection's icons
    local from_p = data.raw.planet[from_planet]
    local to_p   = data.raw.planet[to_planet]
    if not (from_p and from_p.icon and to_p and to_p.icon) then
        return base_icons
    end
    return {
        {icon = from_p.icon, icon_size = from_p.icon_size or 64,
         scale = 1 / 3, shift = {-6, -6}},
        {icon = to_p.icon,   icon_size = to_p.icon_size or 64,
         scale = 1 / 3, shift = { 6,  6}},
    }
end

-- Snapshot existing connections BEFORE we extend data.raw (avoid iterating
-- over our own newly-added prototypes).
local base_connections = {}
for name, conn in pairs(data.raw["space-connection"]) do
    if conn.from and conn.to
       and base_set[conn.from] and base_set[conn.to] then
        base_connections[#base_connections + 1] = {
            name = name,
            proto = conn,
        }
    end
end

for _, info in ipairs(base_connections) do
    local base_conn = info.proto
    for slot = 1, max_teams do
        local variant = table.deepcopy(base_conn)
        local from_variant = space_age.variant_name(base_conn.from, slot)
        local to_variant   = space_age.variant_name(base_conn.to,   slot)
        variant.name  = string.format("%s-to-%s", from_variant, to_variant)
        variant.from  = from_variant
        variant.to    = to_variant
        variant.icons = make_icons(from_variant, to_variant, variant.icons)
        -- Strip any per-prototype icon field that would conflict with icons table
        variant.icon      = nil
        variant.icon_size = nil

        -- Localisation: the deep-copied base connection had a localised_name
        -- pointing at e.g. "space-connection-name.nauvis-vulcanus" which still
        -- works. But if the base relied on auto-lookup by prototype name,
        -- our variant would produce "Unknown key" warnings. Override to
        -- reference the base connection's locale key explicitly.
        variant.localised_name = {
            "", {"space-connection-name." .. info.name}, " (Team " .. slot .. ")",
        }

        data:extend{variant}
    end
end
