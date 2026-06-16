-- Multi-Team Support - compat/mts_dimension_warp.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- Support for the MTS Dimension Warp (MDW) mod. Each team spawns DIRECTLY on
-- its own neo-nauvis platform world as warp #0 -- never on nauvis. neo-nauvis
-- is MDW's purpose-built hidden starting planet (prototypes/planet/neo-nauvis.lua).
--
-- Why this is the highest-precedence compat and why it fixes the platform bug
-- ───────────────────────────────────────────────────────────────────────────
-- nauvis variants are clone-mirrored (compat/clone_mirror.lua), which would
-- overwrite the platform tiles MDW lays. neo-nauvis is NOT a clone target, so
-- the tiles survive. We therefore create the home as an EPHEMERAL, non-variant
-- surface via team_surfaces.create_team_surface. The engine raises
-- on_surface_created -> remote_api.raise_team_surface_created -> on_team_surface_created,
-- which MDW already listens to and uses to lay the warp platform. So we do NOT
-- lay any tiles here; creating the surface is enough to trigger MDW's adoption.
--
-- Determinism / fairness: every team's warp #0 uses the SAME map_gen_settings
-- and the SAME seed (nauvis's seed), so all teams start on an identical world.
--
-- Surface naming: "mdw-<force>-w0" (e.g. "mdw-team-1-w0"). This is NON-VARIANT:
-- it does not match mts-<planet>-N or team-N-<planet>, so normalize_variant_seed
-- leaves the caller's seed intact.
--
-- storage.player_surfaces[player_index] = {name = surface_name, planet = "neo-nauvis"}

local compat_utils  = require("compat.compat_utils")
local team_surfaces = require("scripts.team_surfaces")
local vanilla       = require("compat.vanilla")
local helpers       = require("scripts.helpers")
-- Control stage does NOT have table.deepcopy by default (it's a data-stage /
-- util lualib helper). Require util explicitly for util.table.deepcopy.
local util          = require("util")

local mts_dimension_warp = {}

local NEO_NAUVIS = "neo-nauvis"

--- Returns true when MTS Dimension Warp compat should be used.
--- Active whenever the mts-dimension-warp mod is loaded.
function mts_dimension_warp.is_active()
    return script.active_mods["mts-dimension-warp"] ~= nil
end

mts_dimension_warp.planet_display_name    = compat_utils.planet_display_name
-- Reuse the shared teleport path: MDW's pending teleports live in the same
-- storage.pending_vanilla_tp queue, so process_pending_teleports == compat_utils'.
mts_dimension_warp.process_pending_teleports = compat_utils.process_pending_teleports

--- Spawn `player` directly onto their team's neo-nauvis warp #0 platform world.
---
--- Creates the home via team_surfaces.create_team_surface, which fires
--- on_surface_created and lets MDW adopt it + lay the platform tiles. Then we
--- stamp player_surfaces / pending_vanilla_tp exactly like compat_utils so the
--- deferred teleport (next tick) drops the player onto the new surface.
---
--- Falls back to vanilla.setup_player_surface if neo-nauvis is missing or the
--- create fails, so spawning never hard-fails.
function mts_dimension_warp.setup_player_surface(player)
    local planet = game.planets and game.planets[NEO_NAUVIS]
    if not (planet and planet.valid) then
        helpers.diag("mts_dimension_warp.setup_player_surface: neo-nauvis planet "
            .. "missing -> vanilla fallback", player)
        vanilla.setup_player_surface(player)
        return
    end

    -- Deterministic per-team-identical settings: neo-nauvis's own map_gen plus
    -- nauvis's seed, so every team's warp #0 generates the same world (fair).
    local mgs = util.table.deepcopy(planet.prototype.map_gen_settings)
    local nauvis = game.surfaces["nauvis"]
    mgs.seed = nauvis and nauvis.map_gen_settings.seed or 0

    local surf_name = team_surfaces.create_team_surface(player.force.name, {
        planet           = NEO_NAUVIS,
        name             = "mdw-" .. player.force.name .. "-w0",
        map_gen_settings = mgs,
    })

    local surface = surf_name and game.surfaces[surf_name]
    if not (surface and surface.valid) then
        helpers.diag("mts_dimension_warp.setup_player_surface: create_team_surface "
            .. "failed -> vanilla fallback", player)
        vanilla.setup_player_surface(player)
        return
    end

    -- Mirror compat_utils.setup_player_surface bookkeeping so the rest of MTS
    -- (teleport queue, home lookups) treats this surface as the player's home.
    storage.player_surfaces = storage.player_surfaces or {}
    storage.player_surfaces[player.index] = {name = surf_name, planet = NEO_NAUVIS}

    storage.pending_vanilla_tp = storage.pending_vanilla_tp or {}
    storage.pending_vanilla_tp[player.index] = surface
end

return mts_dimension_warp
