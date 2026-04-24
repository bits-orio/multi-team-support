-- Multi-Team Support - compat/dangoreus.lua
-- Author: bits-orio
-- License: MIT
--
-- Compatibility with the dangOreus mod by Mylon
-- (https://mods.factorio.com/mod/dangOreus). dangOreus covers the map with
-- ore patches in varied patterns (pie, voronoi, perlin, random, spiral).
--
-- Why this module exists
-- ─────────────────────
-- dangOreus only initializes its per-surface state for "nauvis" in its own
-- divOresity_init, and its remote interface (`toggle`) only sets the
-- enabled flag — it does NOT initialize the resource_table / old_resources
-- structures the chunk generator needs. That makes the documented remote
-- hook insufficient for per-team clone surfaces (team-N-nauvis) or
-- Space-Age variant nauvis planets (mts-nauvis-N), which would crash
-- dangOreus's gOre() on first chunk generation.
--
-- Workaround: port dangOreus's generation/anti-building/cleanup logic into
-- this compat module, operating on OUR storage namespace. We also disable
-- dangOreus on the default shared nauvis (via its remote interface) since
-- no team plays there anyway. Everything derived from dangOreus is used
-- under MIT license (same as this mod).
--
-- Storage schema (under storage.dangoreus):
--   resource_table[surface_name] = {easy = {...}, hard = {...}}
--   old_resources [surface_name] = {resource_name = true}
--   pie           [surface_name] = angle_offset
--   flOre         [player_name]  = distance_multiplier
--   rand_vecs     = {x1, y1, x2, y2, scale}   -- for voronoi
--   perlin.permutation2 = {0..511 -> byte}    -- shuffled hash table

local helpers = require("scripts.helpers")

local dangoreus = {}

-- ─── Constants (mirror dangOreus) ─────────────────────────────────────

local ORE_SCALING   = 0.78
local LINEAR_SCALAR = 12
local XFER_FACTOR   = 3.0
local RING_SIZE     = 200.0
local WOBBLE_DEPTH  = 40.0
local WOBBLE_FACTOR = 6.0
local WOBBLE_SCALE  = 0.7

local RELATIVE_COVERAGE = {
    ["iron-ore"]    = 1.3,
    ["copper-ore"]  = 1.1,
    ["coal"]        = 0.5,
    ["stone"]       = 0.4,
    ["uranium-ore"] = 0.06,
}

-- Deepwater hole placed near origin on every team surface. Guarantees
-- offshore-pump access even when the user shrinks dangOreus's
-- starting-radius so far that vanilla's starter lake ends up buried
-- under ore. The hole is offset diagonally from spawn (0,0) so players
-- don't land on water and drown, and kept entirely within the origin
-- chunk (tiles 0..31) so it's placed atomically during that chunk's
-- generation event.
local ORIGIN_WATER_TILE_NAME  = "deepwater"
local ORIGIN_WATER_HOLE_SIZE  = 4            -- N × N tile square
local ORIGIN_WATER_HOLE_ORIGIN = {x = 3, y = 3}  -- top-left tile (offset from spawn)

local ORIGIN_WATER_TILE_POSITIONS = {}
for dy = 0, ORIGIN_WATER_HOLE_SIZE - 1 do
    for dx = 0, ORIGIN_WATER_HOLE_SIZE - 1 do
        ORIGIN_WATER_TILE_POSITIONS[#ORIGIN_WATER_TILE_POSITIONS + 1] = {
            ORIGIN_WATER_HOLE_ORIGIN.x + dx,
            ORIGIN_WATER_HOLE_ORIGIN.y + dy,
        }
    end
end

local DANGORE_EXCEPTIONS = {
    ["mining-drill"]     = true,
    ["car"]              = true,
    ["spider-vehicle"]   = true,
    ["locomotive"]       = true,
    ["cargo-wagon"]      = true,
    ["fluid-wagon"]      = true,
    ["artillery-wagon"]  = true,
    ["tile-ghost"]       = true,
    ["rail-support"]     = true,
    ["rail-ramp"]        = true,
    ["rail-signal"]      = true,
    ["rail-chain-signal"]= true,
}

local DANGORE_EASY_EXCEPTIONS = {
    ["transport-belt"]     = true,
    ["underground-belt"]   = true,
    ["splitter"]           = true,
    ["electric-pole"]      = true,
    ["container"]          = true,
    ["logistic-container"] = true,
    ["pipe"]               = true,
    ["pipe-to-ground"]     = true,
    ["pump"]               = true,
    ["wall"]               = true,
    ["gate"]               = true,
    ["inserter"]           = true,
}

-- Perlin noise distribution table (measured once by dangOreus author,
-- used to translate perlin output into ore-selection thresholds).
-- Copied verbatim from dangOreus's perlin.lua perlin.MEASURED.
-- Stored as an ordered array of {threshold, frequency} pairs so the
-- order of iteration is deterministic (the original used a keyed table
-- which pairs() iterates in unspecified order — a latent bug).
local PERLIN_MEASURED = {
    {-0.8,   3e-06},     {-0.78,  1.9e-05},   {-0.76,  2.26e-05},
    {-0.74,  7.85e-05},  {-0.72,  6.54e-05},  {-0.7,   0.0001065},
    {-0.68,  0.0001422}, {-0.66,  0.0001748}, {-0.64,  0.0003068},
    {-0.62,  0.0005037}, {-0.6,   0.0006998}, {-0.58,  0.0009218},
    {-0.56,  0.0015398}, {-0.54,  0.002261},  {-0.52,  0.0029764},
    {-0.5,   0.0041172}, {-0.48,  0.0074905}, {-0.46,  0.0065377},
    {-0.44,  0.0067735}, {-0.42,  0.0071103}, {-0.4,   0.0077329},
    {-0.38,  0.0086249}, {-0.36,  0.0088168}, {-0.34,  0.0098334},
    {-0.32,  0.0121038}, {-0.3,   0.0142444}, {-0.28,  0.0175389},
    {-0.26,  0.0200083}, {-0.24,  0.0229865}, {-0.22,  0.023516},
    {-0.2,   0.0224692}, {-0.18,  0.0218644}, {-0.16,  0.023464},
    {-0.14,  0.0295019}, {-0.12,  0.0312897}, {-0.1,   0.0300214},
    {-0.08,  0.0299038}, {-0.06,  0.0295616}, {-0.04,  0.0300028},
    {-0.02,  0.0300583}, {0,      0.0344869}, {0.02,   0.0339126},
    {0.04,   0.0305977}, {0.06,   0.0292206}, {0.08,   0.0287079},
    {0.1,    0.0287141}, {0.12,   0.0292377}, {0.14,   0.0308711},
    {0.16,   0.0289125}, {0.18,   0.0227944}, {0.2,    0.0221353},
    {0.22,   0.0224589}, {0.24,   0.0243225}, {0.26,   0.0243281},
    {0.28,   0.0202056}, {0.3,    0.0179745}, {0.32,   0.0145356},
    {0.34,   0.0117213}, {0.36,   0.0100536}, {0.38,   0.0090039},
    {0.4,    0.0083324}, {0.42,   0.0082711}, {0.44,   0.0074277},
    {0.46,   0.0068863}, {0.48,   0.00662},   {0.5,    0.0070714},
    {0.52,   0.0038948}, {0.54,   0.002906},  {0.56,   0.0024376},
    {0.58,   0.0017182}, {0.6,    0.0013078}, {0.62,   0.000955},
    {0.64,   0.0007262}, {0.66,   0.000569},  {0.68,   0.0004113},
    {0.7,    0.0002829}, {0.72,   0.0001852}, {0.74,   0.0001868},
    {0.76,   0.0001051}, {0.78,   6.05e-05},  {0.8,    2.32e-05},
    {0.82,   1.84e-05},  {0.84,   4e-06},     {0.86,   6.4e-06},
    {0.88,   4.5e-06},
}

-- ─── Detection ────────────────────────────────────────────────────────

--- Is dangOreus mod loaded?
function dangoreus.is_active()
    return script.active_mods["dangOreus"] ~= nil
end

--- Should this surface be treated as a team nauvis clone / variant?
--- We apply dangOreus behavior to: "team-N-nauvis" (base 2.0 clones) and
--- "mts-nauvis-N" (Space Age nauvis variants). All other surfaces — other
--- planets, space platforms, voidblock surfaces — are skipped.
function dangoreus.is_enabled_surface(surface_name)
    if not surface_name then return false end
    if surface_name:find("^team%-%d+%-nauvis$") then return true end
    if surface_name:find("^mts%-nauvis%-%d+$")  then return true end
    return false
end

-- ─── Storage ──────────────────────────────────────────────────────────

function dangoreus.init_storage()
    storage.dangoreus = storage.dangoreus or {}
    local s = storage.dangoreus
    s.resource_table = s.resource_table or {}
    s.old_resources  = s.old_resources  or {}
    s.pie            = s.pie            or {}
    s.flOre          = s.flOre          or {}
    s.perlin         = s.perlin         or {}
end

-- ─── Perlin ───────────────────────────────────────────────────────────

-- Ken Perlin's canonical permutation. Copied verbatim from dangOreus.
local PERMUTATION_BASE = {
    151,160,137,91,90,15,131,13,201,95,96,53,194,233,7,225,140,36,103,30,
    69,142,8,99,37,240,21,10,23,190,6,148,247,120,234,75,0,26,197,62,94,
    252,219,203,117,35,11,32,57,177,33,88,237,149,56,87,174,20,125,136,
    171,168,68,175,74,165,71,134,139,48,27,166,77,146,158,231,83,111,229,
    122,60,211,133,230,220,105,92,41,55,46,245,40,244,102,143,54,65,25,63,
    161,1,216,80,73,209,76,132,187,208,89,18,169,200,196,135,130,116,188,
    159,86,164,100,109,198,173,186,3,64,52,217,226,250,124,123,5,202,38,
    147,118,126,255,82,85,212,207,206,59,227,47,16,58,17,182,189,28,42,
    223,183,170,213,119,248,152,2,44,154,163,70,221,153,101,155,167,43,
    172,9,129,22,39,253,19,98,108,110,79,113,224,232,178,185,112,104,218,
    246,97,228,251,34,242,193,238,210,144,12,191,179,162,241,81,51,145,
    235,249,14,239,107,49,192,214,31,181,199,106,157,184,84,204,176,115,
    121,50,45,127,4,150,254,138,236,205,93,222,114,67,29,24,72,243,141,
    128,195,78,66,215,61,156,180,
}

local function perlin_shuffle()
    local perm = {}
    for i = 1, 256 do perm[i] = PERMUTATION_BASE[i] end
    for i = 1, 256 do
        local a = math.random(256)
        perm[i], perm[a] = perm[a], perm[i]
    end
    local perm2 = {}
    for i = 0, 255 do
        perm2[i]       = perm[i + 1]
        perm2[i + 256] = perm[i + 1]
    end
    storage.dangoreus.perlin.permutation2 = perm2
end

local function perlin_fade(t)
    return t * t * t * (t * (t * 6 - 15) + 10)
end

local function perlin_lerp(t, a, b) return a + t * (b - a) end

local function perlin_grad(hash, x, y, z)
    local h = hash % 16
    if     h == 0x0 then return  x + y
    elseif h == 0x1 then return -x + y
    elseif h == 0x2 then return  x - y
    elseif h == 0x3 then return -x - y
    elseif h == 0x4 then return  x + z
    elseif h == 0x5 then return -x + z
    elseif h == 0x6 then return  x - z
    elseif h == 0x7 then return -x - z
    elseif h == 0x8 then return  y + z
    elseif h == 0x9 then return -y + z
    elseif h == 0xA then return  y - z
    elseif h == 0xB then return -y - z
    elseif h == 0xC then return  y + x
    elseif h == 0xD then return -y + z
    elseif h == 0xE then return  y - x
    else return -y - z
    end
end

local function perlin_noise(x, y, z)
    z = z or 0
    local xi = bit32.band(math.floor(x), 255)
    local yi = bit32.band(math.floor(y), 255)
    local zi = bit32.band(math.floor(z), 255)
    x = x - math.floor(x)
    y = y - math.floor(y)
    z = z - math.floor(z)
    local u = perlin_fade(x)
    local v = perlin_fade(y)
    local w = perlin_fade(z)
    local p = storage.dangoreus.perlin.permutation2
    local A   = p[xi]   + yi
    local AA  = p[A]    + zi
    local AB  = p[A+1]  + zi
    local B   = p[xi+1] + yi
    local BA  = p[B]    + zi
    local BB  = p[B+1]  + zi
    return perlin_lerp(w,
        perlin_lerp(v,
            perlin_lerp(u, perlin_grad(p[AA],   x,   y,   z),
                            perlin_grad(p[BA],   x-1, y,   z)),
            perlin_lerp(u, perlin_grad(p[AB],   x,   y-1, z),
                            perlin_grad(p[BB],   x-1, y-1, z))),
        perlin_lerp(v,
            perlin_lerp(u, perlin_grad(p[AA+1], x,   y,   z-1),
                            perlin_grad(p[BA+1], x-1, y,   z-1)),
            perlin_lerp(u, perlin_grad(p[AB+1], x,   y-1, z-1),
                            perlin_grad(p[BB+1], x-1, y-1, z-1))))
end

-- ─── Voronoi ──────────────────────────────────────────────────────────

local function voronoi(x, y)
    local function dot(vx, vy, ux, uy) return vx * ux + vy * uy end
    local function fract(v) local _, b = math.modf(v); return b end

    local rv = storage.dangoreus.rand_vecs
    local function randAt(px, py)
        local a = {dot(px, py, rv[1], rv[2]), dot(px, py, rv[3], rv[4])}
        a[1] = fract(math.sin(a[1]) * rv[5])
        a[2] = fract(math.sin(a[2]) * rv[5])
        return a
    end

    local function clamp(lo, hi, v)
        if v < lo then return lo end
        if v > hi then return hi end
        return v
    end

    local scale_factor = settings.global["voronoi-scale-factor"].value
    local ring = math.floor(math.sqrt(x * x + y * y) / RING_SIZE)
    local ang  = math.atan2(x, y)
    local gx   = x + math.sin(ang * WOBBLE_FACTOR * (1 + ring * WOBBLE_SCALE)) * WOBBLE_DEPTH
    local gy   = y + math.cos(ang * WOBBLE_FACTOR * (1 + ring * WOBBLE_SCALE)) * WOBBLE_DEPTH
    ring = math.floor(math.sqrt(gx * gx + gy * gy) / RING_SIZE)
    local scale = clamp(4.0, 50.0, ring * 10.0) * scale_factor
    local offx = randAt(scale, 0)[1] * 50.0
    x = x / scale + offx
    y = y / scale

    local close = {}
    local ix, fx = math.modf(x)
    local iy, fy = math.modf(y)
    local best = 100
    for ny = -1, 1 do
        for nx = -1, 1 do
            local p = randAt(ix + ny, iy + nx)
            local dx = ny + p[1] / 1.8 - fx
            local dy = nx + p[2] / 1.8 - fy
            local d = dx * dx + dy * dy
            if d < best then
                best = d
                close[1] = ix + ny
                close[2] = iy + nx
            end
        end
    end

    return randAt(close[1], close[2])[1]
end

-- ─── Ore selection ────────────────────────────────────────────────────

local function get_random_ore(surface_name, hard, random)
    random = random or math.random()
    local table_entry = storage.dangoreus.resource_table[surface_name]
    if not table_entry then return nil end
    local list = hard and table_entry.hard or table_entry.easy
    for _, resource in pairs(list) do
        if random < resource.threshold then return resource.name end
    end
    return nil
end

-- Coordinate scale for perlin.noise input. Feature size ~= 1/SCALE tiles.
-- dangOreus calls perlin.noise(x, y) with integer chunk-coords, but Ken
-- Perlin's algorithm returns 0 at all integer-lattice points (fractional
-- parts of 0 make the interpolation weights zero), which collapses the
-- output to a constant and picks the same ore everywhere. Scaling the
-- input pushes us off the integer lattice and gives varied noise.
local PERLIN_INPUT_SCALE = 1 / 50

