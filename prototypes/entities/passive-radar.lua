-- Multi-Team Support - prototypes/entities/passive-radar.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- A hidden, powerless passive radar that other MTS-aware mods place (via the
-- mts-v1 `ensure_passive_radar` interface) to keep a team surface live-viewable
-- when nobody is standing on it.
--
-- WHY this exists: a remote/map view only renders chunks that are CHARTED and
-- fog-free for the viewing force. An empty team surface has no standing vision
-- source, so a spectator (a chart-sharing friend of the team) sees a black
-- screen. A character provides live vision; so does a radar. We want a radar's
-- reveal WITHOUT a real radar's power cost or unbounded map charting.
--
-- The Factorio radar prototype has two reveal mechanisms:
--   max_distance_of_nearby_sector_revealed = a ring kept revealed while working.
--   max_distance_of_sector_revealed        = a rotating scan that charts sector
--       by sector out to this radius.
-- The save-bloat hazard is a LARGE sector radius (e.g. vanilla 14) that charts
-- the whole explored map over time. We bound BOTH to the same small radius, so
-- the radar only ever reveals/charts a fixed local bubble around itself -- enough
-- to make the floor viewable, but it never expands to chart the wider map (no
-- unbounded save growth). We deliberately keep the sector scan ON (not 0): a
-- nearby-only reveal proved unreliable in practice, and a bounded sector scan
-- guarantees the floor is actually revealed. Powered from a `void` source so it
-- needs no electricity and never shows in the power graph. Reused by MDW
-- (dimension floors / docks) and BNM. Consumers place several across a base
-- larger than one bubble.

local radar = table.deepcopy(data.raw["radar"]["radar"])

radar.name = "mts-passive-radar"

-- Invisible + inert: no icon, no collision, no selection, no map marker, no
-- player interaction. It is placed by script and never seen or touched.
radar.icon       = nil
radar.icon_size  = nil
radar.icons      = {util.empty_icon()}
radar.collision_box = {{0, 0}, {0, 0}}
radar.selection_box = {{0, 0}, {0, 0}}
radar.collision_mask = {layers = {}}
radar.flags = {
    "placeable-off-grid",
    "not-on-map",
    "not-blueprintable",
    "not-deconstructable",
    "not-upgradable",
    "not-flammable",
    "not-in-kill-statistics",
}
radar.hidden = true
radar.hidden_in_factoriopedia = true
radar.working_sound = nil
radar.minable = nil
radar.placeable_by = nil
radar.radius_minimap_visualisation_color = nil
radar.integration_patch = nil
radar.water_reflection = nil

-- Free power, no emissions: a hidden utility radar must not aggravate biters or
-- show up in the pollution stats. Cheap per-scan energy + a fast usage rate so the
-- bounded scan reveals the local bubble quickly (the void source has effectively
-- unlimited buffer, so these only set the work cadence, not a real cost).
radar.energy_source = {type = "void", emissions_per_minute = {}}
radar.energy_usage = "50kW"
radar.energy_per_sector = "10kJ"
radar.energy_per_nearby_scan = "10kJ"

-- Reveal a BOUNDED local bubble: an always-revealed nearby ring PLUS a sector scan
-- bounded to the same small radius (8 chunks ~= 512 tiles across). The scan is the
-- part that actually guarantees the floor is charted/viewable; bounding it to a
-- fixed radius means it never crawls outward to chart the wider map, so there is no
-- unbounded save growth. Consumers place several radars to cover a base larger than
-- one bubble.
radar.max_distance_of_nearby_sector_revealed = 8
radar.max_distance_of_sector_revealed = 8

-- No visible graphics — placed and seen only by the engine's reveal logic.
radar.pictures = {
    layers = {
        {
            filename = "__core__/graphics/empty.png",
            priority = "extra-high",
            width = 1,
            height = 1,
            direction_count = 1,
        },
    },
}

data:extend{radar}
