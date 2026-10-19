-- Multi-Team Support - compat/clone_wires.lua
-- Author: bits-orio
-- License: MIT
--
-- Puts back the wires that clone_mirror's chunk-by-chunk copy drops.
--
-- clone_mirror copies a team surface from its source planet one chunk at a
-- time, as each chunk generates. LuaSurface.clone_area only keeps a wire whose
-- two ends are cloned in the same call, so on the team copy every copper, red
-- and green wire that crosses a chunk line is lost. An entity that straddles a
-- chunk line is cloned again by every chunk it overlaps, and each re-clone
-- also drops its wires into the chunks copied before it. Generated terrain has
-- no wires, so this shows on maps that start with built structures: a
-- scenario, or a mod that places wired buildings during map generation.
--
-- After each chunk clone, restore() walks the source entities in that chunk
-- that can take a wire and re-creates each wire whose far end lies outside the
-- chunk and already exists on the team surface. Whichever of the two chunks is
-- copied second completes the wire, so generation order does not matter. Each
-- wire keeps its origin. Radar wires are the engine's own and ghost wires are
-- not real connections, so both are left alone.

local clone_wires = {}

local RADAR_ORIGIN = defines.wire_origin.radars

-- Every entity prototype that takes a copper or circuit wire. Built on first
-- use from prototypes, which all peers share, so caching it is desync-safe.
local wired_names

local function get_wired_names()
    if wired_names then return wired_names end
    wired_names = {}
    for name, proto in pairs(prototypes.entity) do
        if proto.get_max_wire_distance() > 0
            or proto.get_max_circuit_wire_distance() > 0 then
            wired_names[#wired_names + 1] = name
        end
    end
    return wired_names
end

local function inside(area, position)
    return position.x >= area.left_top.x and position.x < area.right_bottom.x
        and position.y >= area.left_top.y and position.y < area.right_bottom.y
end

--- The team-surface connector a source wire should reach, or nil when there
--- is nothing to repair: clone_area kept the wire (far end inside the chunk),
--- the far end is on another surface, or its chunk is not copied yet.
local function far_end_on_team(wire, ctx)
    local far = wire.target.owner
    local position = far.position
    if inside(ctx.area, position) then return nil end
    if far.surface.index ~= ctx.source_index then return nil end
    local far_copy = ctx.team.find_entity(far.name, position)
    return far_copy and far_copy.get_wire_connector(wire.target.wire_connector_id, true)
end

--- Re-create on `copy` every wire of `entity` that leaves the chunk.
local function restore_entity(entity, copy, ctx)
    for id, connector in pairs(entity.get_wire_connectors(false)) do
        for _, wire in pairs(connector.real_connections) do
            local origin = wire.origin or defines.wire_origin.player
            local to = origin ~= RADAR_ORIGIN and far_end_on_team(wire, ctx)
            local from = to and copy.get_wire_connector(id, true)
            if from and not from.is_connected_to(to, origin) then
                from.connect_to(to, false, origin)
            end
        end
    end
end

--- Called by clone_mirror right after it clones `area` of `source` onto the
--- same area of `team`.
function clone_wires.restore(source, team, area)
    local ctx = { source_index = source.index, team = team, area = area }
    for _, entity in pairs(source.find_entities_filtered{ area = area, name = get_wired_names() }) do
        local copy = team.find_entity(entity.name, entity.position)
        if copy then restore_entity(entity, copy, ctx) end
    end
end

return clone_wires
