-- Multi-Team Support - prototypes/connections.lua
-- Author: bits-orio
-- License: MIT
--
-- Data-stage (final-fixes): creates per-team space-connection prototypes
-- by mirroring the vanilla connection topology for each team slot.
--
-- For every vanilla space-connection, we classify the endpoints:
--
--   base  ↔ base  (e.g. "nauvis-vulcanus")
--       Generate N variants, each between the team's per-team planet
--       variants: team 1: mts-nauvis-1 ↔ mts-vulcanus-1, etc.
--
--   base  ↔ shared (e.g. "aquilo-solar-system-edge")
--       The shared endpoint (solar-system-edge, shattered-planet) is NOT
--       duplicated per team — it's a single shared location every team
--       travels to. We generate N variants that rewrite only the planet
--       side: team 1: mts-aquilo-1 ↔ solar-system-edge, etc. This mirrors
--       the Team Starts mod's approach and is what lets each team reach
--       the endgame edge and shattered-planet locations.
--
--   shared ↔ shared (e.g. "solar-system-edge-shattered-planet")
--       No per-team variants needed — the vanilla prototype is already
--       team-agnostic. Every team uses the same connection.
--
--   anything else (modded planets, etc.)
--       Skipped.

local space_age = require("scripts.space_age")

assert(data.raw["space-connection"], "connections.lua: no space-connection prototypes loaded")

local max_teams = settings.startup["mts_max_teams"].value

-- Build a set for quick membership check
local base_set = {}
for _, name in ipairs(space_age.BASE_PLANETS) do base_set[name] = true end

-- Space Age endgame locations that are shared across all teams. They
-- appear as connection endpoints but are never duplicated per team.
local SHARED_LOCATIONS = {
    ["solar-system-edge"] = true,
    ["shattered-planet"]  = true,
}

local function is_base(name)   return base_set[name] == true end
local function is_shared(name) return SHARED_LOCATIONS[name] == true end

--- Look up the icon for an endpoint across planet and space-location
--- prototype tables. Planets live in data.raw.planet; shared locations
--- (solar-system-edge, shattered-planet) live in data.raw["space-location"].
local function endpoint_icon(name)
    local p = data.raw.planet and data.raw.planet[name]
    if p and p.icon then return p.icon, p.icon_size end
    local s = data.raw["space-location"] and data.raw["space-location"][name]
    if s and s.icon then return s.icon, s.icon_size end
    return nil
end

--- Build a dynamic icon stack for a connection using the two endpoint icons.
--- Falls back to the base connection's icons if either endpoint lookup fails.
local function make_icons(from_name, to_name, base_icons)
    local from_icon, from_sz = endpoint_icon(from_name)
    local to_icon,   to_sz   = endpoint_icon(to_name)
    if not (from_icon and to_icon) then
        return base_icons
    end
    return {
        {icon = from_icon, icon_size = from_sz or 64,
         scale = 1 / 3, shift = {-6, -6}},
        {icon = to_icon,   icon_size = to_sz or 64,
         scale = 1 / 3, shift = { 6,  6}},
    }
end

-- Snapshot existing connections BEFORE we extend data.raw (avoid iterating
-- over our own newly-added prototypes). Keep only connections we plan to
-- variantise: base↔base and base↔shared. Shared↔shared stays as vanilla.
local base_connections = {}
for name, conn in pairs(data.raw["space-connection"]) do
    if conn.from and conn.to then
        local from_base   = is_base(conn.from)
        local to_base     = is_base(conn.to)
        local from_shared = is_shared(conn.from)
        local to_shared   = is_shared(conn.to)
        local keep = (from_base and to_base)
            or (from_base and to_shared)
            or (to_base and from_shared)
        if keep then
            base_connections[#base_connections + 1] = {
                name  = name,
                proto = conn,
            }
        end
    end
end

--- Return the per-team endpoint name. Base planets become per-team variants;
--- shared locations pass through unchanged.
local function endpoint_for_slot(name, slot)
    if is_shared(name) then return name end
    return space_age.variant_name(name, slot)
end

for _, info in ipairs(base_connections) do
    local base_conn = info.proto
    for slot = 1, max_teams do
        local variant = table.deepcopy(base_conn)
        local from_variant = endpoint_for_slot(base_conn.from, slot)
        local to_variant   = endpoint_for_slot(base_conn.to,   slot)
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
