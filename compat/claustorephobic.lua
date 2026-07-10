-- Multi-Team Support - compat/claustorephobic.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- Compatibility with ClaustOrephobic (zzz-claustorephobic) by Braxbro
-- (https://mods.factorio.com/mod/zzz-claustorephobic). ClaustOrephobic covers
-- the world in banded ore via pure data-stage noise expressions, with an
-- ore-free clearing (~90 tiles at default settings) around each surface's
-- starting point. Because it is data-stage only, its worldgen and its
-- can't-build-on-ore collision layer apply to every team surface natively --
-- no chunk mirroring or runtime shims are needed.
--
-- What it does NOT guarantee near spawn, and what this module fixes:
--
--   • Crude oil. Oil is ineligible for ClaustOrephobic's banding (its patch
--     isn't AoE-minable), so it keeps its vanilla autoplace -- which never
--     places in the starting area. Teams would have to hike for their first
--     oil. We place one guaranteed crude-oil node at 300% yield, a set
--     distance out from spawn (mts_claust_oil_distance_tiles runtime
--     setting, default 64 tiles ~= 2 chunks).
--
--   • Water. ClaustOrephobic worlds are commonly rolled with water scaled
--     low/none to maximize the ore field. We place the same origin deepwater
--     hole the dangOreus compat uses, so an offshore pump always has a spot.
--
-- Each is placed from its own chunk's on_chunk_generated, AFTER clone_mirror,
-- so it survives the nauvis clone. The synced setting, constant amounts, and
-- a non-colliding search over identical terrain give every team's variant an
-- identical spawn kit (MTS's same-map-per-team goal) -- unless the admin
-- changes the distance between two teams' surface generations.

local compat_utils = require("compat.compat_utils")
local voidblock    = require("compat.voidblock")

local claustorephobic = {}

-- The crude-oil node is targeted `d` tiles out from spawn on the same
-- diagonal as the water hole, where d is the admin-adjustable
-- mts_claust_oil_distance_tiles runtime setting (default 64 ~= 2 chunks:
-- clear of the base start, inside ClaustOrephobic's default ~90-tile ore
-- clearing). Read at chunk-gen time, so team surfaces generated after a
-- change use the new distance. Up to d ~180 the node's chunk falls within
-- MTS's radius-3 spawn pre-generation and exists before the player lands;
-- beyond that it appears when the team first explores that far.
--
-- Placement must keep the node (3x3 box included) inside its own chunk: it
-- is placed when THAT chunk generates, after clone_mirror has processed it,
-- and any part poking into a neighbouring chunk could be wiped by that
-- chunk's later clone pass. Hence the derived search radius and clamp below.
local OIL_YIELD_FACTOR  = 3    -- 300% of the prototype's normal (=100%) amount
local OIL_SEARCH_RADIUS = 13   -- max non-colliding search radius
local OIL_CHUNK_MARGIN  = 2.5  -- keeps the node's 3x3 box off the chunk border

--- Placement derived from the current setting: the tile target (equal x/y
--- putting the node ~d tiles from spawn), the chunk index containing it
--- (chunk (c,c)), and the search radius that keeps results inside that
--- chunk (may be < 1 when the target hugs a chunk border: skip searching).
local function oil_placement()
    local d = settings.global["mts_claust_oil_distance_tiles"].value
    local t = math.floor(d / math.sqrt(2)) + 0.5
    local chunk = math.floor(t / 32)
    local off = t - chunk * 32
    local radius = math.min(OIL_SEARCH_RADIUS, off - OIL_CHUNK_MARGIN, 32 - off - OIL_CHUNK_MARGIN)
    return {x = t, y = t}, chunk, radius
end

-- ─── Detection ────────────────────────────────────────────────────────

function claustorephobic.is_active()
    return script.active_mods["zzz-claustorephobic"] ~= nil
end

-- ─── Origin oil node ──────────────────────────────────────────────────

--- Place one crude-oil node near `target` at OIL_YIELD_FACTOR richness.
--- find_non_colliding_position keeps it off water and off any resource
--- entity (water and resources both collide with the resource layer). When
--- no clear spot exists in radius (or the radius collapsed at a chunk
--- border), force-place at the target clamped into the chunk's safe band --
--- keeping the guarantee, and keeping the node clone-safe.
local function place_spawn_oil(surface, target, chunk, radius)
    local proto = prototypes.entity["crude-oil"]
    if not proto then return end  -- overhaul without crude oil; nothing to place

    local pos = radius >= 1
        and surface.find_non_colliding_position("crude-oil", target, radius, 1)
        or nil
    if not pos then
        local lo = chunk * 32 + OIL_CHUNK_MARGIN
        local hi = chunk * 32 + 32 - OIL_CHUNK_MARGIN
        pos = {
            x = math.min(math.max(target.x, lo), hi),
            y = math.min(math.max(target.y, lo), hi),
        }
    end

    surface.create_entity{
        name     = "crude-oil",
        position = pos,
        amount   = OIL_YIELD_FACTOR * proto.normal_resource_amount,
    }

    -- Clear trees/rocks over the node's 3x3 footprint so a pumpjack can be
    -- dropped straight on it.
    for _, entity in pairs(surface.find_entities_filtered{
        area = {{pos.x - 1.5, pos.y - 1.5}, {pos.x + 1.5, pos.y + 1.5}},
        type = {"tree", "simple-entity"},
    }) do
        entity.destroy()
    end
end

-- ─── Chunk hook ───────────────────────────────────────────────────────

--- Run AFTER clone_mirror so the water hole and oil node survive the nauvis
--- clone. The water hole goes with chunk (0,0); the oil node with the chunk
--- containing its target (see oil_placement for pre-generation coverage).
--- VoidBlock islands are skipped: they're tiny with out-of-map beyond, and a
--- ClaustOrephobic+VoidBlock stack has no autoplaced ore to compensate for.
function claustorephobic.on_chunk_generated(event)
    if not claustorephobic.is_active() then return end
    if voidblock.is_active() then return end
    local surface = event.surface
    if not compat_utils.is_team_nauvis_variant(surface.name) then return end

    local cx, cy = event.position.x, event.position.y
    if cx == 0 and cy == 0 then
        compat_utils.place_origin_water_hole(surface)
    end
    local target, chunk, radius = oil_placement()
    if cx == chunk and cy == chunk then
        place_spawn_oil(surface, target, chunk, radius)
    end
end

return claustorephobic
