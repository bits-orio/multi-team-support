-- Multi-Team Support - prototypes/entities/passivize-radars.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- Turns every "scanning" radar into a passive one: it keeps the local ring it
-- always reveals while working (max_distance_of_nearby_sector_revealed) but no
-- longer runs the rotating sector scan (max_distance_of_sector_revealed) that
-- permanently charts chunks far out from the radar.
--
-- WHY: on a multi-team server each team blankets its territory with radars, and
-- an active radar permanently charts a ~14-chunk-radius disc; the union across
-- ~20 teams is a serious save-size and UPS sink. Passivizing bounds that growth
-- while preserving the thing players actually place radars for -- a stable patch
-- of local visibility.
--
-- Gated by the "mts_passive_radars" startup setting (default on). Runs at
-- data-final-fixes so it also catches radars added by other mods.
--
-- Mechanism: clamp the sector-scan radius DOWN to the radar's own nearby-reveal
-- radius. This is deliberately not "set to 0":
--   * Setting the sector scan to 0 proved unreliable in practice (see the note
--     in passive-radar.lua) -- a bounded scan equal to the nearby ring reliably
--     charts exactly the local bubble and never crawls outward.
--   * Clamping to each radar's OWN nearby radius makes the rule self-preserving:
--     our hidden mts-passive-radar (nearby 8 / sector 8) is left untouched, and
--     any modded radar keeps its intended local footprint.
--   * Radars with no nearby reveal (nearby == 0) are purpose-built scanners
--     whose entire job is charting; clamping them to 0 would make them useless
--     rather than passive, so we leave them alone.
-- Energy: ONLY the base-game radar is dropped to 50 kW (from 300 kW) -- with no
-- wide sector scan to run it does far less work. Modded radars keep their own
-- energy_usage untouched: a flat 50 kW would flatten deliberate mod tiers (e.g.
-- K2's 2 MW advanced radar sustaining an 8-chunk bubble would cost the same as
-- a vanilla radar). The scan clamp alone already delivers the save-bloat fix,
-- which is this feature's goal -- rebalancing other mods' power economy is not.

local PASSIVE_ENERGY_USAGE = "50kW"

if not settings.startup["mts_passive_radars"].value then return end

for _, radar in pairs(data.raw["radar"] or {}) do
    local nearby = radar.max_distance_of_nearby_sector_revealed or 0
    local sector = radar.max_distance_of_sector_revealed or 0
    if nearby > 0 and sector > nearby then
        radar.max_distance_of_sector_revealed = nearby
        if radar.name == "radar" then
            radar.energy_usage = PASSIVE_ENERGY_USAGE
        end

        -- Relabel so the tooltip matches the new behavior. Prefix the radar's
        -- OWN name (fall back to its entity-name key when it has no explicit
        -- localised_name) so vanilla reads "Passive Radar" while a modded radar
        -- keeps its identity ("Passive <Name>") instead of all collapsing to one
        -- label. Description is replaced with the generic passive one. The
        -- locale keys are "mts-passivized-*", deliberately NOT the hidden
        -- mts-passive-radar entity's name, so they never alias its own
        -- entity-name/entity-description lookups.
        local orig_name = radar.localised_name or {"entity-name." .. radar.name}
        radar.localised_name = {"entity-name.mts-passivized-radar-prefix", orig_name}
        radar.localised_description = {"entity-description.mts-passivized-radar"}

        -- Rename the placer item(s) to match. Items without an explicit
        -- localised_name usually inherit the entity name via place_result, but
        -- a mod that ships an explicit item-name locale entry would otherwise
        -- keep its stale label in the inventory/crafting menu while the placed
        -- entity says "Passive". Recipes follow their main product, so they
        -- pick this up for free. (Radar placers are plain "item" prototypes.)
        for _, item in pairs(data.raw["item"] or {}) do
            if item.place_result == radar.name then
                item.localised_name =
                    {"entity-name.mts-passivized-radar-prefix", orig_name}
            end
        end
    end
end