local function get_perlin_ore(surface_name, x, y)
    local noise = perlin_noise(x * PERLIN_INPUT_SCALE, y * PERLIN_INPUT_SCALE, 0.5)
    local accum = 0
    for _, pair in ipairs(PERLIN_MEASURED) do
        if noise > pair[1] then
            accum = accum + pair[2]
        else
            break
        end
    end
    return get_random_ore(surface_name, true, accum)
end

-- ─── Per-surface init ─────────────────────────────────────────────────

--- Build resource_table and old_resources for a surface. Called when we
--- first see a team surface (on_surface_created or on_init sweep).
function dangoreus.setup_surface(surface)
    dangoreus.init_storage()
    if not (surface and surface.valid) then return end
    if not dangoreus.is_enabled_surface(surface.name) then return end
    if storage.dangoreus.resource_table[surface.name] then return end  -- already done

    storage.dangoreus.pie[surface.name] = math.random() * (2 + math.pi)

    local solid = {easy = {}, hard = {}}
    local old_resources = {}
    local resources = prototypes.get_entity_filtered{
        {filter = "type", type = "resource"},
        {filter = "autoplace", mode = "and"},
    }
    for name, resource in pairs(resources) do
        local add  = true
        local easy = true
        if not surface.map_gen_settings.autoplace_controls[name] then
            add = false
        end
        if resource.infinite_resource then add = false end
        if resource.mineable_properties.products then
            for _, product in pairs(resource.mineable_properties.products) do
                if product.type == "fluid" then add = false end
            end
        end
        if resource.mineable_properties.required_fluid then easy = false end
        if add then
            local cov = RELATIVE_COVERAGE[name] or 1
            if easy then solid.easy[name] = cov end
            local fluid_key = resource.mineable_properties.required_fluid or "none"
            solid.hard[fluid_key] = solid.hard[fluid_key] or {}
            solid.hard[fluid_key][name] = cov
            old_resources[name] = true
        end
    end

    -- Normalize into cumulative-threshold arrays
    local norm = {easy = {}, hard = {}}
    local easy_total, hard_total = 0, 0
    for _, cov in pairs(solid.easy) do easy_total = easy_total + cov end
    if easy_total == 0 then return end
    local easy_cum = 0
    for name, cov in pairs(solid.easy) do
        local delta = cov / easy_total
        easy_cum = easy_cum + delta
        norm.easy[#norm.easy + 1] = {name = name, threshold = easy_cum}
    end
    for _, list in pairs(solid.hard) do
        for _, cov in pairs(list) do hard_total = hard_total + cov end
    end
    local hard_cum = 0
    for fluid, list in pairs(solid.hard) do
        for name, cov in pairs(list) do
            local delta = cov / hard_total
            hard_cum = hard_cum + delta
            norm.hard[#norm.hard + 1] = {name = name, threshold = hard_cum, fluid = fluid}
        end
    end

    storage.dangoreus.resource_table[surface.name] = norm
    storage.dangoreus.old_resources[surface.name]  = old_resources
    log("[multi-team-support:dangoreus] initialized surface " .. surface.name)
end

-- ─── Lifecycle ────────────────────────────────────────────────────────

--- Called from our on_init and on_configuration_changed.
--- Initializes global perlin+voronoi state and disables dangOreus on
--- the default nauvis (since no team plays there).
function dangoreus.init()
    if not dangoreus.is_active() then return end
    dangoreus.init_storage()

    -- One-time global init: voronoi random vectors + perlin permutation
    if not storage.dangoreus.rand_vecs then
        storage.dangoreus.rand_vecs = {
            math.random() * 200.0, math.random() * 200.0,
            math.random() * 200.0, math.random() * 200.0,
            math.random() * 50000.0,
        }
    end
    if not storage.dangoreus.perlin.permutation2 then
        perlin_shuffle()
    end

    -- Disable dangOreus on default nauvis; no team uses it.
    -- Wrapped in pcall in case the remote interface isn't registered yet.
    pcall(function()
        remote.call("dangOreus", "toggle", "nauvis", false)
    end)

    -- Sweep any existing team surfaces that already exist (reload/config change)
    for _, surface in pairs(game.surfaces) do
        dangoreus.setup_surface(surface)
    end
end

-- ─── Origin water hole ────────────────────────────────────────────────

--- Drop a 2x2 deepwater patch at origin. Called only for the chunk that
--- contains origin; placed BEFORE the ore loop so dangOreus's own tile
--- collision check (`tile.collides_with("resource")`) naturally skips
--- the water tiles and no ore is generated on top of them.
local function place_origin_water_hole(surface)
    local tiles = {}
    for _, pos in ipairs(ORIGIN_WATER_TILE_POSITIONS) do
        tiles[#tiles + 1] = {name = ORIGIN_WATER_TILE_NAME, position = pos}
    end
    -- correct_tiles=true keeps transitions clean at the water/land edge;
    -- remove_colliding_entities clears any stray entities on these tiles.
    surface.set_tiles(tiles, true, true, true, false)
end

-- ─── Chunk generation (ported from dangOreus gOre) ─────────────────────

function dangoreus.on_chunk_generated(event)
    local surface = event.surface
    if not dangoreus.is_enabled_surface(surface.name) then return end
    local rtable = storage.dangoreus.resource_table[surface.name]
    if not rtable then
        -- Surface wasn't set up yet (e.g. surface_created event fired before us).
        -- Initialize lazily, then continue.
        dangoreus.setup_surface(surface)
        rtable = storage.dangoreus.resource_table[surface.name]
        if not rtable then return end
    end

    -- Carve the origin water hole before the ore loop runs so dangOreus's
    -- tile-collision check skips these tiles without us having to special-case.
    if event.area.left_top.x == 0 and event.area.left_top.y == 0 then
        place_origin_water_hole(surface)
    end

    local mgs = surface.map_gen_settings
    local old_resources = storage.dangoreus.old_resources[surface.name] or {}
    local oldores = surface.find_entities_filtered{type = "resource", area = event.area}
    for _, v in pairs(oldores) do
        if old_resources[v.name] then v.destroy() end
    end

    local mode = settings.global["dangOre-mode"].value
    local starting_radius = settings.global["starting-radius"].value
    local easy_radius     = settings.global["simple-ore-radius"].value
    local square_mode     = settings.global["square-mode"].value
    local colliding_check = settings.global["non-colliding-resources"].value

    local chunk_type
    if mode == "random" then
        if math.random() > 0.5 then
            local hard = (event.area.left_top.y + 16)^2 + (event.area.left_top.x + 16)^2
                         > easy_radius ^ 2
            chunk_type = get_random_ore(surface.name, hard)
        end
    end

    for x = event.area.left_top.x, event.area.left_top.x + 31 do
        for y = event.area.left_top.y, event.area.left_top.y + 31 do
            local bbox = {{x, y}, {x + 0.5, y + 0.5}}
            if surface.count_entities_filtered{type = "cliff", area = bbox} == 0 then
                local outside_starting
                if square_mode then
                    outside_starting = math.abs(x) >= starting_radius
                                    or math.abs(y) >= starting_radius
                else
                    outside_starting = x * x + y * y >= starting_radius * starting_radius
                end
                if outside_starting then
                    local ore_type
                    if mode == "random" then
                        if chunk_type and math.random() > 0.5 then
                            ore_type = chunk_type
                        else
                            ore_type = get_random_ore(surface.name)
                        end
                    elseif mode == "voronoi" then
                        ore_type = get_random_ore(surface.name, true, voronoi(x, y))
                    elseif mode == "perlin" then
                        ore_type = get_perlin_ore(surface.name, x, y)
                    elseif mode == "pie" then
                        local rad = (math.atan2(y, x) + storage.dangoreus.pie[surface.name])
                                    % (math.pi * 2) / (math.pi * 2)
                        ore_type = get_random_ore(surface.name, true, rad)
                    elseif mode == "spiral" then
                        local rad = (math.atan2(y, x)
                                     + storage.dangoreus.pie[surface.name]
                                     + (x*x + y*y) ^ 0.5 / 100)
                                    % (math.pi * 2) / (math.pi * 2)
                        ore_type = get_random_ore(surface.name, true, rad)
                    end
                    if ore_type and mgs.autoplace_controls
                       and mgs.autoplace_controls[ore_type]
                       and mgs.autoplace_controls[ore_type].richness then
                        local ore_position
                        if colliding_check then
                            ore_position = surface.find_non_colliding_position(ore_type, {x, y}, 1, 1)
                        elseif not surface.get_tile(x, y).collides_with("resource") then
                            ore_position = {x, y}
                        end
                        if ore_position then
                            local distance_sq = square_mode
                                and math.max(math.abs(x), math.abs(y)) ^ 2
                                or  (x * x + y * y)
                            local amount = distance_sq ^ ORE_SCALING / LINEAR_SCALAR
                                           * mgs.autoplace_controls[ore_type].richness
                            amount = math.max(1, amount)
                            surface.create_entity{
                                name = ore_type, amount = amount,
                                position = ore_position,
                                enable_tree_removal  = false,
                                enable_cliff_removal = false,
                            }
                        end
                    end
                end
            end
        end
    end
end

-- ─── Anti-building on ore (ported from dangOre) ────────────────────────

function dangoreus.on_built_entity(event)
    local entity = event.created_entity or event.entity
    if not (entity and entity.valid) then return end
    if not dangoreus.is_enabled_surface(entity.surface.name) then return end

    local entity_name, entity_type = entity.name, entity.type
    if entity_name == "entity-ghost" then
        entity_name, entity_type = entity.ghost_name, entity.ghost_type
    end

    if DANGORE_EXCEPTIONS[entity_name] or DANGORE_EXCEPTIONS[entity_type] then return end
    if string.find(entity_type, "elevated") then return end

    if settings.global["easy-mode"].value
       and (DANGORE_EASY_EXCEPTIONS[entity_name]
            or DANGORE_EASY_EXCEPTIONS[entity_type]
            or string.find(entity_type, "rail")
            or string.find(entity_type, "turret")) then
        return
    end

    -- Skip zero-size entities
    if entity.bounding_box.left_top.x == entity.bounding_box.right_bottom.x
       or entity.bounding_box.left_top.y == entity.bounding_box.right_bottom.y then
        return
    end

    local last_user = entity.last_user
    local ores = entity.surface.count_entities_filtered{
        type = "resource", area = entity.bounding_box,
    }
    if ores > 0 then
        local force = entity.force
        local ttl = force.create_ghost_on_entity_death
        force.create_ghost_on_entity_death = false
        entity.die()
        force.create_ghost_on_entity_death = ttl
        if last_user then
            last_user.print("Cannot build non-miners on resources!")
        end
    end
end

-- ─── Spill on destroyed container (ported from ore_rly) ───────────────

function dangoreus.on_entity_died(event)
    local entity = event.entity
    if not (entity and entity.valid) then return end
    if not dangoreus.is_enabled_surface(entity.surface.name) then return end
    if script.active_mods["SpilledItems"] then return end

    local t = entity.type
    if t == "container" or t == "cargo-wagon"
       or t == "logistic-container" or t == "car" then
        for i = 1, 255 do
            local inv = entity.get_inventory(i)
            if inv then
                for _, stack in pairs(inv.get_contents()) do
                    entity.surface.spill_item_stack{
                        position = entity.position, stack = stack,
                    }
                end
            end
        end
    end
end

-- ─── Floor-is-lava (ported from flOre_is_lava) ────────────────────────

function dangoreus.on_nth_tick()
    if not dangoreus.is_active() then return end
    if not settings.global["floor-is-lava"].value then return end
    storage.dangoreus = storage.dangoreus or {}
    storage.dangoreus.flOre = storage.dangoreus.flOre or {}

    local easy_radius = settings.global["simple-ore-radius"].value
    for _, p in pairs(game.connected_players) do
        if p.character and dangoreus.is_enabled_surface(p.surface.name) then
            local position = p.character.position
            if math.abs(position.x) > easy_radius or math.abs(position.y) > easy_radius then
                local distance = storage.dangoreus.flOre[p.name] or 1
                local radius = 5
                local count = p.surface.count_entities_filtered{
                    type = "resource",
                    area = {
                        {position.x - (radius * distance), position.y - (radius * distance)},
                        {position.x + (radius * distance), position.y + (radius * distance)},
                    },
                }
                if count > (distance * radius * 2) ^ 2 * 0.80 then
                    storage.dangoreus.flOre[p.name] = math.min(10, distance + 1)
                    local target = p.vehicle or p.character
                    p.surface.create_entity{
                        name = "acid-stream-worm-medium",
                        target = target,
                        source_position = target.position,
                        position = target.position,
                        duration = 30,
                    }
                    target.health = target.health - 15 * distance
                    if target.health == 0 then target.die() end
                else
                    storage.dangoreus.flOre[p.name] = math.max(distance - 2, 1)
                end
            end
        end
    end
end

return dangoreus
