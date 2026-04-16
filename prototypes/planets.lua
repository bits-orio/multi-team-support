-- Multi-Team Support - prototypes/planets.lua
-- Author: bits-orio
-- License: MIT
--
-- Data-stage: creates per-team planet variants by deep-copying the base
-- Space Age planets (nauvis, vulcanus, gleba, fulgora, aquilo) N times,
-- where N = mts_max_teams startup setting.
--
-- Each variant is a full planet prototype with:
--   - unique name: "mts-<base>-<slot>" e.g. "mts-nauvis-1"
--   - randomized map_seed_offset so terrain differs per team
--   - orientation offset so they don't overlap visually in the solar system view
--
-- The base planets themselves are left intact; they are locked for team
-- forces at runtime so teams can only see/reach their own variants.

local space_age = require("space_age")

-- Guard: only runs if this file is required (data.lua conditionally requires it)
assert(data.raw.planet, "planets.lua: data.raw.planet is missing")

local max_teams = settings.startup["mts_max_teams"].value

-- Small orientation offsets per base planet so our variants cluster away
-- from the vanilla positions. Values are angles on the 0..1 unit circle.
local BASE_ORIENT_OFFSET = {
    nauvis   = 0.02,
    vulcanus = 0.00,
    gleba    = 0.00,
    fulgora  = 0.08,
    aquilo   = 0.04,
}

for _, base_name in ipairs(space_age.BASE_PLANETS) do
    local base = data.raw.planet[base_name]
    if base then
        local base_orient = BASE_ORIENT_OFFSET[base_name] or 0
        for slot = 1, max_teams do
            local variant = table.deepcopy(base)
            variant.name = space_age.variant_name(base_name, slot)

            -- Randomize map seed so each team's terrain differs
            variant.map_seed_offset = math.random(2 ^ 24)

            -- Keep the variant's order grouped with its base planet in menus
            local original_order = type(base.order) == "string" and base.order or "z"
            variant.order = string.format("%s[%s]", original_order, variant.name)

            -- Spread variants around the solar-system ring so they don't
            -- stack on top of each other in the space map view.
            local offset = base_orient + (slot / (max_teams + 1))
            variant.orientation = offset % 1
            variant.label_orientation = offset % 1

            -- Localisation: without an explicit localised_name, Factorio tries
            -- to look up `space-location-name.mts-<base>-<slot>` which doesn't
            -- exist, producing "Unknown key" warnings everywhere. Build the
            -- name by concatenating the base planet's localised name with the
            -- slot number: e.g. "Vulcanus 1", "Nauvis 2".
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
