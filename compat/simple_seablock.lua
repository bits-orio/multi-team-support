-- Multi-Team Support - compat/simple_seablock.lua
-- Author: bits-orio
-- License: MIT
--
-- Compatibility with Simple Seablock by Aronson
-- (https://mods.factorio.com/mod/SimpleSeablock). Every planet starts as a
-- one-tile island with a rock beside it that holds the planet's starting kit
-- (landfill or foundation, agricultural towers, foundries, ...). Mining that
-- rock is how a team gets off the tile.
--
-- Simple Seablock creates the rock from its own on_chunk_generated, only on
-- the surface named exactly after the planet ("vulcanus") and only once per
-- map. A team's planets are named "mts-<planet>-<N>", so it never fires there.
--
-- A team's Nauvis gets its rock anyway: clone_mirror copies chunk (0,0) from
-- the shared nauvis, rock included. The other planets generate on their own,
-- because the shared vulcanus, fulgora, gleba and aquilo surfaces do not exist
-- unless someone creates them, so there is no rock to copy.
--
-- So when chunk (0,0) of a team's planet generates, this puts the planet's
-- rock where Simple Seablock would have, unless the copy already brought one.
-- Every team gets one rock per planet: the kit a single player gets.

local space_age = require("scripts.space_age")

local simple_seablock = {}

local MOD_NAME      = "SimpleSeablock"
-- Simple Seablock's own names: "<planet>-seablock-chest", created at {1, 1}.
local ROCK_SUFFIX   = "-seablock-chest"
local ROCK_POSITION = { x = 1, y = 1 }

function simple_seablock.is_active()
    return script.active_mods[MOD_NAME] ~= nil
end

--- Run AFTER clone_mirror, so a rock it copied from the shared planet counts.
function simple_seablock.on_chunk_generated(event)
    if event.position.x ~= 0 or event.position.y ~= 0 then return end
    if not simple_seablock.is_active() then return end
    local surface = event.surface
    local base = space_age.parse_variant(surface.name)
    if not base then return end

    local rock = base .. ROCK_SUFFIX
    -- A planet from another mod has no rock: Simple Seablock leaves it alone.
    if not prototypes.entity[rock] then return end
    if surface.count_entities_filtered{ name = rock, area = event.area, limit = 1 } > 0 then return end
    surface.create_entity{ name = rock, position = ROCK_POSITION }
end

return simple_seablock
