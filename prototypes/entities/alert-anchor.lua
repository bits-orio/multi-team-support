-- Multi-Team Support - prototypes/entities/alert-anchor.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- A hidden, inert per-team anchor entity for force alerts. 2.1's
-- LuaForce::add_custom_alert needs an entity to point at, and stock MTS has no
-- guaranteed per-team entity (the passive radar exists only when consumer mods
-- request one). Placed lazily by scripts/pause/notify.lua at the team's spawn
-- immediately before an alert is raised, and NEVER trusted to survive:
-- consumer mods script-kill entities (cave-collapse die() bypasses both
-- destructible=false and protected) and retire surfaces, so it is re-ensured
-- on every use and simply dies with its surface. Deliberately NOT
-- Space-Age-gated -- alerts are base API.

local anchor = table.deepcopy(data.raw["simple-entity-with-owner"]["simple-entity-with-owner"])

anchor.name = "mts-alert-anchor"

-- Invisible + inert: no icon, no collision, no selection, no map marker, no
-- player interaction. Placed by script, seen only by the alert system.
anchor.icon      = nil
anchor.icon_size = nil
anchor.icons     = {util.empty_icon()}
anchor.collision_box  = {{0, 0}, {0, 0}}
anchor.selection_box  = {{0, 0}, {0, 0}}
anchor.collision_mask = {layers = {}}
anchor.flags = {
    "placeable-off-grid",
    "not-on-map",
    "not-blueprintable",
    "not-deconstructable",
    "not-upgradable",
    "not-flammable",
    "not-in-kill-statistics",
}
anchor.hidden = true
anchor.hidden_in_factoriopedia = true
anchor.minable = nil
anchor.placeable_by = nil
anchor.created_smoke = nil
anchor.water_reflection = nil

-- No visible graphics in any variant slot.
local empty = {
    filename = "__core__/graphics/empty.png",
    priority = "extra-high",
    width  = 1,
    height = 1,
}
anchor.picture    = empty
anchor.pictures   = nil
anchor.animations = nil
anchor.lower_pictures = nil

data:extend{anchor}
