-- Multi-Team Support - prototypes/planets.lua
-- Author: bits-orio
-- License: MIT
--
-- Data-stage: creates per-team planet variants by deep-copying every base
-- planet prototype currently in `data.raw.planet`, N times, where
-- N = mts_max_teams startup setting.
--
-- Each variant is a full planet prototype with:
--   • unique name: "mts-<base>-<slot>" e.g. "mts-nauvis-1"
--   • the base planet's own map_seed_offset (kept from the deepcopy), so
--     every team's variant generates identical terrain — including
--     territory demolishers, which clone_mirror can't replicate
--   • orientation offset so they don't overlap visually in the solar
--     system view
--
-- Why iterate `data.raw.planet` instead of a hardcoded list
-- ─────────────────────────────────────────────────────────
-- Hardcoding {nauvis, vulcanus, gleba, fulgora, aquilo} excluded modded
-- planets (Maraxsis, Lignumis, Muluna, etc.) from variant creation —
-- teams would all share the modded planet, defeating the per-team
-- isolation MTS provides. Iterating the live prototype table picks up
-- every planet the mod stack has registered by data-final-fixes.
--
-- Load-order requirement: any mod (or planet library) that registers
-- planets must do so by data-final-fixes. Mods that depend on
-- PlanetsLib already follow this pattern. To guarantee MTS sees them,
-- info.json declares `? PlanetsLib` and similar libraries as optional
-- dependencies — Factorio resolves optional deps to "load before" so
-- their data stages complete before MTS iterates here.
--
-- The base planets themselves are left intact; they are locked for
-- team forces at runtime so teams can only see/reach their own
-- variants. See scripts/planet_map.lua's apply_force_locks.

local space_age = require("scripts.space_age")

assert(data.raw.planet, "planets.lua: data.raw.planet is missing")

local max_teams = settings.startup["mts_max_teams"].value

-- Small orientation offsets for vanilla base planets so our variants
-- cluster away from the visual positions of the base planet in the
-- space map. Values are angles on the 0..1 unit circle. Modded
-- planets fall through to 0; their variants get spread around the
-- ring purely by slot index, which is fine in practice (tested with
-- a few modded-planet combos at 20 teams; no visible overlap).
local BASE_ORIENT_OFFSET = {
    nauvis   = 0.02,
    vulcanus = 0.00,
    gleba    = 0.00,
    fulgora  = 0.08,
    aquilo   = 0.04,
}

for _, base_name in ipairs(space_age.list_base_planets_data()) do
    local base = data.raw.planet[base_name]
    -- list_base_planets_data() guarantees the entry exists, but we
    -- guard anyway in case a mod removes a planet between the
    -- enumeration and our access (rare; defensive).
    if base then
        local base_orient = BASE_ORIENT_OFFSET[base_name] or 0
        for slot = 1, max_teams do
            local variant = table.deepcopy(base)
            variant.name = space_age.variant_name(base_name, slot)

            -- Use the base planet's own seed (not a random one). With the same
            -- seed and the same map_gen_settings, every team's variant generates
            -- byte-identical terrain on its own — including territory demolishers,
            -- which clone_mirror cannot replicate (clone_area destroys segmented
            -- units). This keeps the outer planets consistent across teams WITHOUT
            -- cloning, so their native demolishers survive. Nauvis is still cloned
            -- (its base surface always exists), so its variants stay identical via
            -- clone_mirror regardless of seed.
            variant.map_seed_offset = base.map_seed_offset

            -- Keep the variant's order grouped with its base planet
            -- in menus (so e.g. "mts-nauvis-1..N" appear next to
            -- "nauvis" in any list view that respects order strings).
            local original_order = type(base.order) == "string" and base.order or "z"
            variant.order = string.format("%s[%s]", original_order, variant.name)

            -- Spread variants around the solar-system ring so they
            -- don't stack on top of each other in the space map view.
            local offset = base_orient + (slot / (max_teams + 1))
            variant.orientation = offset % 1
            variant.label_orientation = offset % 1

            -- Localisation: without an explicit localised_name,
            -- Factorio tries to look up
            -- `space-location-name.mts-<base>-<slot>` which doesn't
            -- exist, producing "Unknown key" warnings everywhere.
            -- We concatenate the base planet's localised name with
            -- the slot number: e.g. "Vulcanus 1", "Nauvis 2",
            -- "Lignumis 3". This works for any planet that has a
            -- `space-location-name.<base>` locale entry — vanilla
            -- planets and well-behaved modded ones both qualify.
            variant.localised_name = {
                "", {"space-location-name." .. base_name}, " " .. slot,
            }
            variant.localised_description = {
                "space-location-description." .. base_name,
            }

            data:extend{variant}
        end
    end
end
