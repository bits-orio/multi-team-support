-- Multi-Team Support - landing_pen_terrain.lua
-- Author: bits-orio
-- License: MIT
--
-- Surface creation and chunk generation for the Landing Pen.
-- The pen is a circular island with a lab-dark-2 floor, water moat,
-- grass ring, and out-of-map void beyond.

local landing_pen_terrain = {}

-- ─── Layout Constants ──────────────────────────────────────────────────

local PEN_RADIUS   = 15
local MOAT_OUTER   = PEN_RADIUS + 3
local GRASS_OUTER  = MOAT_OUTER  + 3
local SPAWN_RADIUS = 5
local MAX_SLOTS    = 8
local SURFACE_NAME = "landing-pen"

-- Exported for use by landing_pen.lua
landing_pen_terrain.SURFACE_NAME = SURFACE_NAME
landing_pen_terrain.MAX_SLOTS    = MAX_SLOTS
landing_pen_terrain.SPAWN_RADIUS = SPAWN_RADIUS

-- ─── Tile Generation ───────────────────────────────────────────────────

local function tile_for_distance(r)
    if r < PEN_RADIUS then
        return "lab-dark-2"
    elseif r < MOAT_OUTER then
        return "water"
    elseif r < GRASS_OUTER then
        return "grass-1"
    else
        return "out-of-map"
    end
end

-- ─── Surface Creation ──────────────────────────────────────────────────

--- Create the landing-pen surface with a circular island and ground text.
function landing_pen_terrain.get_or_create_surface()
    if game.surfaces[SURFACE_NAME] then
        return game.surfaces[SURFACE_NAME]
    end

    local surface = game.create_surface(SURFACE_NAME, {
        default_enable_all_autoplace_controls = false,
        autoplace_settings = {
            entity     = {treat_missing_as_default = false, settings = {}},
            tile       = {treat_missing_as_default = false, settings = {}},
            decorative = {treat_missing_as_default = false, settings = {}},
        },
    })
    surface.always_day  = true
    surface.show_clouds = false

    surface.request_to_generate_chunks({x = 0, y = 0}, 2)
    surface.force_generate_chunk_requests()

    rendering.draw_text{
        text = "MULTI-TEAM SUPPORT", surface = surface,
        target = {x = 0, y = -8},
        color = {r = 0.9, g = 0.7, b = 0.3, a = 0.8},
        scale = 5, font = "default-large-bold", alignment = "center",
    }
    rendering.draw_text{
        text = "Same start. Different finish.", surface = surface,
        target = {x = 0, y = -4},
        color = {r = 0.7, g = 0.7, b = 0.7, a = 0.8},
        scale = 3, font = "default-large", alignment = "center",
    }
    rendering.draw_text{
        text = "Spawn when ready", surface = surface,
        target = {x = 0, y = 4},
        color = {r = 1.0, g = 1.0, b = 1.0, a = 0.5},
        scale = 1.5, font = "default", alignment = "center",
    }

    return surface
end

-- ─── Chunk Handler ─────────────────────────────────────────────────────

--- Tiles every chunk on the pen surface with the ring layout.
function landing_pen_terrain.on_chunk_generated(event)
    if event.surface.name ~= SURFACE_NAME then return end

    local area  = event.area
    local tiles = {}
    for x = area.left_top.x, area.right_bottom.x - 1 do
        for y = area.left_top.y, area.right_bottom.y - 1 do
            local r = math.sqrt(x * x + y * y)
            tiles[#tiles + 1] = {name = tile_for_distance(r), position = {x, y}}
        end
    end
    event.surface.set_tiles(tiles)

    for _, entity in ipairs(event.surface.find_entities(area)) do
        if entity.type ~= "character" then
            entity.destroy()
        end
    end
end

-- ─── Spawn Positions ───────────────────────────────────────────────────

--- Map a 0-based slot index to a world position on the spawn ring.
function landing_pen_terrain.get_spawn_position(slot)
    local angle = slot * (2 * math.pi / MAX_SLOTS)
    return {
        x = math.floor(SPAWN_RADIUS * math.cos(angle) + 0.5),
        y = math.floor(SPAWN_RADIUS * math.sin(angle) + 0.5),
    }
end

return landing_pen_terrain
