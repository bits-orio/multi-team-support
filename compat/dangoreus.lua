-- Multi-Team Support - compat/dangoreus.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- Compatibility with the dangOreus mod by Mylon
-- (https://mods.factorio.com/mod/dangOreus). dangOreus covers nauvis
-- with ore patches in varied patterns (pie, voronoi, perlin, random,
-- spiral).
--
-- Architecture
-- ────────────
-- Chunk-gen is handled generically by compat/clone_mirror.lua: dangOreus
-- runs on the real nauvis surface (where its hardcoded `surface.name ==
-- "nauvis"` filter accepts), and clone_mirror copies each chunk to
-- team-N-nauvis variants. We don't re-implement dangOreus's pattern
-- algorithms anymore.
--
-- This module retains only the runtime gameplay rules that dangOreus
-- applies AFTER chunk generation, scoped to team surfaces (since
-- dangOreus's own runtime handlers also filter by name and reject
-- team surfaces):
--
--   • on_built_entity     — block non-miner buildings on ore tiles
--   • on_entity_died      — spill resources from destroyed containers
--   • on_nth_tick         — floor-is-lava damage on ore-dense areas
--
-- Plus a small chunk-gen post-step that places a deepwater hole near
-- spawn so offshore pumps work even when dangOreus's starting-radius
-- is shrunk below the vanilla starter lake.

local compat_utils = require("compat.compat_utils")

local dangoreus = {}

-- ─── Constants ────────────────────────────────────────────────────────

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

-- ─── Detection ────────────────────────────────────────────────────────

function dangoreus.is_active()
    return script.active_mods["dangOreus"] ~= nil
end

--- Should this surface be treated as a team nauvis clone / variant?
--- Mirrors the patterns clone_mirror uses for chunk-gen.
dangoreus.is_enabled_surface = compat_utils.is_team_nauvis_variant

-- ─── Storage ──────────────────────────────────────────────────────────

function dangoreus.init_storage()
    storage.dangoreus = storage.dangoreus or {}
    -- flOre tracks per-player escalation distance for floor-is-lava.
    storage.dangoreus.flOre = storage.dangoreus.flOre or {}
end

function dangoreus.init()
    dangoreus.init_storage()
    -- Earlier MTS versions called toggle("nauvis", false) to skip
    -- dangOreus's work on nauvis since no team played there. Under
    -- clone_mirror, nauvis IS the source of truth — its decorated
    -- chunks get copied to team surfaces. Re-enable to undo any
    -- legacy disable left over in saves upgrading from a pre-clone
    -- MTS version. Wrapped in pcall in case dangOreus's remote
    -- interface signature differs across versions.
    if dangoreus.is_active() then
        pcall(function()
            remote.call("dangOreus", "toggle", "nauvis", true)
        end)
    end
end

-- ─── Origin water hole ────────────────────────────────────────────────

--- Run AFTER clone_mirror so the water hole overwrites cloned tiles
--- and ore at the spawn pump location. Only runs for the chunk
--- containing origin.
function dangoreus.on_chunk_generated(event)
    if not dangoreus.is_active() then return end
    local surface = event.surface
    if not dangoreus.is_enabled_surface(surface.name) then return end
    if event.area.left_top.x ~= 0 or event.area.left_top.y ~= 0 then return end
    compat_utils.place_origin_water_hole(surface)
end

-- ─── Anti-building on ore ─────────────────────────────────────────────

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

-- ─── Spill on destroyed container ─────────────────────────────────────

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

-- ─── Floor-is-lava ────────────────────────────────────────────────────

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

-- ─── No-op stubs (kept so callers in control.lua keep working) ────────

--- Previously built per-surface resource_table; now a no-op because
--- clone_mirror handles chunk decoration. Retained as a method so
--- existing call sites in control.lua's on_init / on_surface_created
--- don't error.
function dangoreus.setup_surface(_surface)
    -- intentionally empty
end

return dangoreus
